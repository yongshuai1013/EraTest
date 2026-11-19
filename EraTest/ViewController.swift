import UIKit
import UniformTypeIdentifiers
import SideSign

final class ViewController: UIViewController {
    // Pairing section
    private let pairingStatusLabel = ViewController.bodyLabel()
    private let importButton = ViewController.makeButton("匯入配對檔")

    // Connection section
    private let connectionResultLabel = ViewController.bodyLabel()
    private let testButton = ViewController.makeButton("開始連接測試")

    // Login section
    private let appleIDField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = ViewController.makeButton("登入並註冊裝置")
    private let loginStatusLabel = ViewController.bodyLabel()

    // 2FA sub-section
    private let twoFAContainer = UIStackView()
    private let twoFAInfoLabel = ViewController.bodyLabel()
    private let twoFAMethodStack = UIStackView()
    private let codeField = UITextField()
    private let codeRow = UIStackView()

    // Log section
    private let logTextView = UITextView()
    private let clearLogButton = ViewController.makeButton("清除日誌")

    private let twoFactorBridge = TwoFactorBridge()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        refreshPairingStatus()
        connectionResultLabel.text = "尚未測試"
        loginStatusLabel.text = ""
        EraLog.shared.sink = { [weak self] line in
            self?.appendLog(line)
        }
        twoFactorBridge.onRequest = { [weak self] request in
            self?.presentTwoFactor(request)
        }
        EraLog.shared.log("EraTest 啟動（minimuxer @2e72b199 / SideSign @7f818429+403修法 / AnisetteKit @2b4a643 A10 版）")
    }

    // MARK: - UI construction

    private static func bodyLabel() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        return label
    }

    private static func sectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .boldSystemFont(ofSize: 17)
        return label
    }

    private static func makeButton(_ title: String) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        return UIButton(configuration: config)
    }

    private func buildUI() {
        let scrollView = UIScrollView()
        let content = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])

        // Pairing section
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)
        stack.addArrangedSubview(ViewController.sectionTitle("配對檔"))
        stack.addArrangedSubview(pairingStatusLabel)
        stack.addArrangedSubview(importButton)

        // Connection section
        testButton.addTarget(self, action: #selector(testTapped), for: .touchUpInside)
        stack.addArrangedSubview(ViewController.sectionTitle("連接測試"))
        stack.addArrangedSubview(connectionResultLabel)
        stack.addArrangedSubview(testButton)

        // Login section
        appleIDField.placeholder = "Apple ID"
        appleIDField.borderStyle = .roundedRect
        appleIDField.autocapitalizationType = .none
        appleIDField.autocorrectionType = .no
        appleIDField.textContentType = .username
        appleIDField.keyboardType = .emailAddress
        passwordField.placeholder = "密碼"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        stack.addArrangedSubview(ViewController.sectionTitle("登入與註冊"))
        stack.addArrangedSubview(appleIDField)
        stack.addArrangedSubview(passwordField)
        stack.addArrangedSubview(signInButton)
        stack.addArrangedSubview(loginStatusLabel)

        // 2FA sub-section (hidden until a request arrives)
        twoFAContainer.axis = .vertical
        twoFAContainer.spacing = 8
        twoFAContainer.isHidden = true
        twoFAMethodStack.axis = .vertical
        twoFAMethodStack.spacing = 8
        codeField.placeholder = "驗證碼"
        codeField.borderStyle = .roundedRect
        codeField.keyboardType = .numberPad
        let submitCodeButton = ViewController.makeButton("送出驗證碼")
        submitCodeButton.addTarget(self, action: #selector(submitCodeTapped), for: .touchUpInside)
        codeRow.axis = .horizontal
        codeRow.spacing = 8
        codeRow.addArrangedSubview(codeField)
        codeRow.addArrangedSubview(submitCodeButton)
        let cancelButton = ViewController.makeButton("取消驗證")
        cancelButton.addTarget(self, action: #selector(cancelTwoFATapped), for: .touchUpInside)
        twoFAContainer.addArrangedSubview(ViewController.sectionTitle("雙重驗證"))
        twoFAContainer.addArrangedSubview(twoFAInfoLabel)
        twoFAContainer.addArrangedSubview(twoFAMethodStack)
        twoFAContainer.addArrangedSubview(codeRow)
        twoFAContainer.addArrangedSubview(cancelButton)
        stack.addArrangedSubview(twoFAContainer)

        // Log section
        logTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.isEditable = false
        logTextView.layer.borderWidth = 1
        logTextView.layer.borderColor = UIColor.separator.cgColor
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        logTextView.heightAnchor.constraint(equalToConstant: 280).isActive = true
        clearLogButton.addTarget(self, action: #selector(clearLogTapped), for: .touchUpInside)
        stack.addArrangedSubview(ViewController.sectionTitle("日誌"))
        stack.addArrangedSubview(logTextView)
        stack.addArrangedSubview(clearLogButton)
    }

    // MARK: - Pairing

    private func refreshPairingStatus() {
        if PairingStore.shared.isLoaded {
            pairingStatusLabel.text = "已載入配對檔\nUDID: \(PairingStore.shared.pairingUDID ?? "（plist 內無 UDID 欄位）")"
        } else {
            pairingStatusLabel.text = "尚未匯入配對檔"
        }
    }

    @objc private func importTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.propertyList, UTType.data],
                                                      asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    // MARK: - Connection test

    @objc private func testTapped() {
        view.endEditing(true)
        guard let pairing = PairingStore.shared.pairingContent else {
            connectionResultLabel.text = "請先匯入配對檔"
            return
        }
        setBusy(true)
        connectionResultLabel.text = "連接中…"
        Task {
            do {
                let udid = try await DeviceConnector.shared.fetchUDID(pairingContent: pairing)
                if let udid = udid, !udid.isEmpty {
                    connectionResultLabel.text = "連接成功\n裝置 UDID: \(udid)"
                    EraLog.shared.log("[連接] 測試成功，UDID: \(udid)")
                } else {
                    connectionResultLabel.text = "fetchUDID 回傳空值（連線已建立但無 UDID）"
                    EraLog.shared.log("[連接] fetchUDID 回傳 nil/空字串")
                }
            } catch {
                connectionResultLabel.text = "連接失敗: \(error.localizedDescription)"
                EraLog.shared.log("[連接] 測試失敗: \(error.localizedDescription) | \(String(describing: error))")
            }
            setBusy(false)
        }
    }

    // MARK: - Login

    @objc private func signInTapped() {
        view.endEditing(true)
        guard let pairing = PairingStore.shared.pairingContent else {
            loginStatusLabel.text = "請先匯入配對檔（註冊裝置需要）"
            return
        }
        let appleID = appleIDField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        guard !appleID.isEmpty, !password.isEmpty else {
            loginStatusLabel.text = "請輸入 Apple ID 與密碼"
            return
        }
        setBusy(true)
        loginStatusLabel.text = "處理中…（登入 → Team → 註冊裝置）"
        Task {
            do {
                try await LoginService.shared.signInAndRegisterDevice(
                    appleID: appleID,
                    password: password,
                    pairingContent: pairing,
                    verificationHandler: twoFactorBridge.handler
                )
                loginStatusLabel.text = "登入＋註冊完成（詳見日誌）"
            } catch {
                loginStatusLabel.text = "失敗: \(error.localizedDescription)"
                EraLog.shared.log("[登入] 流程失敗: \(error.localizedDescription) | \(String(describing: error))")
            }
            twoFAContainer.isHidden = true
            setBusy(false)
        }
    }

    // MARK: - 2FA presentation

    private func presentTwoFactor(_ request: TwoFactorRequest) {
        twoFAContainer.isHidden = false
        twoFAMethodStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        codeField.text = ""
        switch request {
        case .selectDeliveryMethod(_, let phoneNumbers):
            twoFAInfoLabel.text = "請選擇雙重驗證方式:"
            codeRow.isHidden = true
            let trustedButton = ViewController.makeButton("信任裝置")
            trustedButton.addTarget(self, action: #selector(twoFATrustedTapped), for: .touchUpInside)
            twoFAMethodStack.addArrangedSubview(trustedButton)
            for phone in phoneNumbers {
                let button = ViewController.makeButton("簡訊傳送至 \(phone.number)")
                button.accessibilityIdentifier = phone.id
                button.addTarget(self, action: #selector(twoFASmsTapped(_:)), for: .touchUpInside)
                twoFAMethodStack.addArrangedSubview(button)
            }
        case .trustedDevice(let error):
            twoFAInfoLabel.text = error ?? "請在信任裝置上核准，或輸入裝置上顯示的驗證碼:"
            codeRow.isHidden = false
        case .sms(_, _, let error):
            twoFAInfoLabel.text = error ?? "驗證碼已透過簡訊發送，請輸入:"
            codeRow.isHidden = false
        case .voice(_, _, let error):
            twoFAInfoLabel.text = error ?? "驗證碼將透過語音來電發送，請輸入:"
            codeRow.isHidden = false
        }
    }

    @objc private func twoFATrustedTapped() {
        twoFactorBridge.respond(.requestTrustedDevice)
    }

    @objc private func twoFASmsTapped(_ sender: UIButton) {
        guard let phoneID = sender.accessibilityIdentifier else { return }
        twoFactorBridge.respond(.requestSMS(phoneID: phoneID))
    }

    @objc private func submitCodeTapped() {
        let code = codeField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else { return }
        twoFactorBridge.respond(.verificationCode(code))
    }

    @objc private func cancelTwoFATapped() {
        twoFactorBridge.respond(.cancel)
        twoFAContainer.isHidden = true
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        logTextView.text += line + "\n"
        let bottom = NSRange(location: (logTextView.text as NSString).length, length: 0)
        logTextView.scrollRangeToVisible(bottom)
    }

    @objc private func clearLogTapped() {
        logTextView.text = ""
        EraLog.shared.clear()
    }

    private func setBusy(_ busy: Bool) {
        importButton.isEnabled = !busy
        testButton.isEnabled = !busy
        signInButton.isEnabled = !busy
    }
}

extension ViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let udid = try PairingStore.shared.importFile(at: url)
            EraLog.shared.log("[配對] 已匯入配對檔，UDID: \(udid.isEmpty ? "（無）" : udid)")
        } catch {
            EraLog.shared.log("[配對] 匯入失敗: \(error.localizedDescription) | \(String(describing: error))")
        }
        refreshPairingStatus()
    }
}
