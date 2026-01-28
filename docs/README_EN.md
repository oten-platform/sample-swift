# Oten Login iOS – Deep Dive Guide

This document explains in detail how an iOS application integrates with **Oten IDP** following the **OAuth 2.0 / OpenID Connect** standard using **Authorization Code Flow + PKCE**.

> **Public Client (Native Application):** According to the [Oten Integration Guide](https://integration.oten.dev), PKCE is **required** for mobile apps. JAR (JWT-Secured Authorization Request) is **not applicable** for public clients.

- If you only need **quick integration** → see [GUIDE_EN.md](./GUIDE_EN.md)
- If you want to **understand the flow and security in depth** → continue reading

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Authorization Code Flow + PKCE](#2-authorization-code-flow--pkce)
3. [Dissecting the login() function](#3-dissecting-the-login-function-in-otenauthservice)
4. [PKCE – code_verifier & code_challenge](#4-pkce--code_verifier--code_challenge)
5. [State validation – CSRF protection](#5-state-validation--csrf-protection--wrong-app-redirect)
6. [Token Exchange](#6-token-exchange--exchanging-authorization-code-for-tokens)
7. [ID Token & parseUserInfo](#7-id-token--parseuserinfo)
8. [Token Storage & Keychain](#8-token-storage--keychain-best-practice)
9. [Security considerations](#9-security-considerations--best-practices)
10. [Configuration Management](#10-configuration-management)
11. [SwiftUI + UIKit Integration](#11-swiftui--uikit-integration-notes)
12. [Comparison with AppAuth](#12-comparison-with-appauth--why-sample-doesnt-use-it)
13. [References](#references)

---

## 1. Architecture Overview

At a high level, there are 3 main components:

- **iOS Application** (SwiftUI / UIKit)
- **Oten IDP** – identity server (OpenID Provider)
- **OtenAuthService** – helper class in the app, encapsulating the entire OIDC flow

Your application:

- Calls `OtenAuthService.shared.configure(...)` with information from Oten IDP.
- When user taps "Login with Oten", calls `await OtenAuthService.shared.login()`.
- Receives `OtenTokenResponse` containing:
  - `accessToken`
  - `idToken`
  - (depending on config) `refreshToken`
- (Optional) Parse `idToken` into `OtenUserInfo` to display profile.

---

## 2. Authorization Code Flow + PKCE

Standard flow according to Oten's [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide):

1. **User taps Login in iOS app**  
   App initiates OIDC Authorization Request.
2. **App opens secure browser (ASWebAuthenticationSession) pointing to Oten**  
   URL contains:
   - `response_type=code`
   - `client_id`
   - `redirect_uri`
   - `scope`
   - `code_challenge` + `code_challenge_method=S256` (PKCE)
   - `state` (CSRF protection)
3. **User logs in & grants permission on Oten**  
   User enters username/password or uses SSO. Oten IDP authenticates and asks for consent (depending on configuration).
4. **Oten redirects back to app via `<YOUR_REDIRECT_URI>`**  
   Redirect contains:
   - `code` – Authorization Code (short-lived, single-use)
   - `state` – for app to verify it matches the value sent initially
5. **App exchanges Authorization Code for Tokens**  
   App sends POST request to token endpoint with `code_verifier`. Oten returns:
   - `access_token`
   - `id_token`
   - `refresh_token` (if granted)
   - other metadata

`OtenAuthService` is where you map each of these steps into Swift code.

---

## 3. Dissecting the `login()` function in OtenAuthService

Main public API:

- `configure(...)`
- `login() async throws -> OtenTokenResponse`
- `parseUserInfo(from idToken: String) throws -> OtenUserInfo`
- `isConfigured: Bool`

Flow in `login()` (simplified):

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

Step-by-step explanation:

1. **Check if configured** – if `configure(...)` hasn't been called → throw `OtenAuthError.notConfigured`.
2. **Create PKCE parameters (code_verifier, code_challenge) and state** – using helpers `generateCodeVerifier`, `generateCodeChallenge`, `generateState`.
3. **Build authorize URL** – `buildAuthorizeURL(...)` appends query string per OIDC standard.
4. **Open ASWebAuthenticationSession** – `presentAuthenticationSession(...)` calls `ASWebAuthenticationSession.start()` and waits for callback.
5. **Validate callback & extract authorization code** – `extractAuthorizationCode(...)` checks for errors, validates `state`, extracts `code`.
6. **Exchange code for tokens** – `exchangeCodeForTokens(...)` sends POST to token endpoint.

---

## 4. PKCE – `code_verifier` & `code_challenge`

### 4.1. Why is PKCE needed?

PKCE (Proof Key for Code Exchange) solves the problem:

- On mobile apps, you **cannot** keep client secret secure.
- If an attacker intercepts the Authorization Code at step 4, they still **cannot** exchange it for tokens without the original `code_verifier` (only the app knows this).

Mechanism:

- App creates `code_verifier` (strong random string).
- From `code_verifier`, app creates `code_challenge = BASE64URL(SHA256(code_verifier))`.
- App sends `code_challenge` to authorize endpoint.
- When exchanging code for tokens, app sends back the `code_verifier`.
- IDP computes `SHA256(code_verifier)` and compares with the original `code_challenge`. If they don't match → reject.

### 4.2. Implementation in OtenAuthService

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

Key points:

- Uses **SHA256** + Base64URL (not standard Base64).
- 128 characters for `code_verifier` is good per PKCE recommendation.

---

## 5. State validation – CSRF protection / wrong app redirect

`state` is a random string, self-generated by the app (usually a UUID, not easily guessable). Purpose:

- When sending authorize request, app attaches `state`.
- When receiving callback, app reads `state` from query and compares with stored state.
- If they don't match → **immediately reject** (throw error).

Generate state:

```swift
private func generateState() -> String {
    return UUID().uuidString.replacingOccurrences(of: "-", with: "")
}
```

Validate in callback (concept):

```swift
guard let state = queryItems.first(where: { $0.name == "state" })?.value,
      state == expectedState else {
    throw OtenAuthError.invalidState
}
```

Significance:

- If `state` mismatches → callback may not be for the current flow (CSRF attack, another app opening same redirect URI, etc.).
- By throwing `invalidState`, you ensure **never exchanging code for token** in suspicious cases.

---

## 6. Token Exchange – Exchanging Authorization Code for Tokens

### 6.1. Request sent to token endpoint

In `exchangeCodeForTokens(...)`, app sends (x-form-encoded):

- `grant_type=authorization_code`
- `code` – code received from callback
- `redirect_uri` – must match the registered and used value from authorize step
- `client_id`
- `code_verifier` – used for PKCE

Example body construction:

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

If successful, IDP returns JSON like:

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

Mapping to struct:

```swift
public struct OtenTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let idToken: String?
    public let scope: String?
}
```

You use `accessToken` to:

- Call backend APIs (put in header `Authorization: Bearer <accessToken>`).

Use `idToken` to:

- Get user profile information (name, email…).

---

## 7. ID Token & `parseUserInfo`

### 7.1. What is ID Token?

- It's a **JWT** containing claims about the user (subject, email, name, picture, exp, …).
- Primarily used for **authentication** (who is logged in), not for authorization with APIs (that's the role of `accessToken`).

Example ID Token payload:

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

`OtenAuthService` has a built-in parse function:

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

Corresponding struct:

```swift
public struct OtenUserInfo: Codable, Sendable {
    public let sub: String?
    public let email: String?
    public let name: String?
    public let picture: String?
    public let exp: TimeInterval?
}
```

Common use case:

- After successful `login()`:
  - If `tokens.idToken` exists:
    - Call `parseUserInfo`.
    - Store `OtenUserInfo` in ViewModel/state.
    - Use to display avatar, name, email.

---

## 8. Token Storage & Keychain (Best Practice)

This sample only **keeps tokens in memory** for simplicity. In production apps, you **must** store tokens securely.

### 8.1. Why use Keychain?

| Method | Security | Notes |
|--------|----------|-------|
| **Keychain** | ✅ Secure | Encrypted by iOS, cannot be read by other apps |
| UserDefaults | ❌ Not secure | Plain text, easily readable |
| Text file | ❌ Not secure | Can be backed up, extracted |

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

        // Delete old item if exists
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

### 8.3. Usage

```swift
// After successful login
func saveTokens(_ tokens: OtenTokenResponse) {
    KeychainHelper.save(tokens.accessToken, forKey: "oten_access_token")

    if let refreshToken = tokens.refreshToken {
        KeychainHelper.save(refreshToken, forKey: "oten_refresh_token")
    }

    if let idToken = tokens.idToken {
        KeychainHelper.save(idToken, forKey: "oten_id_token")
    }
}

// When app launches - check if already logged in
func checkExistingSession() -> Bool {
    return KeychainHelper.load(forKey: "oten_access_token") != nil
}

// Logout
func logout() {
    KeychainHelper.deleteAll()
}
```

### 8.4. Keychain Keys

| Token | Key | Description |
|-------|-----|-------------|
| `accessToken` | `oten_access_token` | Call backend APIs |
| `refreshToken` | `oten_refresh_token` | Get new access token |
| `idToken` | `oten_id_token` | User info (JWT) |

> ⚠️ **Note:** Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so tokens can only be read when device is unlocked and won't be backed up to other devices.

---

## 9. Security considerations & best practices

Key points when taking this sample into production:

1. **Don't embed client secret in the app** – mobile/native apps cannot keep secrets; use PKCE instead of client secret.
2. **Always use HTTPS with official Oten domain** – e.g., `https://account.dev.oten.dev`, `https://account.oten.live`.
3. **Protect tokens** – store in Keychain, don't log full tokens, only log prefix if debugging.
4. **Verify Redirect URI & URL Scheme carefully** – must match between Oten config, Xcode, and value passed to `configure(...)`.
5. **Control scope** – only request scopes you actually need (e.g., `openid profile email`); consider `offline_access` if refresh token is needed.
6. **Handle errors carefully** – distinguish network error, cancel, invalidState to show appropriate UX.

---

## 10. Configuration Management

Instead of hardcoding credentials in code, manage configuration systematically for easy switching between environments.

### 10.1. Why not hardcode?

| Problem | Consequence |
|---------|-------------|
| Hardcode in code | Must modify code when changing environment |
| Commit credentials | Sensitive info exposed on Git |
| Hard to maintain | Easy to confuse Dev/Staging/Prod |

### 10.2. Using Info.plist + xcconfig

**Step 1: Create `.xcconfig` files for each environment**

```
// Config/Dev.xcconfig
OTEN_CLIENT_ID = dev-client-id-xxx
OTEN_AUTH_DOMAIN = https:$()/account.dev.oten.dev
OTEN_REDIRECT_URI = yourapp:$()/auth

// Config/Prod.xcconfig
OTEN_CLIENT_ID = prod-client-id-xxx
OTEN_AUTH_DOMAIN = https:$()/account.oten.live
OTEN_REDIRECT_URI = yourapp:$()/auth
```

**Step 2: Add to Info.plist**

```xml
<key>OtenClientID</key>
<string>$(OTEN_CLIENT_ID)</string>
<key>OtenAuthDomain</key>
<string>$(OTEN_AUTH_DOMAIN)</string>
<key>OtenRedirectURI</key>
<string>$(OTEN_REDIRECT_URI)</string>
```

**Step 3: Read config in code**

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

### 10.3. Usage at app startup

```swift
// AppDelegate or App init
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

### 10.4. Switching environments

In Xcode:
1. **Product → Scheme → Edit Scheme**
2. Select **Build Configuration** (Debug/Release)
3. Assign corresponding `.xcconfig` file for each configuration

| Configuration | xcconfig | Environment |
|---------------|----------|-------------|
| Debug | `Dev.xcconfig` | Development |
| Release | `Prod.xcconfig` | Production |

> 💡 **Tip:** Add `*.xcconfig` to `.gitignore` if it contains sensitive information, and create `.xcconfig.example` file as a template.

---

## 11. SwiftUI + UIKit Integration Notes

### 11.1. SwiftUI

Suggested pattern:

- Create an `ObservableObject` to manage:
  - `isAuthenticated`
  - `currentUser: OtenUserInfo?`
  - `lastError: String?`
- From View, call `login()` on ViewModel (ViewModel calls `OtenAuthService.shared.login()`).

Example ViewModel structure:

```swift
final class AuthViewModel: ObservableObject {
    @Published var userInfo: OtenUserInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func login() async { /* call OtenAuthService and update state */ }
}
```

### 11.2. UIKit

Suggested pattern:

- Use `Task {}` in `UIViewController` to not block main thread.
- Can use an AuthManager wrapper around `OtenAuthService`, or use `OtenAuthService.shared` directly.

Example flow:

- `viewDidLoad` – read token from Keychain (if exists) and update UI.
- User taps Login – call `Task { await handleLogin() }`.

### 11.3. Presentation Anchor for `ASWebAuthenticationSession`

`OtenAuthService` implements `ASWebAuthenticationPresentationContextProviding` and has property:

```swift
public var presentationAnchorProvider: (() -> ASPresentationAnchor)?
```

You can set this in AppDelegate/SceneDelegate to control which window is used for auth (especially when app has multiple scenes).

---

## 12. Comparison with AppAuth – Why sample doesn't use it?

**AppAuth (iOS)** is a popular OIDC/OAuth2 library, RFC-compliant, supporting many use cases.

### 12.1. When should you use AppAuth?

- You need many complex flows beyond Authorization Code + PKCE.
- You want automatic discovery from `.well-known/openid-configuration`.
- You want to leverage a library widely used by the community.

### 12.2. Pros/Cons compared to `OtenAuthService.swift`

**OtenAuthService.swift (current sample):**

- Pros:
  - No external dependencies.
  - Small, simple API: `configure`, `login`, `parseUserInfo`.
  - Uses `async/await`, clean and readable code.
  - Developer can easily follow OIDC flow step by step, understand PKCE & state.
- Cons:
  - Doesn't cover all advanced OIDC features.
  - No built-in token refresh, revocation, discovery.

**AppAuth:**

- Pros:
  - Mature library, many features, widely audited.
  - Supports discovery & many grant types/flows.
- Cons:
  - Adds third-party dependency.
  - API based on callback/completion, need to wrap for `async/await`.

### 12.3. Conclusion

- This sample prioritizes **simplicity, easy to copy–paste, easy to understand**, using standard Authorization Code + PKCE, suitable for mobile.
- If later you need more OIDC features or want to use another SDK/library (like AppAuth), you can use this GUIDE as a "mental model" for the flow, then map to corresponding implementation.

---

## References

### Oten Documentation
- [Oten Developer Portal](https://developer.oten.live) — App management
- [Oten Integration Guide](https://integration.oten.dev) — Official integration documentation
- [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide) — Detailed PKCE guide
- [Integration Flow Diagram](https://integration.oten.dev/developer-integration-guide/integration-flow-diagram) — Integration flow diagram

### Apple Developer
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — OAuth authentication in iOS
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services) — Secure credential storage
