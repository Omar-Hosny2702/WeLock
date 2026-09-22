# WeLock

A native macOS app-lock utility by Omar Hosny.

WeLock lets you protect selected Mac applications with macOS authentication (Touch ID when available, with the normal macOS password fallback). It is independently implemented in Swift and SwiftUI and is not affiliated with MakLock.

## Features

- Protect selected installed applications
- Touch ID / macOS authentication through LocalAuthentication
- App-scoped privacy shield instead of a display-wide blocker
- Immediate or delayed re-locking
- Lock on app switching, sleep/session lock and idle timeout
- Optional auto-close per protected app
- Lock All Now
- Menu bar controls
- Launch at login
- Local settings only; no analytics, tracking or remote account
- Native Swift + SwiftUI implementation

## Requirements

- macOS 13 or later
- Accessibility permission is recommended for reliable protected-window tracking
- Current public builds are unsigned and not notarised because the project is currently distributed without a paid Apple Developer Program certificate

## Install

### Homebrew

Homebrew installation is being prepared for the v1.2.2 release.

```sh
brew install --cask Omar-Hosny2702/tap/welock
```

### Manual

Download the latest release archive, move WeLock.app to Applications, then launch it.

Because the current release is not notarised, macOS may require you to approve the app in System Settings → Privacy & Security before first launch. Do not disable Gatekeeper globally.

After launch, open WeLock → Security and grant Accessibility permission when requested.

## Known limitation: interactive Spaces gestures

WeLock is a privacy/convenience utility, not an operating-system security boundary.

macOS does not provide a supported public API that lets one third-party application attach its own window to another application's window during the live animation of an interactive trackpad Space-switch gesture. On the current v1.2.2 build, protected content can temporarily become visible during some partial/interactive Space swipes.

This limitation is intentionally documented rather than hidden. Normal app switching and authentication protection remain the primary supported workflow. For high-assurance protection, also use macOS account security and any locking features built into the protected application.

## Privacy

WeLock stores its preferences locally. It does not include analytics, advertising, tracking, a remote account system or a network service. Authentication is performed by macOS using LocalAuthentication; WeLock does not store your Mac password or Touch ID data.

## Build from source

```sh
xcodebuild -project WeLock.xcodeproj \
  -scheme WeLock \
  -configuration Debug \
  build \
  CODE_SIGNING_ALLOWED=NO
```

Or open `WeLock.xcodeproj` in Xcode and run the WeLock scheme.

## Permissions

WeLock uses Accessibility APIs for cross-process window geometry and protection behaviour. It does not require Screen Recording, Full Disk Access, Apple Events or a privileged helper for its current design.

## Security scope

WeLock deliberately avoids private APIs, code injection, SIP modifications and display-wide fallback overlays. These choices keep the project within supported macOS APIs, but also mean it cannot provide the same guarantees as an operating-system-level access-control mechanism.

## Version

Current release target: **v1.2.2**

## Licence

MIT License. See `LICENSE`.

Copyright © 2026 Omar Hosny.
