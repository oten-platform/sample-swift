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
