# ReFind One · offline-first iOS app

A native, Russian-language personal collection for saved URLs, notes, screenshots, and PDF text. Built to minimize friction inside **LiveContainer**. **This is a source-code MVP, not a prebuilt/signed IPA.**

## What is implemented (v0.2 source)

- SwiftUI library with search, category chips, favorites, details, notes, tags, delete confirmation.
- Manual URL/text capture; detects HTTP/HTTPS and removes *known tracking* query parameters while preserving video/time IDs. Duplicate cleaned URLs are not saved twice.
- Photo import via PhotosPicker, local Apple Vision OCR, searchable extracted text.
- Import from Files: JPEG/PNG/HEIC, TXT and searchable PDF. PDF image-only pages don't yet undergo page OCR.
- SQLite WAL + FTS5 search, with escaped parameter binding and fallback LIKE.
- Local attachment storage, 20 MB/file limit. Export/import complete library as JSON v1, including Base64 attachments; add-only restore. **Backup is NOT encrypted**.
- No account, no server, no tracking SDK, no custom entitlement, no JIT, no extensions.

## Requirements

- **To compile an iOS app or IPA:** macOS with Xcode and an iPhone SDK (a **cloud macOS runner** is sufficient; you do not have to own a Mac); signing/certificate for installing or configured LiveContainer JIT-less signing. This workspace is Linux, so full Xcode/iOS build and device test could not be executed.
- **To run tests of the portable core:** Swift 5.9+ on macOS/Linux, system SQLite dev headers + sqlite3 library. Tested on Swift 6.2.1/Linux.
- Target runtime iOS 17+; target device iOS 27.0.1 / recent compatible LiveContainer version.

## Build an unsigned IPA on Windows 11 via GitHub Actions

**No Mac needed:** Read [WINDOWS11_BUILD.md](WINDOWS11_BUILD.md) for exact Windows commands, GitHub repository setup, manual Xcode 27 workflow, artifact download and LiveContainer import. This is the recommended route for a Windows-only developer. The workflow files are `.github/workflows/build-ios-ipa.yml` (manual physical-device IPA) and `.github/workflows/core-tests.yml` (portable unit tests).

## Build an unsigned IPA on macOS (alternative)

Open `ReFindOne.xcodeproj` in Xcode, select `ReFindOne` target and a valid Apple development team if you plan to install directly. Build for a real device first and fix any device-SDK incompatibilities. Then create an IPA from the iPhoneOS `.app` output, e.g.:

```bash
xcodebuild -project ReFindOne.xcodeproj \
  -scheme ReFindOne -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/Derived \
  CODE_SIGNING_ALLOWED=NO build

mkdir -p build/ipa/Payload
cp -R build/Derived/Build/Products/Release-iphoneos/ReFindOne.app build/ipa/Payload/
(cd build/ipa && zip -qr ../ReFindOne-unsigned.ipa Payload)
```

This produces an **unsigned** IPA only if Xcode build succeeded. Import it using LiveContainer's **+** action and use its supported signing/JIT-less flow; success depends on your LiveContainer version/certificate. Do not rename a source ZIP to IPA. For sideloading with AltStore rather than LiveContainer, conventional signing is required.

For LiveContainer versions affected by iOS 27's SDK spoof changes, ensure **Spoof SDK Version is disabled** if crashes occur, and update to a release compatible with iOS 27. If file import fails, check LiveContainer's **Fix File Picker** option. These are debugging guidelines, not guaranteed fixes.

## Run unit tests

```bash
swift test
```

The SwiftPM `ReFindCore` target points to the **same Swift sources** used by the iOS app, so domain, database and backup tests are meaningful without iOS SDK. If you add a new platform-independent service, add its sources to `Package.swift` and corresponding tests.

## Architecture

The Windows-first build process is intentionally separate from app architecture. CI does not receive signing certificates or any on-device user data; code stays offline-first.


```
ReFindOne/
  App/            SwiftUI app entry / composition root
  Domain/         independent entity, URL policy
  Data/           repository protocol, SQLite actor, paths and attachment actor
  Services/       OCR (Vision), versioned backup codec
  Presentation/   @MainActor application state, command handlers
  Views/          library, add, details, settings
  Assets.xcassets app icon
Tests/            XCTest portable core
Modules/          portable sqlite3 modulemap for Linux tests
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the invariants, tradeoffs, threat model and ADRs. Read [MASTER_PROMPT.md](MASTER_PROMPT.md) for all future product/engineering requirements.

## Device acceptance test (not yet performed)

1. On iOS 27.0.1 under a compatible LiveContainer: launch, force-close, relaunch and verify data persistence.
2. Create a text note and link with `utm_source`, then search them in Cyrillic and English; verify cleaned link preserves required URL params.
3. Use PhotosPicker to import a screenshot with Russian text; search for a distinctive phrase and inspect OCR details.
4. Import a selectable-text PDF via Files, verify extraction; also import TXT.
5. Favorite, edit title/tags/note, remove; ensure search index refreshes and deletion removes the attachment.
6. Export full JSON, remove/reinstall to a **separate container**, restore, verify all entries/images; ensure restore does not duplicate IDs.
7. Check file picker with LiveContainer's `Fix File Picker` if necessary, accessibility and large font text, low-memory behavior.

## Known constraints / next engineering iteration

- **Not verified with Xcode/device.** Linux can parse iOS source, but cannot type-check Apple framework APIs or package genuine ARM64 iOS binaries.
- JSON export uses whole-buffer memory and is unencrypted. Later: incremental archive/ZIP + integrity manifest/encryption (without breaking v1 imports).
- Backup restore is add-only, may partially complete if one entry fails; later: stage and commit transactionally.
- The list currently caps at 250 records; pagination/search highlights and loading-state refinements are next.
- PhotosPicker may provide unexpected image formats; conversion/transcoding and quality controls need device tests.
- Scanned PDFs do not yet receive page OCR; no automatic cross-app sharing or clipboard surveillance.
- No semantic AI search, metadata crawlers, OCR reindex queue, background tasks, widgets or custom URL scheme in MVP.

## Sources

- Official [LiveContainer repository](https://github.com/LiveContainer/LiveContainer) and [releases](https://github.com/LiveContainer/LiveContainer/releases)
- Apple's [PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)
- Apple's [VNRecognizeTextRequest](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- Apple's [FileDocument](https://developer.apple.com/documentation/swiftui/filedocument)
