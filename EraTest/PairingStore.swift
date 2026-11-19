import Foundation

enum PairingStoreError: LocalizedError {
    case notUTF8
    case notAPlistDictionary

    var errorDescription: String? {
        switch self {
        case .notUTF8: return "配對檔不是 UTF-8 文字（預期為 XML plist）"
        case .notAPlistDictionary: return "配對檔不是 plist 字典格式"
        }
    }
}

/// Stores the imported lockdown pairing file in Documents and exposes its
/// raw contents (for minimuxer) plus the UDID recorded inside it.
final class PairingStore: @unchecked Sendable {
    static let shared = PairingStore()

    private(set) var pairingContent: String?
    private(set) var pairingUDID: String?

    var isLoaded: Bool { pairingContent != nil }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pairing.plist")
    }

    func restoreFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        _ = try? load(data: data)
    }

    /// Copies the picked file into Documents and parses it.
    /// Returns the UDID found in the plist (empty string when absent).
    @discardableResult
    func importFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        try data.write(to: fileURL, options: .atomic)
        return try load(data: data)
    }

    private func load(data: Data) throws -> String {
        guard let content = String(data: data, encoding: .utf8) else {
            throw PairingStoreError.notUTF8
        }
        let raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = raw as? [String: Any] else {
            throw PairingStoreError.notAPlistDictionary
        }
        let udid = dict["UDID"] as? String
        pairingContent = content
        pairingUDID = udid
        return udid ?? ""
    }
}
