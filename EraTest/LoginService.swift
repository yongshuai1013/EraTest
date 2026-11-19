import Foundation
import UIKit
import SideSign
import AnisetteKit

enum LoginServiceError: LocalizedError {
    case noTeams
    case emptyUDID

    var errorDescription: String? {
        switch self {
        case .noTeams: return "登入成功但帳號下沒有任何 Team"
        case .emptyUDID: return "fetchUDID 未回傳 UDID，無法註冊裝置"
        }
    }
}

/// Login + device registration using the 0.6.4-era SideSign, in the same
/// order as SideStore 0.6.4's SignInOperation:
/// authenticate -> fetch team -> register current device.
final class LoginService: @unchecked Sendable {
    static let shared = LoginService()

    // Same defaults SideStore 0.6.4 ships in AppConstants / AnisetteConfigManager.
    private static let clientInfo = "<MacBookPro18,3> <macOS;26.6;25F84> <com.apple.AuthKit/1 (com.apple.dt.Xcode/26.0)>"
    private static let xcodeVersion = "26.0 (26A242)"

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var adiPbURL: URL { documentsURL.appendingPathComponent("adi.pb") }

    private var deviceIdentifier: UUID {
        let key = "eratest.anisetteIdentifier"
        if let stored = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: stored) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }

    /// Fetches fresh anisette data via SideSign's AnisetteDataManager in
    /// remoteODA mode (server list + on-device ADI provisioning through
    /// AnisetteKit), persisting any newly provisioned adi.pb for reuse.
    func fetchAnisetteData() async throws -> AnisetteData {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let baseDir = appSupport
            .appendingPathComponent("EraTest", isDirectory: true)
            .appendingPathComponent(".anisette", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)

        let manager = AnisetteDataManager(baseDirectory: baseDir)
        let headers = AnisetteRequestHeaders().with {
            $0.clientInfo = Self.clientInfo
        }
        let existingAdiPb = try? Data(contentsOf: adiPbURL)
        EraLog.shared.log("[登入] 取得 anisette 資料（remoteODA + 本機 ADI 配置；既有 adi.pb: \(existingAdiPb != nil ? "有" : "無")）…")
        let (data, newAdiPb) = try await manager.fetchAnisetteData(
            mode: .remoteODA(
                sourceURL: URL(string: "https://servers.sidestore.io/servers.json")!,
                fallbackURL: URL(string: "https://zzz.haus/oda.json")
            ),
            identifier: deviceIdentifier,
            existingAdiBlob: existingAdiPb,
            headers: headers
        )
        if let newAdiPb = newAdiPb {
            try? newAdiPb.write(to: adiPbURL, options: .atomic)
            EraLog.shared.log("[登入] 新 adi.pb 已保存（\(newAdiPb.count) bytes）")
        }
        EraLog.shared.log("[登入] anisette 資料已取得")
        return data
    }

    /// Full sequence: anisette -> SRP authenticate (with 2FA handler) ->
    /// fetch teams -> fetchUDID via minimuxer -> register device if needed.
    func signInAndRegisterDevice(appleID: String,
                                 password: String,
                                 pairingContent: String,
                                 twoFactorBridge: TwoFactorBridge) async throws {
        let anisetteData = try await fetchAnisetteData()

        EraLog.shared.log("[登入] 開始 SRP 登入: \(appleID)")
        let authSession = try await DeveloperPortal.shared.authenticate(
            appleID: appleID,
            password: password,
            anisetteData: anisetteData,
            xcodeVersion: Self.xcodeVersion,
            machinePassword: nil,
            accountRepairHandler: DeveloperPortal.defaultAccountRepairHandler,
            verificationHandler: { request in
                try await twoFactorBridge.awaitResponse(for: request)
            }
        )
        EraLog.shared.log("[登入] 登入成功: \(authSession.account.appleID)（\(authSession.account.name)）")

        let teams = try await DeveloperPortal.shared.fetchTeams(for: authSession.account,
                                                                session: authSession.session)
        for team in teams {
            EraLog.shared.log("[登入] Team: \(team.identifier) — \(team.name)")
        }
        guard let team = teams.first else { throw LoginServiceError.noTeams }
        EraLog.shared.log("[登入] 使用 Team: \(team.identifier)")

        EraLog.shared.log("[註冊] 透過 minimuxer 取得裝置 UDID…")
        let fetchedUDID = try await DeviceConnector.shared.fetchUDID(pairingContent: pairingContent)
        guard let udid = fetchedUDID, !udid.isEmpty else { throw LoginServiceError.emptyUDID }
        EraLog.shared.log("[註冊] 裝置 UDID: \(udid)")

        let devices = try await DeveloperPortal.shared.fetchDevices(for: team,
                                                                    types: .all,
                                                                    session: authSession.session)
        if let existing = devices.first(where: { $0.identifier == udid }) {
            EraLog.shared.log("[註冊] 裝置已在 Team 註冊: \(existing.name)（\(existing.identifier)）")
            return
        }
        let deviceName = await MainActor.run { UIDevice.current.name }
        let device = try await DeveloperPortal.shared.registerDevice(
            name: deviceName,
            identifier: udid,
            type: .iPhone,
            team: team,
            session: authSession.session
        )
        EraLog.shared.log("[註冊] 裝置註冊成功: \(device.name)（\(device.identifier)）")
    }
}
