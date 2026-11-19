import Foundation
import SideSign

/// Bridges SideSign's VerificationHandler (an async callback invoked from
/// inside the SRP login flow) to the view controller's 2FA UI: each request
/// is surfaced to the UI, and the flow suspends until the user responds.
final class TwoFactorBridge: @unchecked Sendable {
    /// Invoked on the main queue for every incoming 2FA request.
    var onRequest: ((TwoFactorRequest) -> Void)?

    private let lock = NSLock()
    private var continuation: CheckedContinuation<TwoFactorResponse, Error>?

    func awaitResponse(for request: TwoFactorRequest) async throws -> TwoFactorResponse {
        EraLog.shared.log("[2FA] 收到請求: \(String(describing: request))")
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.onRequest?(request)
            }
        }
    }

    func respond(_ response: TwoFactorResponse) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        EraLog.shared.log("[2FA] 使用者回應: \(String(describing: response))")
        pending?.resume(returning: response)
    }
}
