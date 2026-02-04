# Integrating Oten Login into iOS App

A detailed step-by-step guide for beginners. After completing this guide, you will have an iOS app that can log in with Oten.

## Requirements

- macOS 13+
- Xcode 14+ (free download from [App Store](https://apps.apple.com/app/xcode/id497799835))
- iOS 16.0+

---

## Step 1: Prepare Information from Oten Developer Portal

1. Go to [Oten Developer Portal](https://developer.oten.com)
2. Create an **Integration App**
3. Inside the Integration App, create a **Native Application**
4. Configure the **Redirect URI** (e.g., `otenlogin://auth`)

**✅ After completing, you need these 3 values:**

| Information | Example |
|-------------|---------|
| `<YOUR_CLIENT_ID>` | `0d7b3c9d-124a-40b9-a936-f39fe49653ba` |
| `<YOUR_REDIRECT_URI>` | `otenlogin://auth` |
| `<YOUR_AUTH_DOMAIN>` | `https://account.oten.com` |

> 💡 **Note:** Redirect URI should follow the format `appname://auth`, e.g., `otenlogin://auth`

---

## Step 2: Create a New Project in Xcode

### 2.1. Open Xcode and Create Project

1. Open **Xcode**
2. Select **Create New Project** (or menu **File** → **New** → **Project...**)
3. Select the **iOS** tab → choose **App** → click **Next**

### 2.2. Fill in Project Information

| Field | Value | Note |
|-------|-------|------|
| Product Name | `OtenLogin` | App name |
| Team | Select your team | Or skip if you don't have one |
| Organization Identifier | `com.yourcompany` | Replace `yourcompany` with your company/personal name |
| **Interface** | **SwiftUI** or **Storyboard** | ⬅️ Choose one (see below) |
| Language | Swift | |

**Differences between the 2 Interface types:**

| | SwiftUI | Storyboard (UIKit) |
|---|---------|-------------------|
| Recommended | ✅ For beginners | For legacy projects |
| Entry file | `OtenLoginApp.swift` | `AppDelegate.swift`, `SceneDelegate.swift` |
| UI file | `ContentView.swift` | `ViewController.swift`, `Main.storyboard` |

### 2.3. Choose Where to Save Project

1. Click **Next**
2. Choose the folder where you want to save the project (e.g., Desktop or Documents)
3. Click **Create**

---

## Step 3: Create OtenAuthService.swift File

### 3.1. Create New File

1. In Xcode, go to menu **File** → **New** → **File...**
2. Select **Swift File** → click **Next**
3. Name the file: `OtenAuthService` (Xcode will automatically add the `.swift` extension)
4. Click **Create**

### 3.2. Add Code to File

1. Delete all default content in the `OtenAuthService.swift` file
2. Copy **all** the code below and paste it:

<details>
<summary><strong>👉 Click to view OtenAuthService.swift code</strong></summary>

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

## Step 4: Configure on App Launch

Use the 3 values from **Step 1** to replace in the code:
- `<YOUR_CLIENT_ID>` → Your Client ID
- `<YOUR_REDIRECT_URI>` → Redirect URI (e.g., `otenlogin://auth`)
- `<YOUR_AUTH_DOMAIN>` → Domain (e.g., `https://account.oten.com`)

⚠️ **Choose the guide that matches the Interface type you selected in Step 2:**

### Option A: SwiftUI

1. In Xcode, open the file `OtenLoginApp.swift` (in the left panel)
2. **Delete all** content in the file
3. **Copy and paste** the following code, then replace the 3 values:

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

1. In Xcode, open the file `AppDelegate.swift` (in the left panel)
2. Add the `OtenAuthService.shared.configure(...)` code inside the `application(_:didFinishLaunchingWithOptions:)` function, before the `return true` line:

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

**Example after replacement (applies to both SwiftUI and UIKit):**

```swift
OtenAuthService.shared.configure(
    clientId: "0d7b3c9d-124a-40b9-a936-f39fe49653ba",
    redirectUri: "otenlogin://auth",
    authorizeURL: "https://account.oten.com/v1/oauth/authorize",
    tokenURL: "https://account.oten.com/v1/oauth/token"
)
```

---

## Step 5: Create Login UI

⚠️ **Choose the guide that matches the Interface type you selected in Step 2:**

### Option A: SwiftUI

1. Open the file `ContentView.swift` (in the left panel)
2. **Delete all** content in the file
3. **Copy and paste** the code below:

<details>
<summary><strong>👉 Click to view ContentView.swift code</strong></summary>

```swift
import SwiftUI

struct ContentView: View {
    @State private var userInfo: OtenUserInfo?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            if let user = userInfo {
                // Logged in
                VStack(spacing: 16) {
                    Text("Welcome!")
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

                    Button("Logout") {
                        userInfo = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Not logged in
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
                print("✅ Login successful!")

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

1. Open the file `ViewController.swift` (in the left panel)
2. **Delete all** content in the file
3. **Copy and paste** the code below:

<details>
<summary><strong>👉 Click to view ViewController.swift code</strong></summary>

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
        button.setTitle("Logout", for: .normal)
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
                print("✅ Login successful!")

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
        titleLabel.text = "Welcome!"
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

## Step 6: Run the App

### 6.1. Select Simulator

1. Look at the **toolbar at the top** of Xcode
2. Find the **dropdown** next to the project name `OtenLogin`
   - It may be showing "Any iOS Device (arm64)" or an iPhone name
3. **Click on that dropdown** to open the device list
4. Under **iOS Simulators**, select an iPhone, for example:
   - **iPhone 15 Pro** (recommended)
   - Or **iPhone 15**, **iPhone 14**, **iPhone SE**...

> 💡 **Tip:** If you don't see any iPhones in the list, go to menu **Window** → **Devices and Simulators** to check.

### 6.2. Build and Run App

1. Click the **▶️ (Play)** button at the top left of Xcode
   - Or press the shortcut **⌘R** (Command + R)

2. **Wait for Xcode to build the project:**
   - The first time may take **1-3 minutes**
   - You will see a progress bar at the top
   - When complete, the Simulator will open automatically

3. **Simulator starts:**
   - The first time opening Simulator may take an additional 1-2 minutes
   - After it opens, your app will run automatically

### 6.3. Test Login

1. In the app, tap the **"Login with Oten"** button
2. **A browser will open** the Oten login page
3. Log in with your Oten account
4. After successful login:
   - The browser closes automatically
   - The app displays user info (name, email)
5. Tap **"Logout"** to return to the login screen

