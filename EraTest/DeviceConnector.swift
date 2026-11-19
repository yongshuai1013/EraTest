import Foundation
import Minimuxer

/// Lock-protected storage backing the ConnectionConfigBinding closures
/// (mirrors what SideStore's ConnectionConfig holds for the local-VPN mode).
private final class BindingState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var flags: [String: Bool] = [:]

    func set(_ key: String, _ value: String?) {
        lock.lock()
        values[key] = value
        lock.unlock()
    }

    func get(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return values[key] ?? ""
    }

    func setFlag(_ key: String, _ value: Bool) {
        lock.lock()
        flags[key] = value
        lock.unlock()
    }
}

/// Thin adapter over the 0.6.4-era minimuxer: bind config -> start ->
/// fetchUDID — the same sequence SideStore 0.6.4's AppBootManager runs at
/// launch to validate the pairing file.
final class DeviceConnector: @unchecked Sendable {
    static let shared = DeviceConnector()

    private let state = BindingState()
    private var started = false

    private lazy var binding: ConnectionConfigBinding = ConnectionConfigBinding(
        setTunnelIfaceIp: { [state] value in state.set("ifaceIp", value) },
        setTunnelPeerIp: { [state] value in state.set("peerIp", value) },
        setTunnelPeerSubnetMask: { [state] value in state.set("peerMask", value) },
        setTunnelPeerReachable: { [state] value in state.setFlag("peerReachable", value) },
        setTunnelIfaceSubnetMask: { [state] value in state.set("ifaceMask", value) },
        getRemoteServerIp: { [state] in state.get("remoteServerIp") },
        setRemoteReachable: { [state] value in state.setFlag("remoteReachable", value) },
        getOverrideTunnelPeerIp: { [state] in state.get("overridePeerIp") },
        setOverrideTunnelPeerReachable: { [state] value in state.setFlag("overridePeerReachable", value) },
        getConnectionMode: { .localVPN }
    )

    /// Starts minimuxer with the pairing file (first call only) and returns
    /// the UDID reported by the device gateway (nil when it reports none).
    func fetchUDID(pairingContent: String) async throws -> String? {
        let minimuxer = Minimuxer.shared(backend: .idevice)
        await minimuxer.core.bindConnectionConfig(binding)
        if !started {
            EraLog.shared.log("[連接] 啟動 minimuxer（idevice gateway）…")
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            do {
                try await minimuxer.core.start(pairingFile: pairingContent, mountPath: docs.path)
            } catch let error as MinimuxerError {
                EraLog.shared.log("[連接] start 失敗: \(minimuxer.core.describeError(error))")
                throw error
            }
            started = true
            EraLog.shared.log("[連接] minimuxer 已啟動")
        }
        do {
            return try await minimuxer.core.fetchUDID()
        } catch let error as MinimuxerError {
            EraLog.shared.log("[連接] fetchUDID 失敗: \(minimuxer.core.describeError(error))")
            throw error
        }
    }
}
