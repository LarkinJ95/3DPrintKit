# PrintKit for iOS

A premium, local-first toolkit for FDM/FFF 3D printing: NFC/QR-tagged spool
inventory, a 32-material reference database, print readiness checks, drying
timers with Live Activities, calculators, calibration guidance, maintenance
tracking, projects, and print analytics.

## Requirements

- **Xcode 15.0 or newer** (Swift 5.9+)
- **iOS / iPadOS 17.0 or newer** (deployment target is 17.0)
- For NFC features: a physical iPhone (iPhone 7 or newer) — NFC does not work
  in the Simulator

## Getting started

1. Unzip the project.
2. Double-click **`PrintKit.xcodeproj`**.
3. Select the **PrintKit** scheme (top toolbar) and any iOS 17+ simulator or device.
4. In the project editor → **PrintKit** target → *Signing & Capabilities*,
   pick your **Development Team**. The project uses **automatic signing** with
   the team left intentionally unset; the bundle ID is `com.printkit.app`
   (change it if your account requires a unique ID — also update the widget
   target to `<your-id>.widgets`).
5. Press **Run** (⌘R). No other setup is required — the app works fully
   offline and ships with its seed data bundled.

## Dependencies

**Zero third-party dependencies.** Everything is built on Apple frameworks:
SwiftUI, SwiftData, Core NFC, ActivityKit, App Intents, Charts, PhotosUI,
UserNotifications, AVFoundation, AuthenticationServices. Nothing to resolve,
nothing to download.

## Capabilities

The entitlements file (`PrintKit/PrintKit.entitlements`) declares:

- **Core NFC** (`NDEF` + `TAG`) — required to read/write spool tags.
  Xcode will add the *Near Field Communication Tag Reading* capability
  automatically when you pick your team.
- **Sign in with Apple** — used only if you connect the optional PrintKit
  Cloud backend. The capability must be enabled on your App ID; Xcode handles
  this when automatic signing is on.

Live Activities need no entitlement — `NSSupportsLiveActivities` is already in
`Info.plist`.

## NFC testing

NFC **requires a physical device**; in the Simulator the scan sheet explains
that NFC is unavailable and offers QR scanning instead. On device:

1. Run the app on an iPhone (any free/paid developer account works).
2. Spools tab → ⋯ → **Write NFC Tag**, pick a spool, hold an NTAG213/215/216
   sticker near the top of the phone.
3. The app writes a compact, versioned JSON payload (`printkit.spool` v1) and
   verifies it by reading it back. **Lock Tag** is permanent and clearly
   warned; PrintKit never clones or emulates proprietary tag formats.
4. Scanning an unknown PrintKit tag offers to import the spool.

Every spool can also show a **QR code** encoding the same identity
(`printkit://spool/<uuid>`) — printable labels live under
Spools → ⋯ → Label (PDF via ShareLink).

## Simulator limitations

- **NFC**: unavailable (graceful fallback + QR path).
- **Camera QR scanning**: no camera in the Simulator; use a device or paste a
  `printkit://` deep link into Safari.
- **Live Activities**: work in the Simulator (iOS 17+).
- **Sign in with Apple**: works in the Simulator against your own backend.

## Seed data

On first launch the app seeds storage locations only — your inventory starts
empty. To explore with realistic data: **Settings → Load Sample Data** adds an
example printer (X1-Carbon with AMS), three spools, a known-good PETG profile,
and a print record. The 32-material reference database (`Resources/materials.json`)
is always bundled — reference values, labeled, never fabricated.

## Tests

```text
⌘U  (or: xcodebuild test -scheme PrintKit -destination 'platform=iOS Simulator,name=iPhone 15')
```

- `PrintKitTests` — unit tests for filament math, cost engine, NFC payload
  round-trips, material library integrity, readiness engine, advisor ranking,
  and SwiftData model behavior.
- `PrintKitUITests` — tab navigation and core flows.

## Optional: connect your own backend

The app is fully functional offline. For multi-device sync, deploy the
Cloudflare backend in `../../backend` (see its README), then in the app:
**Settings → Sync & Account → API base URL**, and sign in with Apple.
Session tokens live only in the Keychain; sync is delta-based, cursor-paged,
and survives offline use via a persistent operation journal.

## Known limitations

- Photo attachments are stored in the local SwiftData store; they are not part
  of cloud sync yet (R2 upload endpoint exists server-side).
- The readiness engine evaluates static printer capabilities; it does not talk
  to printers over the network (no fake telemetry).
- CloudKit is not enabled; the schema is prepared for it (optional
  relationships, no `.unique` constraints).
