# Hướng dẫn tích hợp Oten Login vào iOS App

Hướng dẫn chi tiết từng bước dành cho người mới bắt đầu. Sau khi hoàn thành, bạn sẽ có một ứng dụng iOS có thể đăng nhập bằng Oten.

## Yêu cầu

- macOS 13+
- Xcode 14+ (tải miễn phí từ [App Store](https://apps.apple.com/app/xcode/id497799835))
- iOS 16.0+

---

## Bước 1: Chuẩn bị thông tin từ Oten Developer Portal

1. Truy cập [Oten Developer Portal](https://developer.oten.com)
2. Tạo một **Integration App**
3. Trong Integration App, tạo một **Native Application**
4. Cấu hình **Redirect URI** (ví dụ: `otenlogin://auth`)

**✅ Sau khi hoàn tất, bạn cần có 3 giá trị sau:**

| Thông tin | Ví dụ |
|-----------|-------|
| `<YOUR_CLIENT_ID>` | `0d7b3c9d-124a-40b9-a936-f39fe49653ba` |
| `<YOUR_REDIRECT_URI>` | `otenlogin://auth` |
| `<YOUR_AUTH_DOMAIN>` | `https://account.oten.com` |

> 💡 **Lưu ý:** Redirect URI nên đặt theo format `appname://auth`, ví dụ: `otenlogin://auth`

---

## Bước 2: Tạo project mới trong Xcode

### 2.1. Mở Xcode và tạo project

1. Mở **Xcode**
2. Chọn **Create New Project** (hoặc menu **File** → **New** → **Project...**)
3. Chọn tab **iOS** → chọn **App** → bấm **Next**

### 2.2. Điền thông tin project

| Field | Giá trị | Ghi chú |
|-------|---------|---------|
| Product Name | `OtenLogin` | Tên ứng dụng |
| Team | Chọn team của bạn | Hoặc bỏ qua nếu chưa có |
| Organization Identifier | `com.yourcompany` | Thay `yourcompany` bằng tên công ty/cá nhân |
| **Interface** | **SwiftUI** hoặc **Storyboard** | ⬅️ Chọn một trong hai (xem bên dưới) |
| Language | Swift | |

**Sự khác biệt giữa 2 loại Interface:**

| | SwiftUI | Storyboard (UIKit) |
|---|---------|-------------------|
| Khuyến nghị | ✅ Cho người mới | Cho dự án cũ |
| File khởi động | `OtenLoginApp.swift` | `AppDelegate.swift`, `SceneDelegate.swift` |
| File giao diện | `ContentView.swift` | `ViewController.swift`, `Main.storyboard` |

### 2.3. Chọn nơi lưu project

1. Bấm **Next**
2. Chọn thư mục bạn muốn lưu project (ví dụ: Desktop hoặc Documents)
3. Bấm **Create**

---

## Bước 3: Tạo file OtenAuthService.swift

### 3.1. Tạo file mới

1. Trong Xcode, vào menu **File** → **New** → **File...**
2. Chọn **Swift File** → bấm **Next**
3. Đặt tên file: `OtenAuthService` (Xcode sẽ tự thêm đuôi `.swift`)
4. Bấm **Create**

### 3.2. Thêm code vào file

1. Xóa hết nội dung mặc định trong file `OtenAuthService.swift`
2. Copy **toàn bộ** code bên dưới và paste vào:

<details>
<summary><strong>👉 Bấm để xem code OtenAuthService.swift</strong></summary>

```swift
//
//  OtenAuthService.swift
//

import Foundation
import CryptoKit
import AuthenticationServices

// MARK: - Configuration

public struct OtenAuthConfiguration {
    public let clientId: String
    public let redirectUri: String
    public let authorizeURL: String
    public let tokenURL: String
    public let scope: String
    public let codeChallengeMethod: String

    public init(
        clientId: String,
        redirectUri: String,
        authorizeURL: String,
        tokenURL: String,
        scope: String = "openid profile email offline_access",
        codeChallengeMethod: String = "S256"
    ) {
        self.clientId = clientId
        self.redirectUri = redirectUri
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.scope = scope
        self.codeChallengeMethod = codeChallengeMethod
    }
}

// MARK: - Token Response

public struct OtenTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let idToken: String?
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
        case scope = "scope"
    }
}

// MARK: - User Info

public struct OtenUserInfo: Codable, Sendable {
    public let sub: String?
    public let email: String?
    public let name: String?
    public let picture: String?
    public let exp: TimeInterval?
}

// MARK: - Errors

public enum OtenAuthError: Error, LocalizedError {
    case notConfigured
    case invalidAuthorizeURL
    case invalidAuthorizationRequest
    case invalidCallbackURL
    case missingAuthorizationCode
    case invalidState
    case authenticationCancelled
    case tokenExchangeFailed(String)
    case networkError(Error)
    case invalidIdToken

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OtenAuthService is not configured. Call configure() first."
        case .invalidAuthorizeURL:
            return "Invalid authorize URL in configuration."
        case .invalidAuthorizationRequest:
            return "Failed to build authorization request."
        case .invalidCallbackURL:
            return "Invalid callback URL received."
        case .missingAuthorizationCode:
            return "Authorization code not found in callback."
        case .invalidState:
            return "State parameter mismatch. Possible CSRF attack."
        case .authenticationCancelled:
            return "Authentication was cancelled by user."
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidIdToken:
            return "Invalid ID token format."
        }
    }
}

// MARK: - Auth Service

@MainActor
public final class OtenAuthService: NSObject {
    public static let shared = OtenAuthService()

    public var presentationAnchorProvider: (() -> ASPresentationAnchor)?

    private var configuration: OtenAuthConfiguration?
    private var currentCodeVerifier: String?
    private var currentState: String?

    private override init() {
        super.init()
    }

    public func configure(
        clientId: String,
        redirectUri: String,
        authorizeURL: String,
        tokenURL: String,
        scope: String = "openid profile email offline_access",
        codeChallengeMethod: String = "S256"
    ) {
        self.configuration = OtenAuthConfiguration(
            clientId: clientId,
            redirectUri: redirectUri,
            authorizeURL: authorizeURL,
            tokenURL: tokenURL,
            scope: scope,
            codeChallengeMethod: codeChallengeMethod
        )
    }

    public var isConfigured: Bool {
        return configuration != nil
    }

    public func login() async throws -> OtenTokenResponse {
        guard let configuration = configuration else {
            throw OtenAuthError.notConfigured
        }

        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateState()

        currentCodeVerifier = codeVerifier
        currentState = state

        let authorizeURL = try buildAuthorizeURL(codeChallenge: codeChallenge, state: state, configuration: configuration)
        let callbackURL = try await presentAuthenticationSession(url: authorizeURL, configuration: configuration)
        let code = try extractAuthorizationCode(url: callbackURL, expectedState: state)
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier, configuration: configuration)

        currentCodeVerifier = nil
        currentState = nil

        return tokens
    }

    public func parseUserInfo(from idToken: String) throws -> OtenUserInfo {
        let parts = idToken.split(separator: ".")
        guard parts.count == 3, let payloadData = Data(base64URLEncoded: String(parts[1])) else {
            throw OtenAuthError.invalidIdToken
        }
        do {
            return try JSONDecoder().decode(OtenUserInfo.self, from: payloadData)
        } catch {
            throw OtenAuthError.invalidIdToken
        }
    }
}

// MARK: - Private Methods

extension OtenAuthService {
    private func buildAuthorizeURL(
        codeChallenge: String,
        state: String,
        configuration: OtenAuthConfiguration
    ) throws -> URL {
        guard var components = URLComponents(string: configuration.authorizeURL) else {
            throw OtenAuthError.invalidAuthorizeURL
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectUri),
            URLQueryItem(name: "scope", value: configuration.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: configuration.codeChallengeMethod)
        ]
        guard let url = components.url else {
            throw OtenAuthError.invalidAuthorizationRequest
        }
        return url
    }

    private func presentAuthenticationSession(
        url: URL,
        configuration: OtenAuthConfiguration
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let scheme = URL(string: configuration.redirectUri)?.scheme

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: scheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: OtenAuthError.authenticationCancelled)
                    } else {
                        continuation.resume(throwing: OtenAuthError.networkError(error))
                    }
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OtenAuthError.invalidCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }

    private func extractAuthorizationCode(
        url: URL,
        expectedState: String
    ) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItems = components.queryItems else {
            throw OtenAuthError.invalidCallbackURL
        }

        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            throw OtenAuthError.tokenExchangeFailed(error)
        }

        guard let state = queryItems.first(where: { $0.name == "state" })?.value, state == expectedState else {
            throw OtenAuthError.invalidState
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw OtenAuthError.missingAuthorizationCode
        }

        return code
    }

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        configuration: OtenAuthConfiguration
    ) async throws -> OtenTokenResponse {
        guard let tokenURL = URL(string: configuration.tokenURL) else {
            throw OtenAuthError.tokenExchangeFailed("Invalid token URL")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectUri,
            "client_id": configuration.clientId,
            "code_verifier": codeVerifier
        ]
        let bodyString = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OtenAuthError.tokenExchangeFailed("Invalid response")
            }
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OtenAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }
            return try JSONDecoder().decode(OtenTokenResponse.self, from: data)
        } catch let error as OtenAuthError {
            throw error
        } catch {
            throw OtenAuthError.networkError(error)
        }
    }
}

// MARK: - PKCE Helpers

extension OtenAuthService {
    private func generateCodeVerifier() -> String {
        let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<128).compactMap { _ in charset.randomElement() })
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    private func generateState() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OtenAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        if let anchor = presentationAnchorProvider?() {
            return anchor
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow
                ?? scenes.first?.windows.first
        else {
            fatalError("No presentation anchor available")
        }
        return window
    }
}

// MARK: - Data Extension for Base64URL

private extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}
```

</details>

---

## Bước 4: Cấu hình khi app khởi động

Sử dụng 3 giá trị đã có ở **Bước 1** để thay thế vào code:
- `<YOUR_CLIENT_ID>` → Client ID của bạn
- `<YOUR_REDIRECT_URI>` → Redirect URI (ví dụ: `otenlogin://auth`)
- `<YOUR_AUTH_DOMAIN>` → Domain (ví dụ: `https://account.oten.com`)

⚠️ **Chọn hướng dẫn phù hợp với loại Interface bạn đã chọn ở Bước 2:**

### Option A: SwiftUI

1. Trong Xcode, mở file `OtenLoginApp.swift` (ở panel bên trái)
2. **Xóa hết** nội dung trong file
3. **Copy và paste** code sau, sau đó thay thế 3 giá trị:

```swift
import SwiftUI

@main
struct OtenLoginApp: App {
    init() {
        OtenAuthService.shared.configure(
            clientId: "<YOUR_CLIENT_ID>",
            redirectUri: "<YOUR_REDIRECT_URI>",
            authorizeURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/authorize",
            tokenURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/token"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Option B: UIKit (Storyboard)

1. Trong Xcode, mở file `AppDelegate.swift` (ở panel bên trái)
2. Thêm đoạn code `OtenAuthService.shared.configure(...)` vào trong hàm `application(_:didFinishLaunchingWithOptions:)`, trước dòng `return true`:

```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    OtenAuthService.shared.configure(
        clientId: "<YOUR_CLIENT_ID>",
        redirectUri: "<YOUR_REDIRECT_URI>",
        authorizeURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/authorize",
        tokenURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/token"
    )
    return true
}
```

**Ví dụ sau khi thay thế (áp dụng cho cả SwiftUI và UIKit):**

```swift
OtenAuthService.shared.configure(
    clientId: "0d7b3c9d-124a-40b9-a936-f39fe49653ba",
    redirectUri: "otenlogin://auth",
    authorizeURL: "https://account.oten.com/v1/oauth/authorize",
    tokenURL: "https://account.oten.com/v1/oauth/token"
)
```

---

## Bước 5: Tạo giao diện Login

⚠️ **Chọn hướng dẫn phù hợp với loại Interface bạn đã chọn ở Bước 2:**

### Option A: SwiftUI

1. Mở file `ContentView.swift` (ở panel bên trái)
2. **Xóa hết** nội dung trong file
3. **Copy và paste** code bên dưới:

<details>
<summary><strong>👉 Bấm để xem code ContentView.swift</strong></summary>

```swift
import SwiftUI

struct ContentView: View {
    @State private var userInfo: OtenUserInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if let user = userInfo {
                // Đã đăng nhập
                VStack(spacing: 16) {
                    Text("Chào mừng!")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if let name = user.name {
                        Text(name)
                            .font(.title2)
                    }

                    if let email = user.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button("Đăng xuất") {
                        userInfo = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Chưa đăng nhập
                VStack(spacing: 16) {
                    Text("Oten Login Demo")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    if isLoading {
                        ProgressView()
                    } else {
                        Button("Login with Oten") {
                            login()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let tokens = try await OtenAuthService.shared.login()
                print("✅ Đăng nhập thành công!")

                if let idToken = tokens.idToken {
                    let user = try OtenAuthService.shared.parseUserInfo(from: idToken)
                    await MainActor.run {
                        userInfo = user
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

#Preview {
    ContentView()
}
```

</details>

### Option B: UIKit (Storyboard)

1. Mở file `ViewController.swift` (ở panel bên trái)
2. **Xóa hết** nội dung trong file
3. **Copy và paste** code bên dưới:

<details>
<summary><strong>👉 Bấm để xem code ViewController.swift</strong></summary>

```swift
import UIKit

class ViewController: UIViewController {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Oten Login Demo"
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Login with Oten", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let userInfoLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let logoutButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Đăng xuất", for: .normal)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .systemRed
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(titleLabel)
        view.addSubview(loginButton)
        view.addSubview(loadingIndicator)
        view.addSubview(userInfoLabel)
        view.addSubview(logoutButton)
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),

            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            loginButton.widthAnchor.constraint(equalToConstant: 200),
            loginButton.heightAnchor.constraint(equalToConstant: 50),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            userInfoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            userInfoLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            userInfoLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            userInfoLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            logoutButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoutButton.topAnchor.constraint(equalTo: userInfoLabel.bottomAnchor, constant: 20),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: loginButton.bottomAnchor, constant: 20),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
    }

    @objc private func loginTapped() {
        loginButton.isHidden = true
        loadingIndicator.startAnimating()
        errorLabel.isHidden = true

        Task {
            do {
                let tokens = try await OtenAuthService.shared.login()
                print("✅ Đăng nhập thành công!")

                if let idToken = tokens.idToken {
                    let user = try OtenAuthService.shared.parseUserInfo(from: idToken)
                    await MainActor.run {
                        showLoggedInState(user: user)
                    }
                }
            } catch {
                await MainActor.run {
                    showError(error.localizedDescription)
                }
            }
            await MainActor.run {
                loadingIndicator.stopAnimating()
            }
        }
    }

    @objc private func logoutTapped() {
        titleLabel.text = "Oten Login Demo"
        userInfoLabel.isHidden = true
        logoutButton.isHidden = true
        loginButton.isHidden = false
    }

    private func showLoggedInState(user: OtenUserInfo) {
        titleLabel.text = "Chào mừng!"
        var info = ""
        if let name = user.name { info += name + "\n" }
        if let email = user.email { info += email }
        userInfoLabel.text = info
        userInfoLabel.isHidden = false
        logoutButton.isHidden = false
        loginButton.isHidden = true
    }

    private func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
        loginButton.isHidden = false
    }
}
```

</details>

---

## Bước 6: Chạy ứng dụng

### 6.1. Chọn Simulator

1. Nhìn lên **thanh công cụ phía trên** của Xcode (toolbar)
2. Tìm **dropdown** nằm bên cạnh tên project `OtenLogin`
   - Có thể đang hiển thị "Any iOS Device (arm64)" hoặc tên một iPhone
3. **Bấm vào dropdown đó** để mở danh sách thiết bị
4. Trong mục **iOS Simulators**, chọn một iPhone, ví dụ:
   - **iPhone 15 Pro** (khuyến nghị)
   - Hoặc **iPhone 15**, **iPhone 14**, **iPhone SE**...

> 💡 **Mẹo:** Nếu không thấy iPhone nào trong danh sách, vào menu **Window** → **Devices and Simulators** để kiểm tra.

### 6.2. Build và chạy app

1. Bấm nút **▶️ (Play)** ở góc trên bên trái của Xcode
   - Hoặc nhấn phím tắt **⌘R** (Command + R)

2. **Đợi Xcode build project:**
   - Lần đầu tiên có thể mất **1-3 phút**
   - Bạn sẽ thấy thanh progress ở phía trên
   - Khi hoàn thành, Simulator sẽ tự động mở

3. **Simulator khởi động:**
   - Lần đầu mở Simulator có thể mất thêm 1-2 phút
   - Sau khi mở xong, app của bạn sẽ tự động chạy

### 6.3. Test đăng nhập

1. Trong app, bấm nút **"Login with Oten"**
2. **Trình duyệt sẽ mở** trang đăng nhập Oten
3. Đăng nhập bằng tài khoản Oten của bạn
4. Sau khi đăng nhập thành công:
   - Trình duyệt tự động đóng
   - App hiển thị thông tin user (tên, email)
5. Bấm **"Đăng xuất"** để quay lại màn hình login

