//
//  OtenLoginApp.swift
//  OtenLogin
//

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
