# ios: conventions
SwiftUI, Swift 6 (strict concurrency complete), iOS 17+, XcodeGen. Generate the
project with `xcodegen generate` in `ios/`; never commit the `.xcodeproj`.

- Structure: `App/` (entry point, assets, string catalog), `Packages/Core`
  (auth, networking, models, experiment events), `Packages/Features`
  (screens per feature, CLASSIC and AGENT mode), `AppTests/`, `AppUITests/`.
- Concurrency: UI types are `@MainActor`; shared state in actors; models `Sendable`.
  No `@unchecked Sendable` without a comment explaining why.
- UI follows docs/design/ via DesignSystem components: no hard-coded colours or
  sizes. Apple HIG and system components win over mockups; report every deviation.
- Every screen: loading/empty/error/offline states (docs/design/screen-state-matrix.md),
  VoiceOver labels, Dynamic Type up to the largest accessibility sizes, strings in
  `Localizable.xcstrings` for DE/FR/IT/EN (no string literals in views).
- Auth: MSAL tokens only in Keychain; never log tokens or PII. No secrets in
  source, plist or xcconfig. Business rules live in api/, never in the app.
- Agent mode: writes happen only after the user taps the confirm card, which
  obtains the `confirmation_token`.
- Emit experiment events per docs/experiment/metrics.md for every task flow.
- Tests: Swift Testing for unit tests; XCUITest for flows. Tag every test with its requirement ID.
- Verify: `./scripts/ci-check.sh`; UI changes also `./scripts/screenshot.sh`.
- Signing, device builds and App Store Connect are human-only. Bundle id is a
  placeholder (`ch.example.employee`) until the human sets the retailer.
