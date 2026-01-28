# Oten Login - iOS Integration Guide

Hướng dẫn tích hợp đăng nhập Oten vào ứng dụng iOS sử dụng **Authorization Code Flow + PKCE** theo chuẩn OAuth 2.0 / OpenID Connect.

> **Public Client (Native Application):** PKCE là **bắt buộc** theo [Oten Integration Guide](https://integration.oten.dev).

**Yêu cầu:** iOS 16.0+ · Xcode 14.0+

---

## ⚡ Quick Start

1. Tạo Native App trên [Oten Developer Portal](https://developer.oten.live) → lấy Auth Domain, Client ID, Redirect URI
2. Copy `OtenAuthService.swift` vào project
3. Gọi `configure(...)` khi app khởi động
4. Gọi `await OtenAuthService.shared.login()`

---

## 🚀 Run Sample Project

### Bước 1: Mở project
- Tải `sample-swift.zip` về và giải nén (hoặc clone repository)
- Mở `OtenLogin.xcodeproj`

### Bước 2: Configure credentials

**Nếu chạy SwiftUI target (OtenLogin):**
- Mở `OtenLogin/OtenLoginApp.swift`, tìm hàm `init()`:

**Nếu chạy UIKit target (OtenLoginUIKit):**
- Mở `OtenLoginUIKit/AppDelegate.swift`, tìm hàm `application(didFinishLaunchingWithOptions:)`:

```swift
OtenAuthService.shared.configure(
    clientId: "<YOUR_CLIENT_ID>",        // ← Thay bằng Client ID từ Oten Portal
    redirectUri: "<YOUR_REDIRECT_URI>",  // ← Ví dụ: yourapp://auth
    authorizeURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/authorize",
    tokenURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/token"
)
```

**Auth Domain:**
- Development: `https://account.dev.oten.dev`
- Production: `https://account.oten.live`

### Bước 3: Run
- Chọn target:
  - **OtenLogin** (SwiftUI) - Mặc định
  - **OtenLoginUIKit** (UIKit) - Nếu muốn xem UIKit demo
- Chọn simulator hoặc device
- Nhấn **⌘R** để chạy

### Bước 4: Test login
- Nhấn nút **"Login with Oten"**
- Đăng nhập trên browser
- Xem kết quả tokens trong console

> 💡 **Tip:** Nếu chưa có Client ID và Redirect URI, xem [Bước 1: Tạo ứng dụng trên Oten Developer Portal](#bước-1-tạo-ứng-dụng-trên-oten-developer-portal)

> 📱 **Demo implementations:** Project có 2 targets:
> - **OtenLogin (SwiftUI):** `ContentView.swift` - Target mặc định
> - **OtenLoginUIKit (UIKit):** `ViewController.swift` - Chọn target này để chạy UIKit demo

---

## Mục lục

| # | Tích hợp vào project của bạn |
|---|------|
| 1 | [Tạo ứng dụng trên Oten](#bước-1-tạo-ứng-dụng-trên-oten-developer-portal) |
| 2 | [Thêm OtenAuthService](#bước-2-thêm-otenauthservice-vào-project) |
| 3 | [Cấu hình App](#bước-3-cấu-hình-khi-app-khởi-động) |
| 4 | [Gọi Login](#bước-4-gọi-login) |

**Mở rộng:** [Lấy thông tin User](#lấy-thông-tin-user) · [Lưu Tokens](#lưu-tokens) · [Xử lý lỗi](#xử-lý-lỗi) · [Best Practices](#best-practices) · [Tham khảo](#tham-khảo)

---

## Bước 1: Tạo ứng dụng trên Oten Developer Portal

1. Truy cập [Oten Developer Portal](https://developer.oten.live/app-management)
2. Bấm **Create App** để tạo một **Integration App**
3. Trong **App setup process**, chọn bước **Resources & Security**
4. Tại tab **Client Identity**, trong mục **Choose Client Type to Create**:
   - Chọn **Native Application** → bấm **Create**
5. Trong popup **Config Client**:
   - **Redirect URIs**: Nhập redirect URI của bạn (ví dụ: `yourapp://auth`)
   - Bấm **Save**
6. Sau khi tạo xong, copy **Client ID** từ phần **Client Credentials**

**✅ Sau khi hoàn thành các bước trên, bạn sẽ có 3 giá trị cần dùng cho Bước 3:**

- **`<YOUR_CLIENT_ID>`** — lấy từ phần **Client Credentials**
- **`<YOUR_REDIRECT_URI>`** — redirect URI bạn đã cấu hình (ví dụ: `yourapp://auth`)
- **`<YOUR_AUTH_DOMAIN>`** — sử dụng `https://account.oten.live` cho Production hoặc `https://account.dev.oten.dev` cho Development

---

## Bước 2: Thêm OtenAuthService vào project

Tạo file `OtenAuthService.swift` trong project và copy nội dung bên dưới:

<details>
<summary><strong>OtenAuthService.swift</strong> (bấm để mở)</summary>

```swift
//
//  OtenAuthService.swift
//  OtenLogin
//

import Foundation
import CryptoKit
import AuthenticationServices

// MARK: - Configuration

/// Configuration for Oten OAuth service
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

/// Token response from OAuth server
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

/// User info parsed from ID token
public struct OtenUserInfo: Codable, Sendable {
    public let sub: String?
    public let email: String?
    public let name: String?
    public let picture: String?
    public let exp: TimeInterval?
}

// MARK: - Errors

/// Errors that can occur during OAuth flow
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

/// Main OAuth service - Singleton
/// Usage:
/// 1. Call `configure(...)` once at app startup
/// 2. Call `login()` when user taps login button
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

    // MARK: - Public Methods

    /// Configure the service with IDP parameters
    /// Call this once at app startup (e.g., in AppDelegate or App init)
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

    /// Check if service is configured
    public var isConfigured: Bool {
        return configuration != nil
    }

    /// Perform OAuth login flow
    /// Opens ASWebAuthenticationSession for user to authenticate
    /// Returns token response on success
    public func login() async throws -> OtenTokenResponse {
        guard let configuration = configuration else {
            throw OtenAuthError.notConfigured
        }

        // Generate PKCE parameters
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateState()

        // Store for later verification
        currentCodeVerifier = codeVerifier
        currentState = state

        // Build authorize URL
        let authorizeURL = try buildAuthorizeURL(codeChallenge: codeChallenge, state: state, configuration: configuration)

        // Present authentication session
        let callbackURL = try await presentAuthenticationSession(url: authorizeURL, configuration: configuration)

        // Extract authorization code
        let code = try extractAuthorizationCode(url: callbackURL, expectedState: state)

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier, configuration: configuration)

        // Clear temporary values
        currentCodeVerifier = nil
        currentState = nil

        return tokens
    }

    /// Parse user info from ID token
    /// - Parameter idToken: The ID token JWT string from token response
    /// - Returns: User info parsed from token payload
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
            // Extract scheme from redirect URI
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

        // Check for error
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            throw OtenAuthError.tokenExchangeFailed(error)
        }

        // Verify state
        guard let state = queryItems.first(where: { $0.name == "state" })?.value, state == expectedState else {
            throw OtenAuthError.invalidState
        }

        // Extract code
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
            let tokens = try JSONDecoder().decode(OtenTokenResponse.self, from: data)
            return tokens
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

<br>

> **Tip:** Kéo thả file `OtenLogin/Oten/OtenAuthService.swift` từ sample vào project, chọn "Copy items if needed".

---

## Bước 3: Cấu hình khi app khởi động

Gọi `configure()` **một lần** khi app khởi động, **trước khi** gọi `login()`.

**UIKit (AppDelegate):**

Nếu project dùng UIKit với `AppDelegate.swift`:

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

**SwiftUI (App init):**

Nếu project dùng SwiftUI thuần (không có AppDelegate):

```swift
@main
struct YourApp: App {
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

> **Note:** Nếu SwiftUI project có `@UIApplicationDelegateAdaptor`, dùng cách AppDelegate ở trên.

Thay thế `<YOUR_CLIENT_ID>`, `<YOUR_REDIRECT_URI>`, `<YOUR_AUTH_DOMAIN>` bằng thông tin từ Bước 1.

---

## Bước 4: Gọi login

**SwiftUI:**

```swift
Button("Login with Oten") {
    Task {
        do {
            let tokens = try await OtenAuthService.shared.login()
            print("Access token: \(tokens.accessToken.prefix(20))...")
        } catch {
            print("Login failed: \(error.localizedDescription)")
        }
    }
}
```

**UIKit:**

```swift
@objc private func loginTapped() {
    Task {
        do {
            let tokens = try await OtenAuthService.shared.login()
            print("Access token: \(tokens.accessToken.prefix(20))...")
        } catch {
            print("Login failed: \(error.localizedDescription)")
        }
    }
}
```

Khi user nhấn button, hệ thống sẽ mở trình duyệt để đăng nhập. Sau khi đăng nhập thành công, app nhận được tokens.

---

## Mở rộng

Các phần dưới đây là tuỳ chọn, giúp bạn xử lý thêm sau khi login thành công.

---

### Lấy thông tin User

Sau khi login thành công, bạn có thể lấy thông tin user từ `idToken`:

```swift
if let idToken = tokens.idToken {
    let userInfo = try OtenAuthService.shared.parseUserInfo(from: idToken)
    print("User ID: \(userInfo.sub ?? "N/A")")
    print("Name: \(userInfo.name ?? "N/A")")
    print("Email: \(userInfo.email ?? "N/A")")
}
```

| Property | Mô tả |
|----------|-------|
| `sub` | User ID (unique) |
| `name` | Tên hiển thị |
| `email` | Email |
| `picture` | URL avatar |

---

### Lưu Tokens

Sample này chỉ print tokens ra console. Trong production, bạn nên lưu tokens vào **Keychain** sử dụng [Security framework](https://developer.apple.com/documentation/security/keychain_services) của Apple.

| Token | Mô tả |
|-------|-------|
| `accessToken` | Dùng để gọi API (`Authorization: Bearer <token>`) |
| `refreshToken` | Dùng để lấy access token mới khi hết hạn |
| `idToken` | JWT chứa thông tin user |

---

### Xử lý lỗi

```swift
do {
    let tokens = try await OtenAuthService.shared.login()
} catch let error as OtenAuthError {
    switch error {
    case .authenticationCancelled:
        print("User đã hủy đăng nhập")
    case .notConfigured:
        print("Chưa gọi configure()")
    default:
        print("Lỗi: \(error.localizedDescription)")
    }
} catch {
    print("Lỗi không xác định: \(error)")
}
```

| Error | Nguyên nhân |
|-------|-------------|
| `.notConfigured` | Chưa gọi `configure()` |
| `.authenticationCancelled` | User hủy đăng nhập |
| `.invalidState` | Lỗi bảo mật (CSRF) |
| `.tokenExchangeFailed` | Lỗi khi đổi code lấy token |

> Xem đầy đủ các lỗi trong `OtenAuthError` enum.

---

## Best Practices

### Quản lý Configuration

Thay vì hardcode credentials trong code, nên lưu vào `Info.plist` để dễ quản lý giữa các môi trường (Dev/Staging/Prod):

**Info.plist:**
```xml
<key>OtenClientID</key>
<string>$(OTEN_CLIENT_ID)</string>
<key>OtenAuthDomain</key>
<string>$(OTEN_AUTH_DOMAIN)</string>
<key>OtenRedirectURI</key>
<string>$(OTEN_REDIRECT_URI)</string>
```

**Đọc config trong code:**
```swift
func loadOtenConfig() -> OtenAuthConfiguration? {
    guard let clientId = Bundle.main.object(forInfoDictionaryKey: "OtenClientID") as? String,
          let authDomain = Bundle.main.object(forInfoDictionaryKey: "OtenAuthDomain") as? String,
          let redirectUri = Bundle.main.object(forInfoDictionaryKey: "OtenRedirectURI") as? String else {
        return nil
    }

    return OtenAuthConfiguration(
        clientId: clientId,
        redirectUri: redirectUri,
        authorizeURL: "\(authDomain)/v1/oauth/authorize",
        tokenURL: "\(authDomain)/v1/oauth/token"
    )
}
```

> 💡 **Tip:** Sử dụng `.xcconfig` files để quản lý giá trị khác nhau cho từng môi trường.

### Lưu Token vào Keychain

Tokens cần được lưu an toàn trong Keychain, không phải UserDefaults:

```swift
import Security

struct KeychainHelper {
    static func save(_ token: String, forKey key: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// Sử dụng
KeychainHelper.save(tokens.accessToken, forKey: "oten_access_token")
KeychainHelper.save(tokens.refreshToken ?? "", forKey: "oten_refresh_token")
```

---

## Tham khảo

- [Oten Developer Portal](https://developer.oten.live) — Quản lý ứng dụng
- [Oten Integration Guide](https://integration.oten.dev) — Tài liệu tích hợp chính thức
- [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide) — Hướng dẫn PKCE chi tiết
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — Apple Developer
