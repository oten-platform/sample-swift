//
//  ContentView.swift
//  OtenLogin
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button("Login with Oten") {
                login()
            }
        }
    }

    private func login() {
        Task {
            do {
                let tokens = try await OtenAuthService.shared.login()
                print("✅ Login success! Access token: \(tokens.accessToken.prefix(20))...")

                // Parse user info từ ID token
                if let idToken = tokens.idToken {
                    let userInfo = try OtenAuthService.shared.parseUserInfo(from: idToken)
                    print("Sub: \(userInfo.sub ?? "N/A")")
                    print("User: \(userInfo.name ?? "N/A")")
                    print("Email: \(userInfo.email ?? "N/A")")
                }
            } catch {
                print("❌ Login failed: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ContentView()
}
