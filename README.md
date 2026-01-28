# Oten Login iOS Sample

iOS sample project demonstrating **OAuth 2.0 / OpenID Connect** integration with Oten IDP using **Authorization Code Flow + PKCE**.

## ✨ Features

- ✅ Pure Swift, no dependencies
- ✅ Modern async/await with `ASWebAuthenticationSession`
- ✅ PKCE for secure native apps
- ✅ Both SwiftUI and UIKit implementations

## 📱 Requirements

- iOS 16.0+ · Xcode 14.0+ · Swift 5.7+

## 🚀 Quick Start

```bash
git clone https://github.com/your-org/sample-swift.git
cd sample-swift
open OtenLogin.xcodeproj
```

Configure credentials in `OtenLoginApp.swift` (SwiftUI) or `AppDelegate.swift` (UIKit), then run.

## 📚 Documentation

- **[GUIDE.md](./docs/GUIDE.md)** / **[GUIDE_EN.md](./docs/GUIDE_EN.md)** — Quick integration guide
- **[README.md](./docs/README.md)** / **[README_EN.md](./docs/README_EN.md)** — Deep dive: OAuth flow & security

## 🏗️ Project Structure

```
sample-swift/
├── OtenLogin/              # SwiftUI target
│   └── Oten/OtenAuthService.swift
├── OtenLoginUIKit/         # UIKit target
│   └── Oten/OtenAuthService.swift
└── docs/                   # Full documentation
```

## 📖 Learn More

- [Oten Developer Portal](https://developer.oten.live)
- [Oten Integration Guide](https://integration.oten.dev)