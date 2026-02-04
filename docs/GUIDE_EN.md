# Oten Login - iOS Integration Guide

A guide to integrating Oten login into iOS applications using **Authorization Code Flow + PKCE** following OAuth 2.0 / OpenID Connect standards.

> **Public Client (Native Application):** PKCE is **required** according to [Oten Integration Guide](https://integration.oten.dev).

**Requirements:** macOS 13+ · Xcode 14+ · iOS 16.0+

> 📘 **New to iOS development?** See [BEGINNER_EN.md](./BEGINNER_EN.md) for a detailed step-by-step guide to create a project from scratch.

---

## ⚡ Quick Start

1. Go to [Oten Developer Portal](https://developer.oten.com): create Integration App → create Native App → config Redirect URI → get Client ID, Redirect URI, Auth Domain
2. Copy `OtenAuthService.swift` into your project
3. Call `configure(...)` when app launches
4. Call `await OtenAuthService.shared.login()`

---

## 🚀 Run Sample Project

### Step 1: Open project
- Download `sample-swift.zip` and extract (or clone repository)
- Open `OtenLogin.xcodeproj`

### Step 2: Configure credentials

Use 3 values from Oten Developer Portal to replace in the code:
- `<YOUR_CLIENT_ID>` → Your Client ID
- `<YOUR_REDIRECT_URI>` → Redirect URI (e.g., `otenlogin://auth`)
- `<YOUR_AUTH_DOMAIN>` → Auth Domain:
  - Production: `https://account.oten.com`
  - Development: `https://account.dev.oten.dev`

**If running SwiftUI target (OtenLogin):**
- Open `OtenLogin/OtenLoginApp.swift`, find the `init()` function

**If running UIKit target (OtenLoginUIKit):**
- Open `OtenLoginUIKit/AppDelegate.swift`, find the `application(didFinishLaunchingWithOptions:)` function

```swift
OtenAuthService.shared.configure(
    clientId: "<YOUR_CLIENT_ID>",
    redirectUri: "<YOUR_REDIRECT_URI>",
    authorizeURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/authorize",
    tokenURL: "<YOUR_AUTH_DOMAIN>/v1/oauth/token"
)
```

### Step 3: Run
- Select target:
  - **OtenLogin** (SwiftUI) - Default
  - **OtenLoginUIKit** (UIKit) - If you want to see UIKit demo
- Select simulator or device
- Press **⌘R** to run

### Step 4: Test login
- Tap **"Login with Oten"** button
- Login in browser
- Check tokens in console

> 💡 **Tip:** If you don't have Client ID and Redirect URI yet, see [Step 1: Create app on Oten Developer Portal](#step-1-create-app-on-oten-developer-portal)

> 📱 **Demo implementations:** Project includes 2 targets:
> - **OtenLogin (SwiftUI):** `ContentView.swift` - Default target
> - **OtenLoginUIKit (UIKit):** `ViewController.swift` - Select this target to run UIKit demo

---

## Table of Contents

| # | Integration into your project |
|---|------|
| 1 | [Create app on Oten](#step-1-create-app-on-oten-developer-portal) |
| 2 | [Add OtenAuthService](#step-2-add-otenauthservice-to-project) |
| 3 | [Configure App](#step-3-configure-on-app-launch) |
| 4 | [Call Login](#step-4-call-login) |

**Extensions:** [Get User Info](#get-user-info) · [Store Tokens](#store-tokens) · [Error Handling](#error-handling) · [Best Practices](#best-practices) · [References](#references)

---

## Step 1: Create app on Oten Developer Portal

1. Go to [Oten Developer Portal](https://developer.oten.com)
2. Create an **Integration App**
3. Inside the Integration App, create a **Native Application**
4. Configure **Redirect URI** (e.g., `otenlogin://auth`)

**✅ After completion, you need these 3 values:**

| Information | Example |
|-------------|---------|
| `<YOUR_CLIENT_ID>` | `0d7b3c9d-124a-40b9-a936-f39fe49653ba` |
| `<YOUR_REDIRECT_URI>` | `otenlogin://auth` |
| `<YOUR_AUTH_DOMAIN>` | `https://account.oten.com` |

> 💡 **Note:** Redirect URI should follow the format `appname://auth`, e.g., `otenlogin://auth`

---

## Step 2: Add OtenAuthService to project

Create file `OtenAuthService.swift` in your project and copy the content below:

<details>
<summary><strong>OtenAuthService.swift</strong> (click to expand)</summary>

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

> **Tip:** Drag and drop `OtenLogin/Oten/OtenAuthService.swift` from the sample into your project, select "Copy items if needed".

---

## Step 3: Configure on app launch

Call `configure()` **once** when app launches, **before** calling `login()`.

**SwiftUI (App init):**

If your project uses pure SwiftUI (no AppDelegate):

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

> **Note:** If your SwiftUI project has `@UIApplicationDelegateAdaptor`, use the AppDelegate approach below.

**UIKit (AppDelegate):**

If your project uses UIKit with `AppDelegate.swift`:

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

⚠️ **Important:** Replace `<YOUR_CLIENT_ID>`, `<YOUR_REDIRECT_URI>`, `<YOUR_AUTH_DOMAIN>` with information from Step 1.

---

## Step 4: Call login

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

When user taps the button, the system opens a browser for login. After successful login, the app receives tokens.

---

## Extensions

The sections below are optional, helping you handle additional tasks after successful login.

---

### Get User Info

After successful login, you can get user info from `idToken`:

```swift
if let idToken = tokens.idToken {
    let userInfo = try OtenAuthService.shared.parseUserInfo(from: idToken)
    print("User ID: \(userInfo.sub ?? "N/A")")
    print("Name: \(userInfo.name ?? "N/A")")
    print("Email: \(userInfo.email ?? "N/A")")
}
```

| Property | Description |
|----------|-------------|
| `sub` | User ID (unique) |
| `name` | Display name |
| `email` | Email |
| `picture` | Avatar URL |

---

### Store Tokens

This sample only prints tokens to console. In production, you should store tokens in **Keychain** using Apple's [Security framework](https://developer.apple.com/documentation/security/keychain_services).

| Token | Description |
|-------|-------------|
| `accessToken` | Used to call APIs (`Authorization: Bearer <token>`) |
| `refreshToken` | Used to get new access token when expired |
| `idToken` | JWT containing user info |

---

### Error Handling

```swift
do {
    let tokens = try await OtenAuthService.shared.login()
} catch let error as OtenAuthError {
    switch error {
    case .authenticationCancelled:
        print("User cancelled login")
    case .notConfigured:
        print("configure() not called")
    default:
        print("Error: \(error.localizedDescription)")
    }
} catch {
    print("Unknown error: \(error)")
}
```

| Error | Cause |
|-------|-------|
| `.notConfigured` | `configure()` not called |
| `.authenticationCancelled` | User cancelled login |
| `.invalidState` | Security error (CSRF) |
| `.tokenExchangeFailed` | Error exchanging code for token |

> See all errors in `OtenAuthError` enum.

---

## Best Practices

### Configuration Management

Instead of hardcoding credentials in code, store them in `Info.plist` for easier management across environments (Dev/Staging/Prod):

**Info.plist:**
```xml
<key>OtenClientID</key>
<string>$(OTEN_CLIENT_ID)</string>
<key>OtenAuthDomain</key>
<string>$(OTEN_AUTH_DOMAIN)</string>
<key>OtenRedirectURI</key>
<string>$(OTEN_REDIRECT_URI)</string>
```

**Read config in code:**
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

> 💡 **Tip:** Use `.xcconfig` files to manage different values for each environment.

### Store Tokens in Keychain

Tokens must be stored securely in Keychain, not UserDefaults:

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

// Usage
KeychainHelper.save(tokens.accessToken, forKey: "oten_access_token")
KeychainHelper.save(tokens.refreshToken ?? "", forKey: "oten_refresh_token")
```

---

## References

- [Oten Developer Portal](https://developer.oten.com) — App management
- [Oten Integration Guide](https://integration.oten.dev) — Official integration documentation
- [PKCE Implementation Guide](https://integration.oten.dev/developer-integration-guide/pkce-implementation-guide) — Detailed PKCE guide
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession) — Apple Developer
