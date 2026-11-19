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

    /// Everything the minimuxer has written back through the binding so far
    /// (v2 state dump; nil values surface as （未設定）).
    func snapshot() -> [(key: String, value: String)] {
        lock.lock()
        defer { lock.unlock() }
        var out: [(key: String, value: String)] = []
        for key in ["ifaceIp", "ifaceMask", "peerIp", "peerMask"] {
            out.append((key, values[key] ?? "（未設定）"))
        }
        for key in ["peerReachable", "remoteReachable", "overridePeerReachable"] {
            out.append((key, (flags[key] ?? false) ? "true" : "false"))
        }
        return out
    }
}

/// Thin adapter over the 0.6.4-era minimuxer: bind config -> start ->
/// fetchUDID — the same sequence SideStore 0.6.4's AppBootManager runs at
/// launch to validate the pairing file.
///
/// v2 adds measurement only (version pins and the login path are unchanged):
/// the connection-test path additionally drives `network.refreshEndpoint()`
/// explicitly and dumps the observable minimuxer state around it, and a
/// direct gateway lockdown GetValue test bypasses the usbmuxd device list
/// that fetchUDID depends on.
final class DeviceConnector: @unchecked Sendable {
    static let shared = DeviceConnector()

    private let state = BindingState()
    private var started = false
    private var loggingConfigured = false

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

    private var minimuxer: Minimuxer { Minimuxer.shared(backend: .idevice) }

    /// The pinned minimuxer's own logging (MinimuxerLogging /
    /// DeviceGatewayLogging / MinimuxerCommonLogging) only print()s to the
    /// console — at this pin there is no global log handler/sink to attach
    /// to, and an app cannot capture its own stdout. Enable it anyway (as
    /// SideStore does via minimuxerSetLogging) and substitute observable
    /// state dumps (see dumpMuxerState) for the console stream.
    private func configureLoggingOnce(_ minimuxer: Minimuxer) {
        guard !loggingConfigured else { return }
        loggingConfigured = true
        minimuxer.core.setLogging(true)
        EraLog.shared.log("[muxer] minimuxer 內部日誌已啟用（core.setLogging(true)）；此釘版 logging 僅 print 至主控台、無 handler 可接，改以狀態傾印代替（見後續 [muxer] 行）")
    }

    /// bind (every call, as v1) + start (first call only), in the same
    /// order as SideStore 0.6.4's minimuxerStart: bindConnectionConfig()
    /// then core.start(pairingFile:mountPath:).
    private func bindAndStart(pairingContent: String) async throws {
        let minimuxer = self.minimuxer
        configureLoggingOnce(minimuxer)
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
    }

    /// Starts minimuxer with the pairing file (first call only) and returns
    /// the UDID reported by the device gateway (nil when it reports none).
    /// v1 behavior, unchanged — the login flow uses this path.
    func fetchUDID(pairingContent: String) async throws -> String? {
        try await bindAndStart(pairingContent: pairingContent)
        let minimuxer = self.minimuxer
        do {
            return try await minimuxer.core.fetchUDID()
        } catch let error as MinimuxerError {
            EraLog.shared.log("[連接] fetchUDID 失敗: \(minimuxer.core.describeError(error))")
            throw error
        }
    }

