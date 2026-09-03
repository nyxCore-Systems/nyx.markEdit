# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project

MarkEdit is a native macOS Markdown editor (macOS 15.0+). The actual editing surface is a CodeMirror 6 web app embedded in a `WKWebView`; the native shell is AppKit/SwiftUI. There is no iOS target, but the lower-level Swift packages (`MarkEditCore`, `MarkEditKit`) are kept platform-independent so they could compile on iOS.

## Build / Test / Lint

The project has two halves that must be built in order: the TypeScript editor first, then the Xcode app that bundles it.

**CoreEditor (TypeScript, run from `CoreEditor/`):**
- `yarn install` — uses Yarn 4 via Corepack (`corepack enable` first if needed). Node 22.x.
- `yarn dev` — Vite dev server for iterating on the editor in a browser.
- `yarn build` — runs `lint` + `codegen` + two Vite builds (full and `@light`). The Xcode build expects these outputs.
- `yarn lint` — ESLint over the CoreEditor sources.
- `yarn codegen` — runs ts-gyb to regenerate Swift bridge code (see "Codegen bridge" below). **Must be re-run whenever you change anything under `CoreEditor/src/bridge/` or `CoreEditor/src/config.ts`.**
- `yarn test` — Jest (jsdom). Single test: `yarn test path/to/file.test.ts` or `yarn test -t "test name"`.

**Xcode (run from repo root):**
- Build the app: `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Test core types: `xcodebuild test -project MarkEdit.xcodeproj -scheme MarkEditCoreTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Test Mac modules: `xcodebuild test -project MarkEdit.xcodeproj -scheme ModulesTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Single Swift test: append `-only-testing:<TestTarget>/<ClassName>/<testMethod>` to the `xcodebuild test` invocation.
- SwiftLint runs as a SwiftPM build-tool plugin (`MarkEditTools`) on every Swift target — lint errors will fail the Xcode build, not a separate command. Rules live in `.swiftlint.yml`.

**Local release build (downloadable app, run from repo root):**
- Needs a **full Xcode** install. If `xcode-select -p` still points at `/Library/Developer/CommandLineTools`, prefix the commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. A freshly installed Xcode also needs `sudo xcodebuild -license accept` once, otherwise every `xcodebuild` call fails with a license error.
- Build: `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -configuration Release -destination 'platform=macOS' -derivedDataPath .derived-data CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (CoreEditor must be built first).
- Package: ad-hoc sign with `codesign --force --deep --sign -`, clear attributes with `xattr -cr`, then `ditto -c -k --sequesterRsrc --keepParent <app> dist/MarkEdit-<version>.zip`.
- `.derived-data/` and `dist/` are git-ignored. The full copy-paste sequence is in the README's "Build from source" section; `.github/workflows/release.yml` runs the identical steps for tagged releases.
- **Never pass `-derivedDataPath build`** — `build/` is checked into git in this fork (~4,800 files, ~1 GB of stale DerivedData), so building there floods `git status`.

CI (`.github/workflows/build-and-test.yml`) runs all of the above on macOS 26 / Xcode 26, and `release.yml` builds, packages and publishes the zip for `v*` tags. Local overrides for signing/team go in `Build.xcconfig` via an ignored `Local.xcconfig`.

## Architecture

The editor is split across **four Swift packages** and **one TypeScript app**, communicating through an auto-generated bridge:

```
CoreEditor (TS, CodeMirror 6)  ──┐
                                  │  ts-gyb codegen (yarn codegen)
MarkEditCore     (Swift, shared types, encoding, config)
MarkEditKit      (Swift, WKWebView wrapper + bridge protocols)
MarkEditMac      (Swift, AppKit/SwiftUI app shell — macOS only)
  └── Modules    (Swift, isolated AppKit feature modules)
MarkEditTools    (SwiftLint binary plugin)
```

Two adjacent extension targets ship in the same Xcode project: `PreviewExtension/` (Quick Look using the `@light` build of CoreEditor) and `FinderExtension/`.

### Codegen bridge (the most important thing to understand)

