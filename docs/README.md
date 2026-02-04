# Oten Login iOS – Deep Dive Guide

Tài liệu này giải thích chi tiết cách ứng dụng iOS tích hợp **Oten IDP** theo chuẩn **OAuth 2.0 / OpenID Connect** sử dụng **Authorization Code Flow + PKCE**.

> **Public Client (Native Application):** Theo [Oten Integration Guide](https://integration.oten.dev), PKCE là **bắt buộc** cho mobile apps. JAR (JWT-Secured Authorization Request) **không áp dụng** cho public clients.

- Nếu bạn chỉ cần **tích hợp nhanh** → xem [GUIDE.md](./GUIDE.md)
- Nếu bạn muốn **hiểu sâu về flow và bảo mật** → tiếp tục đọc

---

## Mục lục

1. [Tổng quan kiến trúc](#1-tổng-quan-kiến-trúc)
2. [Authorization Code Flow + PKCE](#2-authorization-code-flow--pkce)
3. [Mổ xẻ hàm login()](#3-mổ-xẻ-hàm-login-trong-otenauthservice)
4. [PKCE – code_verifier & code_challenge](#4-pkce--code_verifier--code_challenge)
5. [State validation – chống CSRF](#5-state-validation--chống-csrf--redirect-sai-app)
6. [Token Exchange](#6-token-exchange--đổi-authorization-code-lấy-tokens)
7. [ID Token & parseUserInfo](#7-id-token--parseuserinfo)
8. [Lưu trữ Token & Keychain](#8-lưu-trữ-token--keychain-best-practice)
9. [Security considerations](#9-security-considerations--best-practices)
10. [Configuration Management](#10-configuration-management)
11. [SwiftUI + UIKit Integration](#11-swiftui--uikit-integration-notes)
12. [So sánh với AppAuth](#12-so-sánh-với-appauth--vì-sao-sample-không-dùng)
13. [Tham khảo](#tham-khảo)

---

## 1. Tổng quan kiến trúc

Ở mức cao, có 3 thành phần chính:

- **Ứng dụng iOS** (SwiftUI / UIKit)
- **Oten IDP** – máy chủ identity (OpenID Provider)
- **OtenAuthService** – lớp helper trong app, đóng gói toàn bộ OIDC flow

Ứng dụng của bạn:

- Gọi `OtenAuthService.shared.configure(...)` với thông tin từ Oten IDP.
- Khi user bấm “Login with Oten”, gọi `await OtenAuthService.shared.login()`.
- Nhận lại `OtenTokenResponse` chứa:
  - `accessToken`
  - `idToken`
  - (tuỳ config) `refreshToken`
- (Tuỳ ý) Parse `idToken` thành `OtenUserInfo` để hiển thị profile.

---

## 2. Authorization Code Flow + PKCE

Flow chuẩn theo [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide) của Oten:

1. **User bấm Login trong app iOS**  
   App khởi động OIDC Authorization Request.
2. **App mở trình duyệt bảo mật (ASWebAuthenticationSession) trỏ tới Oten**  
   URL chứa:
   - `response_type=code`
   - `client_id`
   - `redirect_uri`
   - `scope`
   - `code_challenge` + `code_challenge_method=S256` (PKCE)
   - `state` (chống CSRF)
3. **User đăng nhập & cấp quyền trên Oten**  
   User nhập username/password hoặc dùng SSO. Oten IDP xác thực và hỏi consent (tuỳ cấu hình).
4. **Oten redirect về lại app qua `<YOUR_REDIRECT_URI>`**  
   Redirect chứa:
   - `code` – Authorization Code (ngắn hạn, một lần dùng)
   - `state` – để app kiểm tra khớp với value đã gửi ban đầu
5. **App đổi Authorization Code lấy Tokens**  
   App gửi request POST lên token endpoint với `code_verifier`. Oten trả về:
   - `access_token`
   - `id_token`
   - `refresh_token` (nếu được cấp)
   - các metadata khác

`OtenAuthService` chính là nơi bạn map từng bước này thành code Swift.

---

## 3. Mổ xẻ hàm `login()` trong OtenAuthService

Public API chính:

- `configure(...)`
- `login() async throws -> OtenTokenResponse`
- `parseUserInfo(from idToken: String) throws -> OtenUserInfo`
- `isConfigured: Bool`

Flow trong `login()` (đơn giản hoá):

```swift
public func login() async throws -> OtenTokenResponse {
    guard let configuration = configuration else { throw OtenAuthError.notConfigured }

    let codeVerifier = generateCodeVerifier()
    let codeChallenge = generateCodeChallenge(from: codeVerifier)
    let state = generateState()

    let authorizeURL = try buildAuthorizeURL(
        codeChallenge: codeChallenge, state: state, configuration: configuration
    )
    let callbackURL = try await presentAuthenticationSession(
        url: authorizeURL, configuration: configuration
    )
    let code = try extractAuthorizationCode(url: callbackURL, expectedState: state)
    let tokens = try await exchangeCodeForTokens(
        code: code, codeVerifier: codeVerifier, configuration: configuration
    )
    return tokens
}
```

Giải thích theo flow:

1. **Kiểm tra đã configure hay chưa** – nếu chưa gọi `configure(...)` → ném `OtenAuthError.notConfigured`.
2. **Tạo PKCE parameters (code_verifier, code_challenge) và state** – dùng helper `generateCodeVerifier`, `generateCodeChallenge`, `generateState`.
3. **Xây dựng authorize URL** – `buildAuthorizeURL(...)` gắn query string theo chuẩn OIDC.
4. **Mở ASWebAuthenticationSession** – `presentAuthenticationSession(...)` gọi `ASWebAuthenticationSession.start()` và chờ callback.
5. **Validate callback & lấy authorization code** – `extractAuthorizationCode(...)` kiểm tra lỗi, validate `state`, lấy `code`.
6. **Đổi code lấy tokens** – `exchangeCodeForTokens(...)` gửi POST lên token endpoint.

---

## 4. PKCE – `code_verifier` & `code_challenge`

### 4.1. Tại sao cần PKCE?

PKCE (Proof Key for Code Exchange) giải quyết vấn đề:

- Trên mobile app, bạn **không** thể giữ client secret an toàn.
- Nếu attacker intercept được Authorization Code ở bước 4, vẫn **không thể** đổi code lấy token nếu không có `code_verifier` gốc (chỉ app biết).

Cơ chế:

- App tạo `code_verifier` (chuỗi ngẫu nhiên mạnh).
- Từ `code_verifier`, app tạo `code_challenge = BASE64URL(SHA256(code_verifier))`.
- App gửi `code_challenge` lên authorize endpoint.
- Khi đổi code lấy tokens, app gửi ngược lại `code_verifier`.
- IDP tự tính `SHA256(code_verifier)` và so với `code_challenge` ban đầu. Nếu không khớp → từ chối.

### 4.2. Implementation trong OtenAuthService

Generate `code_verifier`:

```swift
private func generateCodeVerifier() -> String {
    let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    return String((0..<128).compactMap { _ in charset.randomElement() })
}
```

Generate `code_challenge`:

```swift
private func generateCodeChallenge(from verifier: String) -> String {
    let data = Data(verifier.utf8)
    let hash = SHA256.hash(data: data)
    return Data(hash).base64URLEncodedString()
}
```

Điểm chú ý:

- Dùng **SHA256** + Base64URL (không phải Base64 thường).
- Độ dài 128 ký tự cho `code_verifier` là tốt theo khuyến nghị PKCE.

---

## 5. State validation – chống CSRF / redirect sai app

`state` là một string random, app tự sinh (thường là UUID, không dễ đoán). Mục đích:

- Khi gửi authorize request, app đính kèm `state`.
- Khi nhận callback, app đọc `state` trên query và so sánh với state đã lưu.
- Nếu không khớp → **ngay lập tức từ chối** (ném lỗi).

Generate state:

```swift
private func generateState() -> String {
    return UUID().uuidString.replacingOccurrences(of: "-", with: "")
}
```

Validate trong callback (ý tưởng):

```swift
guard let state = queryItems.first(where: { $0.name == "state" })?.value,
      state == expectedState else {
    throw OtenAuthError.invalidState
}
```

Ý nghĩa:

- Nếu `state` mismatch → có thể callback không phải cho flow hiện tại (tấn công CSRF, app khác mở cùng redirect URI, v.v.).
- Bằng cách ném `invalidState`, bạn đảm bảo **không bao giờ đổi code lấy token** trong trường hợp đáng ngờ.

---

## 6. Token Exchange – đổi Authorization Code lấy Tokens

### 6.1. Request gửi lên token endpoint

Trong `exchangeCodeForTokens(...)`, app gửi (x-form-encoded):

- `grant_type=authorization_code`
- `code` – code nhận từ callback
- `redirect_uri` – trùng với giá trị đã đăng ký và đã dùng ở bước authorize
- `client_id`
- `code_verifier` – dùng cho PKCE

Ví dụ dựng body:

```swift
let parameters = [
    "grant_type": "authorization_code",
    "code": code,
    "redirect_uri": configuration.redirectUri,
    "client_id": configuration.clientId,
    "code_verifier": codeVerifier
]
```

### 6.2. Response & `OtenTokenResponse`

Nếu thành công, IDP trả về JSON dạng:

```json
{
  "access_token": "eyJhbGciOi...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "def50200...",
  "id_token": "eyJhbGciOi...",
  "scope": "openid profile email"
}
```

Mapping sang struct:

```swift
public struct OtenTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let idToken: String?
    public let scope: String?
}
```

Bạn dùng `accessToken` để:

- Gọi API backend (đặt trong header `Authorization: Bearer <accessToken>`).

Dùng `idToken` để:

- Lấy thông tin profile user (name, email…).

---

## 7. ID Token & `parseUserInfo`

### 7.1. ID Token là gì?

- Là một **JWT** chứa claim về user (subject, email, name, picture, exp, …).
- Dùng chủ yếu cho **authentication** (ai đang đăng nhập), không phải cho authorization với API (vai trò đó thuộc về `accessToken`).

Ví dụ payload ID Token:

```json
{
  "sub": "1234567890",
  "email": "user@example.com",
  "name": "John Doe",
  "picture": "https://...",
  "exp": 1716242622
}
```

### 7.2. `parseUserInfo(from:)`

`OtenAuthService` có sẵn hàm parse:

```swift
public func parseUserInfo(from idToken: String) throws -> OtenUserInfo {
    let parts = idToken.split(separator: ".")
    guard parts.count == 3,
          let payloadData = Data(base64URLEncoded: String(parts[1])) else {
        throw OtenAuthError.invalidIdToken
    }
    return try JSONDecoder().decode(OtenUserInfo.self, from: payloadData)
}
```

Struct tương ứng:

```swift
public struct OtenUserInfo: Codable, Sendable {
    public let sub: String?
    public let email: String?
    public let name: String?
    public let picture: String?
    public let exp: TimeInterval?
}
```

Use case thường gặp:

- Sau khi `login()` thành công:
  - Nếu `tokens.idToken` tồn tại:
    - Gọi `parseUserInfo`.
    - Lưu `OtenUserInfo` vào ViewModel/state.
    - Dùng để hiển thị avatar, name, email.

---

## 8. Lưu trữ Token & Keychain (Best Practice)

Sample này chỉ **giữ token trong memory** để đơn giản. Trong app production, bạn **bắt buộc** phải lưu tokens an toàn.

### 8.1. Tại sao phải dùng Keychain?

| Phương pháp | Bảo mật | Ghi chú |
|-------------|---------|---------|
| **Keychain** | ✅ An toàn | Mã hoá bởi iOS, không thể đọc từ app khác |
| UserDefaults | ❌ Không an toàn | Plain text, dễ bị đọc |
| File text | ❌ Không an toàn | Có thể backup, extract |

### 8.2. Keychain Helper

```swift
import Security

struct KeychainHelper {

    private static let service = "com.yourapp.oten"

    // MARK: - Save
    static func save(_ token: String, forKey key: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Xoá item cũ nếu có
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Load
    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    // MARK: - Delete
    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Delete All (Logout)
    static func deleteAll() {
        let keys = ["oten_access_token", "oten_refresh_token", "oten_id_token"]
        keys.forEach { delete(forKey: $0) }
    }
}
```

### 8.3. Sử dụng

```swift
// Sau khi login thành công
func saveTokens(_ tokens: OtenTokenResponse) {
    KeychainHelper.save(tokens.accessToken, forKey: "oten_access_token")

    if let refreshToken = tokens.refreshToken {
        KeychainHelper.save(refreshToken, forKey: "oten_refresh_token")
    }

    if let idToken = tokens.idToken {
        KeychainHelper.save(idToken, forKey: "oten_id_token")
    }
}

// Khi app khởi động - kiểm tra đã login chưa
func checkExistingSession() -> Bool {
    return KeychainHelper.load(forKey: "oten_access_token") != nil
}

// Logout
func logout() {
    KeychainHelper.deleteAll()
}
```

### 8.4. Keychain Keys

| Token | Key | Mô tả |
|-------|-----|-------|
| `accessToken` | `oten_access_token` | Gọi API backend |
| `refreshToken` | `oten_refresh_token` | Lấy access token mới |
| `idToken` | `oten_id_token` | Thông tin user (JWT) |

> ⚠️ **Lưu ý:** Sử dụng `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` để token chỉ có thể đọc khi device unlocked và không backup sang device khác.

---

## 9. Security considerations & best practices

Một số điểm quan trọng khi đem sample này vào sản phẩm:

1. **Không nhúng client secret trong app** – mobile/native app không thể giữ bí mật; dùng PKCE thay vì client secret.
2. **Luôn dùng HTTPS với domain Oten chính thức** – ví dụ `https://account.dev.oten.dev`, `https://account.oten.com`.
3. **Bảo vệ token** – lưu trong Keychain, không log full token, chỉ log prefix nếu cần debug.
4. **Kiểm tra kỹ Redirect URI & URL Scheme** – trùng giữa config Oten, Xcode, và giá trị truyền vào `configure(...)`.
5. **Kiểm soát scope** – chỉ yêu cầu scope thực sự cần (vd: `openid profile email`); cân nhắc `offline_access` nếu cần refresh token.
6. **Xử lý lỗi cẩn thận** – phân biệt network error, cancel, invalidState để hiển thị UX phù hợp.

---

## 10. Configuration Management

Thay vì hardcode credentials trong code, nên quản lý configuration một cách có hệ thống để dễ dàng chuyển đổi giữa các môi trường.

### 10.1. Tại sao không nên hardcode?

| Vấn đề | Hậu quả |
|--------|---------|
| Hardcode trong code | Phải sửa code khi đổi môi trường |
| Commit credentials | Lộ thông tin nhạy cảm trên Git |
| Khó maintain | Dễ nhầm lẫn giữa Dev/Staging/Prod |

### 10.2. Sử dụng Info.plist + xcconfig

**Bước 1: Tạo file `.xcconfig` cho từng môi trường**

```
// Config/Dev.xcconfig
OTEN_CLIENT_ID = dev-client-id-xxx
OTEN_AUTH_DOMAIN = https:$()/account.dev.oten.dev
OTEN_REDIRECT_URI = yourapp:$()/auth

// Config/Prod.xcconfig
OTEN_CLIENT_ID = prod-client-id-xxx
OTEN_AUTH_DOMAIN = https:$()/account.oten.com
OTEN_REDIRECT_URI = yourapp:$()/auth
```

**Bước 2: Thêm vào Info.plist**

```xml
<key>OtenClientID</key>
<string>$(OTEN_CLIENT_ID)</string>
<key>OtenAuthDomain</key>
<string>$(OTEN_AUTH_DOMAIN)</string>
<key>OtenRedirectURI</key>
<string>$(OTEN_REDIRECT_URI)</string>
```

**Bước 3: Đọc config trong code**

```swift
struct OtenConfigLoader {

    struct Config {
        let clientId: String
        let authDomain: String
        let redirectUri: String

        var authorizeURL: String { "\(authDomain)/v1/oauth/authorize" }
        var tokenURL: String { "\(authDomain)/v1/oauth/token" }
    }

    static func load() throws -> Config {
        guard let clientId = Bundle.main.object(forInfoDictionaryKey: "OtenClientID") as? String,
              !clientId.isEmpty else {
            throw ConfigError.missingClientID
        }

        guard let authDomain = Bundle.main.object(forInfoDictionaryKey: "OtenAuthDomain") as? String,
              !authDomain.isEmpty else {
            throw ConfigError.missingAuthDomain
        }

        guard let redirectUri = Bundle.main.object(forInfoDictionaryKey: "OtenRedirectURI") as? String,
              !redirectUri.isEmpty else {
            throw ConfigError.missingRedirectURI
        }

        return Config(
            clientId: clientId,
            authDomain: authDomain,
            redirectUri: redirectUri
        )
    }

    enum ConfigError: Error, LocalizedError {
        case missingClientID
        case missingAuthDomain
        case missingRedirectURI

        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Missing OtenClientID in Info.plist"
            case .missingAuthDomain: return "Missing OtenAuthDomain in Info.plist"
            case .missingRedirectURI: return "Missing OtenRedirectURI in Info.plist"
            }
        }
    }
}
```

### 10.3. Sử dụng khi khởi động app

```swift
// AppDelegate hoặc App init
func configureOten() {
    do {
        let config = try OtenConfigLoader.load()

        OtenAuthService.shared.configure(
            clientId: config.clientId,
            redirectUri: config.redirectUri,
            authorizeURL: config.authorizeURL,
            tokenURL: config.tokenURL
        )
    } catch {
        fatalError("Failed to load Oten config: \(error.localizedDescription)")
    }
}
```

### 10.4. Chuyển đổi môi trường

Trong Xcode:
1. **Product → Scheme → Edit Scheme**
2. Chọn **Build Configuration** (Debug/Release)
3. Gán `.xcconfig` file tương ứng cho từng configuration

| Configuration | xcconfig | Môi trường |
|---------------|----------|------------|
| Debug | `Dev.xcconfig` | Development |
| Release | `Prod.xcconfig` | Production |

> 💡 **Tip:** Thêm `*.xcconfig` vào `.gitignore` nếu chứa thông tin nhạy cảm, và tạo file `.xcconfig.example` làm template.

---

## 11. SwiftUI + UIKit Integration Notes

### 11.1. SwiftUI

Pattern gợi ý:

- Tạo một `ObservableObject` quản lý:
  - `isAuthenticated`
  - `currentUser: OtenUserInfo?`
  - `lastError: String?`
- Từ View, gọi hàm `login()` trên ViewModel (ViewModel gọi `OtenAuthService.shared.login()`).

Ví dụ cấu trúc ViewModel:

```swift
final class AuthViewModel: ObservableObject {
    @Published var userInfo: OtenUserInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func login() async { /* gọi OtenAuthService và cập nhật state */ }
}
```

### 11.2. UIKit

Pattern gợi ý:

- Dùng `Task {}` trong `UIViewController` để không block main thread.
- Có thể dùng một AuthManager wrap quanh `OtenAuthService`, hoặc dùng trực tiếp `OtenAuthService.shared`.

Ví dụ flow:

- `viewDidLoad` – đọc token từ Keychain (nếu có) và cập nhật UI.
- User tap Login – gọi `Task { await handleLogin() }`.

### 11.3. Presentation Anchor cho `ASWebAuthenticationSession`

`OtenAuthService` implement `ASWebAuthenticationPresentationContextProviding` và có property:

```swift
public var presentationAnchorProvider: (() -> ASPresentationAnchor)?
```

Bạn có thể set ở AppDelegate/SceneDelegate để kiểm soát window dùng cho auth (nhất là khi app có nhiều scene).

---

## 12. So sánh với AppAuth – vì sao sample không dùng?

**AppAuth (iOS)** là thư viện OIDC/OAuth2 phổ biến, chuẩn RFC, hỗ trợ nhiều use case.

### 12.1. Khi nào nên dùng AppAuth?

- Bạn cần nhiều flow phức tạp ngoài Authorization Code + PKCE.
- Bạn muốn discovery tự động từ `.well-known/openid-configuration`.
- Bạn muốn tận dụng thư viện đã được cộng đồng dùng rộng rãi.

### 12.2. Ưu/nhược điểm so với `OtenAuthService.swift`

**OtenAuthService.swift (sample hiện tại):**

- Ưu điểm:
  - Không thêm dependency bên ngoài.
  - API nhỏ, đơn giản: `configure`, `login`, `parseUserInfo`.
  - Dùng `async/await`, code gọn, dễ đọc.
  - Developer dễ follow flow OIDC từng bước, hiểu PKCE & state.
- Nhược điểm:
  - Không cover hết các advanced OIDC features.
  - Chưa có sẵn token refresh, revocation, discovery.

**AppAuth:**

- Ưu điểm:
  - Thư viện mature, nhiều tính năng, được audit rộng rãi.
  - Hỗ trợ discovery & nhiều loại grant/flow.
- Nhược điểm:
  - Thêm dependency third-party.
  - API dựa trên callback/completion, muốn dùng với `async/await` phải wrap thêm.

### 12.3. Kết luận

- Sample này ưu tiên **đơn giản, dễ copy–paste, dễ hiểu**, dùng chuẩn Authorization Code + PKCE, phù hợp cho mobile.
- Nếu sau này bạn cần nhiều tính năng OIDC hơn hoặc dùng SDK/thu viện khác (như AppAuth), bạn có thể dùng GUIDE này như “mental model” về flow, rồi map sang implementation tương ứng.

---

## Tham khảo

### Oten Documentation
- [Oten Developer Portal](https://developer.oten.com) — Quản lý ứng dụng
- [Oten Integration Guide](https://integration.oten.dev) — Tài liệu tích hợp chính thức
- [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide) — Hướng dẫn PKCE chi tiết
- [Integration Flow Diagram](https://integration.oten.dev/developer-integration-guide/integration-flow-diagram) — Sơ đồ luồng tích hợp

### Apple Developer
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — OAuth authentication trong iOS
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services) — Lưu trữ credentials an toàn
