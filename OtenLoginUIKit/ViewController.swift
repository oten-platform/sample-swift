//
//  ViewController.swift
//  OtenLoginUIKit
//

import UIKit

class ViewController: UIViewController {

    private lazy var loginButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Login with Oten"
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(loginButton)
        NSLayoutConstraint.activate([
            loginButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loginButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func loginTapped() {
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
