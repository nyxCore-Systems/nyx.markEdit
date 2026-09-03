<picture>
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/MarkEdit-app/MarkEdit/main/Icon.png" width="96">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/MarkEdit-app/MarkEdit/main/Icon-dark.png" width="96">
  <img src="./Icon.png" width="96">
</picture>

# MarkEdit

[![](https://img.shields.io/badge/Platform-macOS_15.0+-blue?color=007bff)](https://github.com/MarkEdit-app/MarkEdit?tab=readme-ov-file#installation) [![](https://github.com/MarkEdit-app/MarkEdit/actions/workflows/build-and-test.yml/badge.svg?branch=main)](https://github.com/MarkEdit-app/MarkEdit/actions/workflows/build-and-test.yml)

MarkEdit is a free and **open-source** Markdown editor, for macOS. It's just like _TextEdit_ on Mac but dedicated to `Markdown`.

No bloat. Markdown editing done right in a 4 MB app that flies through million-line files.

> [!TIP]
> Discover our other free and open-source apps at [libremac.github.io](https://libremac.github.io/).
>
> Follow our Mastodon account [@MarkEditApp](https://mastodon.social/@MarkEditApp) for the latest updates.

## Preview

![Screenshots 01](/Screenshots/01.png)

![Screenshots 02](/Screenshots/02.png)

![Screenshots 03](/Screenshots/03.png)

![Screenshots 04](/Screenshots/04.png)

## What makes MarkEdit different

- Privacy-focused: doesn't collect any user data
- Native: clean and intuitive, feels right at home on Mac
- Fast: edits 10 MB files easily
- Lightweight: installer size is about 4 MB
- Extensible: seamless integration with Shortcuts and AppleScript

MarkEdit strictly follows the [GFM specification](https://github.github.com/gfm/), with no proprietary syntax or invented features. Complex editing like multi-caret and code folding is built on [CodeMirror 6](https://codemirror.net/) for correctness and performance, consistently faster than most macOS editors. UI controls remain native to macOS in both aesthetics and behavior, including force-touch word lookup, inline predictions, and Writing Tools.

Customization is built around CSS, JavaScript, and [CodeMirror extensions](https://github.com/MarkEdit-app/MarkEdit-api). Official extensions include [MarkEdit-preview](https://github.com/MarkEdit-app/MarkEdit-preview) for a preview pane, [MarkEdit-theming](https://github.com/MarkEdit-app/MarkEdit-theming) for custom themes, and [MarkEdit-ai-writer](https://github.com/MarkEdit-app/MarkEdit-ai-writer) for Apple Intelligence on macOS Tahoe.

> To learn more, refer to [Philosophy](https://github.com/MarkEdit-app/MarkEdit/wiki/Philosophy), [Why MarkEdit](https://github.com/MarkEdit-app/MarkEdit/wiki/Why-MarkEdit) and [MarkEdit-api](https://github.com/MarkEdit-app/MarkEdit-api).

## Installation

Get `MarkEdit.dmg` from the <a href="https://github.com/MarkEdit-app/MarkEdit/releases/latest" target="_blank">latest release</a>, open it, and drag `MarkEdit.app` to `Applications`. Or install via [Homebrew](https://brew.sh/): `brew install --cask markedit`.

<img src="./Screenshots/install.png" width="540" alt="Install MarkEdit">

MarkEdit checks for updates automatically; you can also browse version history [here](https://github.com/MarkEdit-app/MarkEdit/releases).

For older macOS: [macos-12](https://github.com/MarkEdit-app/MarkEdit/releases/tag/macos-12), [macos-13](https://github.com/MarkEdit-app/MarkEdit/releases/tag/macos-13), [macos-14](https://github.com/MarkEdit-app/MarkEdit/releases/tag/macos-14).

## Build from source

Prebuilt releases are the easy path; build locally if you want to run unreleased changes or produce your own downloadable app bundle.

**Requirements:** macOS 15.0+, a full [Xcode](https://developer.apple.com/xcode/) 26 install (Command Line Tools alone are not enough), and Node.js 22.x.

The project has two halves that must be built **in order**: the CodeMirror editor first, then the Xcode app that bundles it.

```sh
# 0. One-time setup, if you have never used this Xcode install
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# 1. Build the CoreEditor web app
cd CoreEditor
corepack enable
yarn install
yarn build
cd ..

# 2. Build MarkEdit.app in Release configuration
xcodebuild build \
  -project MarkEdit.xcodeproj \
  -scheme MarkEditMac \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .derived-data \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# 3. Ad-hoc sign and package it as a downloadable zip
APP=".derived-data/Build/Products/Release/MarkEdit.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
codesign --force --deep --sign - "$APP"
xattr -cr "$APP"
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/MarkEdit-$VERSION.zip"
shasum -a 256 "dist/MarkEdit-$VERSION.zip"
```

This leaves the app at `.derived-data/Build/Products/Release/MarkEdit.app` and the shareable archive at `dist/MarkEdit-<version>.zip`. Both paths are git-ignored. Install it by unzipping and dragging `MarkEdit.app` to `Applications`, same as a release build.

> [!NOTE]
> A local build is **ad-hoc signed and not notarized**, so Gatekeeper will refuse it on first launch. Open it once via right-click → _Open_, or clear the quarantine flag with `xattr -dr com.apple.quarantine /Applications/MarkEdit.app`. Only do this for builds you produced yourself.

If `xcode-select -p` still points at `/Library/Developer/CommandLineTools`, prefix the `xcodebuild` calls with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` instead of switching it globally.

These are the same steps CI runs in [`.github/workflows/release.yml`](.github/workflows/release.yml); tagging a `v*` release runs them on a clean machine and publishes the zip to [Releases](https://github.com/MarkEdit-app/MarkEdit/releases).

### Running the tests

```sh
cd CoreEditor && yarn test && cd ..
xcodebuild test -project MarkEdit.xcodeproj -scheme MarkEditCoreTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild test -project MarkEdit.xcodeproj -scheme ModulesTests -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

## Using MarkEdit

Please refer to the [wiki page](https://github.com/MarkEdit-app/MarkEdit/wiki/Manual) for details. Check out [MarkEdit-skill](https://github.com/MarkEdit-app/MarkEdit-skill) if you're interested in managing MarkEdit with an AI agent.

## Why MarkEdit is free

MarkEdit is a tool we use every day and keep improving for ourselves. We ship it openly, hoping it's useful to others with the same needs.

## Contributing to MarkEdit

For bugs, [open an issue](https://github.com/MarkEdit-app/MarkEdit/issues/new) or [pull request](https://github.com/MarkEdit-app/MarkEdit/compare). For behavior changes, discuss first; MarkEdit is intentionally minimal ([why](https://github.com/MarkEdit-app/MarkEdit/wiki/Why-MarkEdit#feature-poor)).

Please refer to the [wiki page](https://github.com/MarkEdit-app/MarkEdit/wiki/Development) for development instructions.

## Acknowledgments

Built on [CodeMirror 6](https://codemirror.net/), with [ts-gyb](https://github.com/microsoft/ts-gyb) for code generation.