The TypeScript ↔ Swift boundary is defined in TypeScript and *generated* into Swift. **Never edit the generated Swift directly.**

- **TS sources of truth:**
  - `CoreEditor/src/config.ts` — shared config types
  - `CoreEditor/src/bridge/native/*.ts` — interfaces the Swift side implements (called *from* the web)
  - `CoreEditor/src/bridge/web/*.ts` — interfaces the web side implements (called *from* Swift)
- **Generated Swift (do not edit):**
  - `MarkEditCore/Sources/EditorSharedTypes.swift` (and config types)
  - `MarkEditKit/Sources/Bridge/Native/Generated/`
  - `MarkEditKit/Sources/Bridge/Web/Generated/`
- Templates and config: `CoreEditor/src/@codegen/` (`config.json` + Mustache templates).
- Type aliases like `CodeGen_Int`, `CodeGen_UInt64`, `CodeGen_Self`, `CodeGen_Dict` map to Swift types — use them in TS interfaces instead of plain `number`.
- Runtime transport: TS `createNativeModule()` builds a `Proxy` that posts `{moduleName, methodName, parameters}` JSON over `window.webkit.messageHandlers.bridge` (`CoreEditor/src/bridge/nativeModule.ts`). Swift dispatches via `NativeBridge`/`NativeModule` protocols (`MarkEditKit/Sources/Bridge/Native/NativeModules.swift`).

Workflow when changing the bridge: edit the `.ts` interface → `yarn codegen` → implement the new method on the Swift `NativeBridge` (or the JS `WebModule`) → rebuild Xcode.

### CoreEditor internals

- Entry: `CoreEditor/src/core.ts` (full app) and `CoreEditor/src/@light/index.ts` (read-only build for `PreviewExtension`).
- Features live under `CoreEditor/src/modules/` (one folder per concern: `commands`, `completion`, `frontMatter`, `history`, `search`, `selection`, `tokenizer`, `writingTools`, …). The public extension API lives in `CoreEditor/src/api/`.
- Vite aliases `@codemirror/lang-markdown` and `@codemirror/language-data` to vendored copies under `src/@vendor/`. When touching language/highlighting code, prefer the vendored copies.
- Browserslist target is `safari >= 18` only — don't add transpilation/polyfills for older browsers.

### MarkEditMac structure

- `MarkEditMac/Sources/Editor/` — the document window. `EditorViewController` is split across many `+Feature.swift` extension files (Completion, Encoding, Menu, Pandoc, Preview, Statistics, TextFinder, Toolbar, …); follow that pattern when adding controller methods rather than growing the base class.
- `MarkEditMac/Sources/Main/` — app-level glue (`AppDocumentController`, `AppPreferences`, `AppHotKeys`, `AppWritingTools`, …).
- `MarkEditMac/Sources/{Settings,Panels,Shortcuts,Scripting,Updater}/` — Settings UI, custom panels, App Shortcuts/AppleScript surface, Sparkle.
- `MarkEditMac/Modules/` is a separate SwiftPM package. Each subfolder under `Sources/` (`AppKitControls`, `AppKitExtensions`, `DiffKit`, `FontPicker`, `Previewer`, `SettingsUI`, `Statistics`, `TextBundle`, `TextCompletion`, …) is its **own standalone target** — keep cross-module imports explicit.

### Concurrency

`MarkEditCore` and `MarkEditKit` enable `StrictConcurrency` as an experimental Swift feature. Most bridge protocols are `@MainActor`. New code on the Swift side should respect Sendable requirements rather than disabling them.

## Conventions

- MarkEdit is intentionally minimal — see the README and the project's "Why MarkEdit" wiki page. New user-facing features should be discussed in an issue first; bug fixes and internal cleanup don't need that.
- Strictly follows the GFM specification — no proprietary Markdown syntax.
- Customization is intended to flow through CSS / JS / CodeMirror extensions (the [MarkEdit-api](https://github.com/MarkEdit-app/MarkEdit-api) package), not by adding new built-in features.
- Version numbers live in `Build.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