    /// Observable minimuxer state via public API only (substitute for the
    /// console-only internal logs): connection mode, pairing state, the
    /// values the connection manager wrote back through the binding (tunnel
    /// iface / derived peer / reachability), the interface scan as the app
    /// sees it, and a direct TCP probe of the derived peer.
    /// Note: the gateway's usbmuxd get_devices count is not exposed by any
    /// public API at this pin, so it cannot be dumped; fetchUDID's nil vs
    /// value and isReady's failing stage are its observable proxies.
    private func dumpMuxerState(_ minimuxer: Minimuxer, phase: String) async {
        let mode = await minimuxer.core.getConnectionMode()
        EraLog.shared.log("[muxer] 狀態（\(phase)）: connectionMode=.\(mode.rawValue) pairingLoaded=\(minimuxer.core.isPairingFileLoaded) pairingType=\(minimuxer.gateway.pairingFileType) servicePort=\(minimuxer.gateway.servicePort)")
        for entry in state.snapshot() {
            EraLog.shared.log("[muxer] binding.\(entry.key) = \(entry.value)")
        }
        EraLog.shared.log("[muxer] utun 可用: \(minimuxer.network.isUTunAvailable)")
        let ifaces = minimuxer.network.activeInterfaces
        if ifaces.isEmpty {
            EraLog.shared.log("[muxer] activeInterfaces: （空）")
        } else {
            for info in ifaces {
                EraLog.shared.log("[muxer] iface \(info.name) ip=\(info.ip) subnet=\(info.subnet) type=\(info.type.rawValue)")
            }
        }
        let peer = state.get("peerIp")
        if !peer.isEmpty {
            let reachable = minimuxer.core.testDeviceConnection(ifaddr: peer)
            EraLog.shared.log("[muxer] testDeviceConnection(\(peer)) = \(reachable)")
        }
    }

    /// v2 connection-test path: the v1 bind/start sequence, then an explicit
    /// `network.refreshEndpoint()` drive (interface scan + peer probe +
    /// endpoint/gateway update — the step that decides whether the usbmuxd
    /// proxy ever reports a device), state dumps around it, the core's
    /// staged readiness check verbatim, and finally fetchUDID as in v1.
    func runConnectionDiagnostics(pairingContent: String) async throws -> String? {
        try await bindAndStart(pairingContent: pairingContent)
        let minimuxer = self.minimuxer
        await dumpMuxerState(minimuxer, phase: "refresh 前")
        EraLog.shared.log("[連接] 驅動 network.refreshEndpoint()…")
        await minimuxer.network.refreshEndpoint()
        EraLog.shared.log("[連接] refreshEndpoint() 已回傳")
        await dumpMuxerState(minimuxer, phase: "refresh 後")
        let ready = await minimuxer.core.isReady(withNetworkCheck: true, withDDIMountCheck: false)
        switch ready {
        case .success(let ok):
            EraLog.shared.log("[muxer] isReady = success(\(ok))")
        case .failure(let error):
            EraLog.shared.log("[muxer] isReady = failure: \(minimuxer.core.describeError(error))")
        }
        do {
            return try await minimuxer.core.fetchUDID()
        } catch let error as MinimuxerError {
            EraLog.shared.log("[連接] fetchUDID 失敗: \(minimuxer.core.describeError(error))")
            throw error
        }
    }

    /// v2 direct lockdown measurement: bypasses the usbmuxd device list
    /// that fetchUDID reads and performs a real TCP connection + lockdown
    /// handshake + GetValue against the device through the gateway
    /// (performWithTcpService -> lockdownd_connect -> lockdownd_get_value).
    /// Values and gateway errors (code + reason) are logged verbatim.
    func directLockdownTest(pairingContent: String) async {
        let minimuxer = self.minimuxer
        do {
            try await bindAndStart(pairingContent: pairingContent)
        } catch {
            EraLog.shared.log("[直連] minimuxer 啟動失敗，取消直連測試: \(error.localizedDescription) | \(String(describing: error))")
            return
        }
        await dumpMuxerState(minimuxer, phase: "直連測試前")
        for key in ["UniqueDeviceID", "ProductVersion"] {
            do {
                let value = try await minimuxer.gateway.getLockdownValue(key: key)
                EraLog.shared.log("[直連] getLockdownValue(\(key)) = \(value ?? "（nil）")")
            } catch let error as DeviceGatewayError {
                EraLog.shared.log("[直連] getLockdownValue(\(key)) 錯誤 code=\(error.code.rawValue) reason=\(error.reason) | \(error.localizedDescription)")
            } catch {
                EraLog.shared.log("[直連] getLockdownValue(\(key)) 未知錯誤: \(error.localizedDescription) | \(String(describing: error))")
            }
        }
        EraLog.shared.log("[直連] 直接 lockdown 測試結束")
    }
}
