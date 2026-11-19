import Foundation

/// App-wide logger. Every line is appended to Documents/eratest.log and
/// mirrored to an optional UI sink installed by the view controller.
final class EraLog: @unchecked Sendable {
    static let shared = EraLog()

    private let queue = DispatchQueue(label: "com.yongshuai.eratest.log")
    private let fileURL: URL
    var sink: ((String) -> Void)?

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("eratest.log")
    }

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        queue.async { [self] in
            if let data = (line + "\n").data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
            if let sink = self.sink {
                DispatchQueue.main.async { sink(line) }
            }
        }
    }

    func clear() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
