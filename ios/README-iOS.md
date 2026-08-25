# The Sharp Edge — iPad app

A native SwiftUI iPadOS app for The Sharp Edge. It talks to the existing FastAPI
backend over Tailscale — browse, kitchen-sane scaling, cook mode, editing,
Library search, and streaming Ask/RAG. This laptop is only the build machine; the
shipped app has zero dependency on it.

## Requirements
- Xcode 16+ (built/tested with 16.4, iOS 18.5 SDK)
- iPadOS 17.0+ target
- For real data: the iPad on the **home Tailscale network** with the backend stack running.

## Open & run (simulator)
```bash
open "ios/TheSharpEdge.xcodeproj"
# Scheme: TheSharpEdge · Destination: any iPad simulator · ⌘R
```

Headless build + run:
```bash
DEV=/Applications/Xcode.app/Contents/Developer
DEVELOPER_DIR=$DEV xcodebuild -project ios/TheSharpEdge.xcodeproj -scheme TheSharpEdge \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' \
  -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=$DEV xcrun simctl install booted ios/build/Build/Products/Debug-iphonesimulator/TheSharpEdge.app
DEVELOPER_DIR=$DEV xcrun simctl launch booted com.sharpedge.TheSharpEdge
```

> Note: `xcode-select` on this machine points at CommandLineTools, so prefix
> `xcodebuild`/`simctl` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
> (or run `sudo xcode-select -s /Applications/Xcode.app`).

### Sample data
In DEBUG the app defaults to **sample data** (bundled fixtures) so every screen works
without the backend. Toggle it in **Settings → Developer → Use sample data**, or set the
launch env var `SIMCTL_CHILD_UITEST_ROUTE=<slug|library|ask|gluten|settings>` to open a
screen directly for screenshots.

## Point at the real backend
1. Ensure the iPad has **Tailscale** active and the FastAPI stack is running.
2. In the app: **Settings**
   - **Base URL**: `http://100.110.190.10:8010` (the default; compose publishes the API on host port 8010)
   - **API token**: the deployment's `API_TOKEN` (only needed to save recipe edits). Reads, scaling, Ask and Library search need no token.
   - Turn **off** "Use sample data".
   - Tap **Test connection** — expect "API ok" (or "API + index ok" when Atlas/RAG is reachable).

The token is stored in the **Keychain**; the base URL and GF filter in UserDefaults.
Ask streams over SSE; Library search and Ask require the Atlas stack (they degrade
gracefully — "index unreachable" — when it's down).

## TestFlight
1. **Signing**: select the target → **Signing & Capabilities** → check *Automatically manage
   signing* → pick your **Team**. (Team ID can't be committed, so this is the one manual step.)
2. Optionally change the **bundle identifier** (`com.sharpedge.TheSharpEdge`) to one in your
   developer account before the first upload. Bump `MARKETING_VERSION` / build number per release.
3. **Product → Archive**, then **Distribute App → TestFlight & App Store Connect**.
4. **App Transport Security**: the app ships with `NSAllowsArbitraryLoads` because the backend
   is plain HTTP over the private tailnet. That's intentional for this self-hosted app; if App
   Review asks, the justification is "connects only to a user-configured server on the user's
   own private network."
5. **Local network**: `NSLocalNetworkUsageDescription` is set — iOS will prompt on first
   connect to a Tailscale `100.x` host.

## Fonts
Ships on system fallbacks (serif display, monospaced quantities) so it builds with no
bundled fonts. To use the real faces, drop `Fraunces`, `Work Sans` and `Spline Sans Mono`
`.ttf`s into `TheSharpEdge/` — `FontRegistrar` registers them at launch automatically (the
synchronized project group picks them up with no pbxproj edit).

## Layout
```
ios/TheSharpEdge/
  App/            App entry, NavigationSplitView shell, environment
  Config/         AppConfig (URL/token/flags), Keychain
  Models/         Codable mirrors of the API schemas
  Networking/     APIClient, SSEClient, Endpoints, JSON coding, DataSource, errors
  Domain/         ScalingEngine (server-parity), StepText, Grouping
  DesignSystem/   Theme tokens, Typography, Components
  Features/       Home, Recipe, Cook, Library, Ask, Editor, Settings, Reference
  Support/        SampleData + SampleDataSource
  Info.plist      ATS + local-network + scene keys
```

The scaling math in `Domain/ScalingEngine.swift` is a verbatim port of
`api/app/services/scaling.py` and is verified against the server's `test_scaling.py`
table (44 checks) — the server's `/recipes/{slug}/scale` remains canonical for
shopping-list/card export.
