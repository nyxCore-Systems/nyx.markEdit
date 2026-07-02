# nyxCore Dual-Protocol Integration & Toolbar Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make markedit accept Persona Studio tokens (`nyx_pa_`) alongside MCP tokens, add an Aus/Projekt/Global/Alle knowledge-scope selector backed by the Axiom REST API, and redesign the floating AI toolbar (flip-to-fit, clamping, drag, editor-theme colors).

**Architecture:** Token-prefix routing in `AppAIService`: `nyx_pa_` → new `PersonaStudioClient` (REST, server-side LLM), `nyx_mt_`/`nyx_mp_` → existing `NyxCoreClient` (MCP + local Anthropic). Knowledge: `nyx_ax_` → new `AxiomClient` (REST `/api/v1/rag/search`), MCP token → legacy fallback (project scope only). Toolbar positioning becomes a pure, Jest-tested function.

**Tech Stack:** Swift (AppKit/SwiftUI, StrictConcurrency), TypeScript (CodeMirror 6), ts-gyb codegen bridge, Jest.

**Spec:** `docs/superpowers/specs/2026-07-02-nyxcore-dual-protocol-design.md`

## Global Constraints

- Branch: `feat/nyxcore-dual-protocol` (already created, stacked on `fix/nyxcore-persona-token-split`).
- New Swift files MUST be added to `MarkEdit.xcodeproj/project.pbxproj` in **4 places** (PBXBuildFile, PBXFileReference, group children, Sources phase). Continue the ID scheme: next free IDs are `9AB1000000000000000B000B` … (see Task 3/4 for exact entries).
- SwiftLint runs as a build plugin and FAILS the build. Known traps: use `case let .x(a, b)` (pattern_matching_keywords), use `Self(...)` in static references, do not add superfluous `swiftlint:disable`.
- Never edit generated Swift (`MarkEditKit/Sources/Bridge/Native/Generated/`). Bridge changes: edit `CoreEditor/src/bridge/native/ai.ts` → run `yarn codegen` in `CoreEditor/`.
- Any TS/CSS change requires `yarn build` in `CoreEditor/` **before** the Xcode build (dist is embedded at build time).
- Xcode build command (repo root):
  `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Jest: `cd CoreEditor && yarn test test/<file>.test.ts`. Node 26.x works despite the 22.x engine hint; `corepack enable` fails with EACCES but Yarn 4.9.2 works anyway.
- All keychain accounts stay unchanged: `nyxcore.persona-token`, `nyxcore.token`, `anthropic.api-key`.

---

### Task 1: Pure toolbar-positioning function (TDD)

**Files:**
- Create: `CoreEditor/src/modules/ai/positioning.ts`
- Test: `CoreEditor/test/aiToolbarPositioning.test.ts`

**Interfaces:**
- Consumes: nothing (pure module, no imports).
- Produces: `computeToolbarPosition(args: {selStart: Rect; selEnd: Rect; toolbar: Size; editor: Rect; wasFlipped: boolean}): {top: number; left: number; flipped: boolean}` and `clampPosition(pos: Point, toolbar: Size, editor: {width: number; height: number}): Point`, `toolbarGap = 8`. Task 2 imports all three. `Rect = {top; bottom; left; right}`, `Size = {width; height}`, `Point = {top; left}` — all viewport/editor-relative pixel numbers.

- [ ] **Step 1: Write the failing test**

Create `CoreEditor/test/aiToolbarPositioning.test.ts`:

```ts
import { clampPosition, computeToolbarPosition, toolbarGap } from '../src/modules/ai/positioning';

const editor = { top: 0, bottom: 600, left: 0, right: 800 };
const toolbar = { width: 400, height: 32 };
const line = (top: number, left = 100) => ({ top, bottom: top + 20, left, right: left + 50 });

describe('computeToolbarPosition', () => {
  test('places the toolbar above the selection when there is room', () => {
    const result = computeToolbarPosition({
      selStart: line(300), selEnd: line(340), toolbar, editor, wasFlipped: false,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(300 - toolbar.height - toolbarGap);
    expect(result.left).toBe(100);
  });

  test('flips below the selection end when there is no room above', () => {
    const result = computeToolbarPosition({
      selStart: line(10), selEnd: line(30), toolbar, editor, wasFlipped: false,
    });
    expect(result.flipped).toBe(true);
    expect(result.top).toBe(50 + toolbarGap); // selEnd.bottom (30 + 20) + gap
  });

  test('stays flipped while below still fits (sticky flag)', () => {
    const result = computeToolbarPosition({
      selStart: line(300), selEnd: line(340), toolbar, editor, wasFlipped: true,
    });
    expect(result.flipped).toBe(true);
    expect(result.top).toBe(360 + toolbarGap);
  });

  test('un-flips when below no longer fits', () => {
    const result = computeToolbarPosition({
      selStart: line(500), selEnd: line(590), toolbar, editor, wasFlipped: true,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(500 - toolbar.height - toolbarGap);
  });

  test('clamps to the right edge', () => {
    const result = computeToolbarPosition({
      selStart: line(300, 700), selEnd: line(340, 700), toolbar, editor, wasFlipped: false,
    });
    expect(result.left).toBe(800 - toolbar.width); // 400
  });

  test('clamps within the editor when neither side fits', () => {
    const smallEditor = { top: 0, bottom: 40, left: 0, right: 800 };
    const result = computeToolbarPosition({
      selStart: line(5), selEnd: line(15), toolbar, editor: smallEditor, wasFlipped: false,
    });
    expect(result.flipped).toBe(false);
    expect(result.top).toBe(0); // negative above-position clamps to the top edge
  });
});

describe('clampPosition', () => {
  test('clamps negative and overflowing coordinates', () => {
    expect(clampPosition({ top: -10, left: 900 }, toolbar, { width: 800, height: 600 }))
      .toEqual({ top: 0, left: 400 });
  });

  test('pins to 0 when the toolbar is larger than the editor', () => {
    expect(clampPosition({ top: 50, left: 50 }, { width: 900, height: 700 }, { width: 800, height: 600 }))
      .toEqual({ top: 0, left: 0 });
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn test test/aiToolbarPositioning.test.ts`
Expected: FAIL — `Cannot find module '../src/modules/ai/positioning'`.

- [ ] **Step 3: Write the implementation**

Create `CoreEditor/src/modules/ai/positioning.ts`:

```ts
export interface Rect { top: number; bottom: number; left: number; right: number }
export interface Size { width: number; height: number }
export interface Point { top: number; left: number }

/** Gap between the toolbar and the selection line, in pixels. */
export const toolbarGap = 8;

/**
 * Clamp a candidate position so the toolbar stays fully inside the editor.
 */
export function clampPosition(pos: Point, toolbar: Size, editor: Size): Point {
  const maxLeft = Math.max(0, editor.width - toolbar.width);
  const maxTop = Math.max(0, editor.height - toolbar.height);
  return {
    top: Math.min(Math.max(pos.top, 0), maxTop),
    left: Math.min(Math.max(pos.left, 0), maxLeft),
  };
}

/**
 * Compute where the floating AI toolbar should sit relative to the editor.
 *
 * Prefers sitting above the selection start; flips below the selection end
 * when there is not enough room above. The flip is sticky (wasFlipped) so the
 * toolbar does not flutter between positions while the selection grows.
 */
export function computeToolbarPosition(args: {
  selStart: Rect;
  selEnd: Rect;
  toolbar: Size;
  editor: Rect;
  wasFlipped: boolean;
}): { top: number; left: number; flipped: boolean } {
  const { selStart, selEnd, toolbar, editor, wasFlipped } = args;
  const editorSize = { width: editor.right - editor.left, height: editor.bottom - editor.top };

  const aboveTop = selStart.top - editor.top - toolbar.height - toolbarGap;
  const belowTop = selEnd.bottom - editor.top + toolbarGap;
  const fitsAbove = aboveTop >= 0;
  const fitsBelow = belowTop + toolbar.height <= editorSize.height;

  const flipped = wasFlipped ? fitsBelow : (!fitsAbove && fitsBelow);
  const top = flipped ? belowTop : aboveTop;
  const left = selStart.left - editor.left;
  return { ...clampPosition({ top, left }, toolbar, editorSize), flipped };
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn test test/aiToolbarPositioning.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add CoreEditor/src/modules/ai/positioning.ts CoreEditor/test/aiToolbarPositioning.test.ts
git commit -m "feat(toolbar): pure flip-to-fit positioning with tests"
```

---

### Task 2: Toolbar positioning, theming, drag (TS/CSS)

**Files:**
- Modify: `CoreEditor/src/modules/ai/index.ts`
- Modify: `CoreEditor/src/modules/ai/index.css`

**Interfaces:**
- Consumes: `computeToolbarPosition`, `clampPosition`, `toolbarGap` from Task 1; `globalState` from `CoreEditor/src/common/store` (`globalState.colors?: EditorColors` with string fields `background`, `text`, `accent`).
- Produces: no new exports; behavior only. The bridge API is untouched in this task (still `useKnowledge: boolean`).

- [ ] **Step 1: Update imports and class fields in `index.ts`**

At the top of `CoreEditor/src/modules/ai/index.ts`, extend the imports:

```ts
import { EditorView, ViewPlugin, ViewUpdate } from '@codemirror/view';
import { EditorSelection } from '@codemirror/state';
import { AIAction, AIPersona, AIPersonaListResponse } from '../../bridge/native/ai';
import { globalState } from '../../common/store';
import { clampPosition, computeToolbarPosition } from './positioning';
import './index.css';
```

Add two fields to the plugin class (below `private readonly boundOnKeyDown…`):

```ts
    private manualPosition: { top: number; left: number } | undefined;
    private wasFlipped = false;
```

- [ ] **Step 2: Add the drag grip in `build()`**

At the very start of `build()` (before `addAction(activeLabels.improve, …)`), insert:

```ts
      const grip = document.createElement('div');
      grip.className = 'cm-md-aiGrip';
      grip.textContent = '⠿';
      grip.title = 'Drag to move';
      grip.addEventListener('mousedown', event => this.startDrag(event));
      this.dom.appendChild(grip);
```

Add the drag handler as a new private method (below `onKeyDown`):

```ts
    private startDrag(event: MouseEvent) {
      event.preventDefault();
      event.stopPropagation();

      const toolbarRect = this.dom.getBoundingClientRect();
      const editorRect = this.view.dom.getBoundingClientRect();
      const origin = {
        top: toolbarRect.top - editorRect.top,
        left: toolbarRect.left - editorRect.left,
      };
      const startX = event.clientX;
      const startY = event.clientY;

      const onMove = (move: MouseEvent) => {
        const rect = this.view.dom.getBoundingClientRect();
        const pos = clampPosition(
          { top: origin.top + (move.clientY - startY), left: origin.left + (move.clientX - startX) },
          { width: toolbarRect.width, height: toolbarRect.height },
          { width: rect.width, height: rect.height },
        );
        this.manualPosition = pos;
        this.dom.style.top = `${pos.top}px`;
        this.dom.style.left = `${pos.left}px`;
      };

      const onUp = () => {
        document.removeEventListener('mousemove', onMove);
        document.removeEventListener('mouseup', onUp);
      };

      document.addEventListener('mousemove', onMove);
      document.addEventListener('mouseup', onUp);
    }
```

- [ ] **Step 3: Replace `reposition()` and extend `hide()`**

Replace the entire `reposition()` method body with:

```ts
    private reposition() {
      // Don't compete with macOS Writing Tools.
      if (isWritingToolsActive()) {
        this.hide();
        return;
      }

      const sel = this.view.state.selection.main;
      if (sel.empty || this.state.busy) {
        if (!this.state.busy) {
          this.hide();
        }
        return;
      }

      const startPos = Math.min(sel.from, sel.to);
      const endPos = Math.max(sel.from, sel.to);
      const selStart = this.view.coordsAtPos(startPos);
      const selEnd = this.view.coordsAtPos(endPos);
      if (selStart === null || selEnd === null) {
        this.hide();
        return;
      }

      this.applyTheme();
      this.dom.style.position = 'absolute';
      this.dom.style.zIndex = '550';
      this.dom.setAttribute('aria-hidden', 'false');

      const editorRect = this.view.dom.getBoundingClientRect();
      const toolbarRect = this.dom.getBoundingClientRect();
      const toolbarSize = { width: toolbarRect.width, height: toolbarRect.height };

      if (this.manualPosition !== undefined) {
        // The user dragged the toolbar — keep their position, re-clamped.
        const pos = clampPosition(this.manualPosition, toolbarSize, {
          width: editorRect.width, height: editorRect.height,
        });
        this.dom.style.top = `${pos.top}px`;
        this.dom.style.left = `${pos.left}px`;
      } else {
        const placement = computeToolbarPosition({
          selStart, selEnd, toolbar: toolbarSize, editor: editorRect, wasFlipped: this.wasFlipped,
        });
        this.wasFlipped = placement.flipped;
        this.dom.style.top = `${placement.top}px`;
        this.dom.style.left = `${placement.left}px`;
      }

      // Reset transient error after the user moves on.
      if (isNonEmpty(this.state.errorMessage)) {
        this.clearStatus();
      }
    }

    /** Sync toolbar colors with the active editor theme (not just OS appearance). */
    private applyTheme() {
      const colors = globalState.colors;
      if (colors === undefined) {
        return; // CSS falls back to system colors.
      }
      this.dom.style.setProperty('--md-ai-bg', colors.background);
      this.dom.style.setProperty('--md-ai-fg', colors.text);
      this.dom.style.setProperty('--md-ai-accent', colors.accent);
    }
```

In `hide()`, add resets at the end:

```ts
    private hide() {
      this.dom.setAttribute('aria-hidden', 'true');
      this.toneList.style.display = 'none';
      this.personaList.style.display = 'none';
      this.clearStatus();
      this.manualPosition = undefined;
      this.wasFlipped = false;
    }
```

- [ ] **Step 4: Rework `index.css` for theme variables + grip**

Replace the full contents of `CoreEditor/src/modules/ai/index.css` with:

```css
.cm-md-aiToolbar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 4px;
  background: color-mix(in oklab, var(--md-ai-bg, Canvas) 92%, var(--md-ai-fg, CanvasText) 8%);
  color: var(--md-ai-fg, CanvasText);
  border: 1px solid color-mix(in oklab, var(--md-ai-fg, CanvasText) 15%, transparent);
  border-radius: 8px;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.18);
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 12px;
  user-select: none;
  pointer-events: auto;
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
}

.cm-md-aiToolbar .cm-md-aiGrip {
  cursor: grab;
  padding: 4px 2px 4px 5px;
  font-size: 10px;
  opacity: 0.45;
  user-select: none;
}

.cm-md-aiToolbar .cm-md-aiGrip:active {
  cursor: grabbing;
}

.cm-md-aiToolbar button {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 9px;
  background: transparent;
  border: 0;
  border-radius: 5px;
  color: inherit;
  font: inherit;
  cursor: pointer;
  white-space: nowrap;
}

.cm-md-aiToolbar button:hover:not(:disabled) {
  background: color-mix(in oklab, var(--md-ai-fg, CanvasText) 12%, transparent);
}

.cm-md-aiToolbar button:disabled {
  opacity: 0.4;
  cursor: progress;
}

.cm-md-aiToolbar .cm-md-aiSeparator {
  width: 1px;
  height: 16px;
  background: color-mix(in oklab, var(--md-ai-fg, CanvasText) 18%, transparent);
  margin: 0 2px;
}

.cm-md-aiToolbar .cm-md-aiToneMenu,
.cm-md-aiToolbar .cm-md-aiPersonaMenu {
  position: relative;
}

.cm-md-aiToneList,
.cm-md-aiPersonaList {
  position: absolute;
  top: 100%;
  left: 0;
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 4px;
  background-color: color-mix(in oklab, var(--md-ai-bg, Canvas) 92%, var(--md-ai-fg, CanvasText) 8%);
  background-image: linear-gradient(var(--md-ai-bg, Canvas), var(--md-ai-bg, Canvas));
  border: 1px solid color-mix(in oklab, var(--md-ai-fg, CanvasText) 15%, transparent);
  border-radius: 8px;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.18);
  -webkit-backdrop-filter: blur(20px);
  backdrop-filter: blur(20px);
  min-width: 140px;
  z-index: 1;
}

.cm-md-aiToneList button,
.cm-md-aiPersonaList button {
  justify-content: flex-start;
  width: 100%;
}

.cm-md-aiPersonaList {
  min-width: 200px;
  max-height: 320px;
  overflow-y: auto;
}

.cm-md-aiPersonaList .cm-md-aiScopeRow {
  display: flex;
  flex-direction: row;
  gap: 2px;
  border-bottom: 1px solid color-mix(in oklab, var(--md-ai-fg, CanvasText) 15%, transparent);
  margin-bottom: 4px;
  padding-bottom: 4px;
}

.cm-md-aiPersonaList .cm-md-aiScopeRow button {
  width: auto;
  padding: 3px 7px;
  font-size: 11px;
}

.cm-md-aiPersonaList .cm-md-aiScopeRow button.cm-md-aiScopeSelected {
  background: color-mix(in oklab, var(--md-ai-accent, Highlight) 25%, transparent);
}

.cm-md-aiPersonaList .cm-md-aiPersonaGroup {
  padding: 5px 9px 2px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.4px;
  opacity: 0.55;
}

.cm-md-aiPersonaList .cm-md-aiPersonaInfo {
  padding: 4px 9px;
  font-style: italic;
  opacity: 0.75;
}

.cm-md-aiToolbar .cm-md-aiStatus {
  padding: 0 6px;
  font-style: italic;
  opacity: 0.75;
}

.cm-md-aiToolbar .cm-md-aiError {
  padding: 0 6px;
  color: #d4380d;
}

@media (prefers-color-scheme: dark) {
  .cm-md-aiToolbar .cm-md-aiError {
    color: #ff7875;
  }
}

.cm-md-aiToolbar[aria-hidden="true"] {
  display: none !important;
}
```

Note: `.cm-md-aiScopeRow`, `.cm-md-aiScopeSelected`, and `.cm-md-aiPersonaGroup` are used by Task 6; adding the styles now keeps this file change atomic. The old `.cm-md-aiKnowledgeToggle` rule is intentionally dropped (Task 6 removes the element).

- [ ] **Step 5: Build + lint + full test suite**

Run: `cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn build && yarn test`
Expected: build succeeds (lint + codegen + two Vite builds), all Jest tests pass.
Note: `yarn test` may warn about unused `.cm-md-aiKnowledgeToggle` — there is no such check; expect plain PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add CoreEditor/src/modules/ai/index.ts CoreEditor/src/modules/ai/index.css
git commit -m "feat(toolbar): flip-to-fit positioning, drag grip, editor-theme colors"
```

---

### Task 3: `PersonaStudioClient.swift` (REST client) + pbxproj

**Files:**
- Create: `MarkEditMac/Sources/Editor/PersonaStudioClient.swift`
- Modify: `MarkEdit.xcodeproj/project.pbxproj` (4 places)

**Interfaces:**
- Consumes: `AppPreferences.NyxCore.enabled`, `.personaToken`, `.personaBaseURL` (all exist).
- Produces (used by Task 5):
  - `PersonaStudioClient.tokenPrefix: String` (= `"nyx_pa_"`)
  - `PersonaStudioClient.current() -> PersonaStudioClient?` (`@MainActor`)
  - `func listPersonas() async throws -> [StudioPersona]` where `StudioPersona = {id, name, description: String?, circleID, circleName}`
  - `func chat(personaID: String, circleID: String?, system: String, user: String, maxTokens: Int) async throws -> String`

- [ ] **Step 1: Create the client**

Create `MarkEditMac/Sources/Editor/PersonaStudioClient.swift`:

```swift
//
//  PersonaStudioClient.swift
//  MarkEditMac
//
//  REST client for nyx Persona Studio (nyx_pa_ tokens). Persona Studio does
//  NOT speak the MCP protocol: personas are listed via GET /api/v1/persona/list
//  and rewrites run server-side via POST /api/v1/persona/chat (the LLM call is
//  billed in nyxCore; no local Anthropic key is involved).
//

import Foundation

struct StudioPersona: Sendable {
  let id: String
  let name: String
  let description: String?
  let circleID: String
  let circleName: String
}

struct PersonaStudioClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case api(String, String)
    case decoding(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid Persona Studio endpoint URL."
      case let .http(code, detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Persona Studio request failed: HTTP \(code)" : "Persona Studio request failed: \(trimmed)"
      case let .api(code, message):
        return Self.friendlyMessage(code: code, message: message)
      case .decoding(let message):
        return "Could not parse Persona Studio response: \(message)"
      }
    }

    static func friendlyMessage(code: String, message: String) -> String {
      switch code {
      case "UNAUTHORIZED":
        return "Persona Studio token was rejected. Check the token in Settings → AI."
      case "BUDGET_EXCEEDED":
        return "Persona Studio monthly budget exceeded."
      case "FORBIDDEN":
        return "This token is not allowed to use that persona or circle."
      case "NOT_FOUND":
        return "Persona or circle not found — is the circle published?"
      case "RATE_LIMITED":
        return "Persona Studio rate limit reached. Try again in a minute."
      default:
        return "Persona Studio error: \(message)"
      }
    }
  }

  static let tokenPrefix = "nyx_pa_"

  let origin: String
  let token: String

  /// Client for Persona Studio, or nil when nyxCore is disabled or the persona
  /// token is not a Persona Studio (nyx_pa_) token.
  @MainActor
  static func current() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.personaToken ?? "").trimmingCharacters(in: .whitespaces)
    guard token.hasPrefix(tokenPrefix) else {
      return nil
    }

    guard let origin = origin(from: AppPreferences.NyxCore.personaBaseURL) else {
      return nil
    }

    return Self(origin: origin, token: token)
  }

  /// "https://nyxcore.cloud/api/v1/mcp" → "https://nyxcore.cloud". Users keep
  /// their existing endpoint setting; REST paths are derived from the origin.
  static func origin(from urlString: String) -> String? {
    guard let url = URL(string: urlString), let scheme = url.scheme, let host = url.host else {
      return nil
    }

    let port = url.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
  }

  // MARK: - Endpoints

  func listPersonas() async throws -> [StudioPersona] {
    struct Member: Decodable {
      let id: String
      let name: String
      let description: String?
    }
    struct Circle: Decodable {
      let id: String
      let name: String
      let personas: [Member]
    }
    struct Payload: Decodable {
      let circles: [Circle]?
    }

    let payload: Payload = try await send(path: "/api/v1/persona/list", method: "GET", body: nil)
    return (payload.circles ?? []).flatMap { circle in
      circle.personas.map { member in
        StudioPersona(
          id: member.id,
          name: member.name,
          description: member.description,
          circleID: circle.id,
          circleName: circle.name
        )
      }
    }
  }

  /// One-shot persona rewrite. The persona's own system prompt is built
  /// server-side; our editor contract travels as a supplementary system message.
  func chat(personaID: String, circleID: String?, system: String, user: String, maxTokens: Int) async throws -> String {
    struct Payload: Decodable {
      let content: String?
    }

    var body: [String: Any] = [
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user],
      ],
      "personaId": personaID,
      "maxTokens": min(8192, max(1, maxTokens)),
      "useSkills": true,
    ]
    if let circleID {
      body["circleId"] = circleID
    }

    let payload: Payload = try await send(path: "/api/v1/persona/chat", method: "POST", body: body)
    guard let content = payload.content, !content.isEmpty else {
      throw ClientError.decoding("Empty chat content")
    }

    return content
  }

  // MARK: - Transport

  private func send<T: Decodable>(path: String, method: String, body: [String: Any]?) async throws -> T {
    guard let url = URL(string: "\(origin)\(path)") else {
      throw ClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.http(-1, "Invalid response")
    }

    // The API wraps errors as { ok: false, error: { code, message } } with a
    // matching non-2xx status; prefer the structured message when present.
    struct APIEnvelopeError: Decodable {
      struct Inner: Decodable {
        let code: String
        let message: String
      }
      let error: Inner?
    }

    guard (200...299).contains(http.statusCode) else {
      if let envelope = try? JSONDecoder().decode(APIEnvelopeError.self, from: data), let inner = envelope.error {
        throw ClientError.api(inner.code, inner.message)
      }
      throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    do {
      return try JSONDecoder().decode(T.self, from: data)
    } catch {
      throw ClientError.decoding(error.localizedDescription)
    }
  }
}
```

- [ ] **Step 2: Register the file in `project.pbxproj` (4 places)**

In `MarkEdit.xcodeproj/project.pbxproj`:

1. PBXBuildFile section — after the line containing `9AB1000000000000000B000A /* NyxCorePromptComposer.swift in Sources */` (line ~35), add:
```
		9AB1000000000000000B000C /* PersonaStudioClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9AB1000000000000000B000B /* PersonaStudioClient.swift */; };
```
2. PBXFileReference section — after the line containing `9AB1000000000000000B0009 /* NyxCorePromptComposer.swift */ = {isa = PBXFileReference; …` (line ~241), add:
```
		9AB1000000000000000B000B /* PersonaStudioClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PersonaStudioClient.swift; sourceTree = "<group>"; };
```
3. Editor group children — after `9AB1000000000000000B0009 /* NyxCorePromptComposer.swift */,` (line ~395), add:
```
				9AB1000000000000000B000B /* PersonaStudioClient.swift */,
```
4. Sources build phase — after `9AB1000000000000000B000A /* NyxCorePromptComposer.swift in Sources */,` (line ~869), add:
```
				9AB1000000000000000B000C /* PersonaStudioClient.swift in Sources */,
```

- [ ] **Step 3: Build to verify it compiles (incl. SwiftLint)**

Run (repo root): `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add MarkEditMac/Sources/Editor/PersonaStudioClient.swift MarkEdit.xcodeproj/project.pbxproj
git commit -m "feat(persona-studio): REST client for nyx_pa_ tokens (list + chat)"
```

---

### Task 4: `AxiomClient.swift` + new preferences + pbxproj

**Files:**
- Create: `MarkEditMac/Sources/Editor/AxiomClient.swift`
- Modify: `MarkEditMac/Sources/Main/AppPreferences.swift` (NyxCore enum, lines 274–307)
- Modify: `MarkEdit.xcodeproj/project.pbxproj` (4 places)

**Interfaces:**
- Consumes: `AppPreferences.NyxCore.enabled`, `.knowledgeToken`, `.knowledgeBaseURL`, `.projectID`, plus the two new preferences added here. `PersonaStudioClient.origin(from:)` from Task 3.
- Produces (used by Task 5):
  - `AxiomClient.tokenPrefix: String` (= `"nyx_ax_"`)
  - `AxiomClient.current() -> AxiomClient?` (`@MainActor`)
  - `func search(query: String, scope: String, limit: Int) async throws -> [String]` — scope is `"project" | "global" | "all"`; snippets formatted `[filename › heading]\ncontent`.
  - New prefs: `AppPreferences.NyxCore.collectionID: String` (default `""`), `AppPreferences.NyxCore.knowledgeScope: String` (default `""`, empty = migrate from `useKnowledge`).

- [ ] **Step 1: Add the two preferences**

In `MarkEditMac/Sources/Main/AppPreferences.swift`, inside `enum NyxCore`, after the `projectID` property (line ~298), add:

```swift
    /// Standalone Axiom collection used by the "global" knowledge scope. Optional.
    @Storage(key: "nyxcore.collection-id", defaultValue: "")
    static var collectionID: String

    /// Default knowledge scope: "off" | "project" | "global" | "all".
    /// Empty means "not set yet" — callers migrate from the legacy useKnowledge flag.
    @Storage(key: "nyxcore.knowledge-scope", defaultValue: "")
    static var knowledgeScope: String
```

Keep `useKnowledge` — it is still read for migration.

- [ ] **Step 2: Create the client**

Create `MarkEditMac/Sources/Editor/AxiomClient.swift`:

```swift
//
//  AxiomClient.swift
//  MarkEditMac
//
//  REST client for the nyxCore Axiom RAG search API (nyx_ax_ tokens).
//  Scope mapping: "project" → projectId, "global" → collectionId (standalone
//  collection), "all" → neither (tenant-wide; requires a tenant-wide token —
//  project-scoped tokens are pinned server-side and degrade to their project).
//

import Foundation

struct AxiomClient: Sendable {
  enum ClientError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case missingProject
    case missingCollection
    case decoding(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "Invalid Axiom endpoint URL."
      case let .http(code, detail):
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Axiom request failed: HTTP \(code)" : "Axiom request failed: \(trimmed)"
      case .missingProject:
        return "Set a Project ID in Settings → AI to use project-scoped knowledge."
      case .missingCollection:
        return "Set a Collection ID in Settings → AI to use global knowledge."
      case .decoding(let message):
        return "Could not parse Axiom response: \(message)"
      }
    }
  }

  static let tokenPrefix = "nyx_ax_"

  let origin: String
  let token: String
  let projectID: String?
  let collectionID: String?

  /// Client for Axiom knowledge search, or nil when nyxCore is disabled or the
  /// knowledge token is not an Axiom (nyx_ax_) token.
  @MainActor
  static func current() -> Self? {
    guard AppPreferences.NyxCore.enabled else {
      return nil
    }

    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespaces)
    guard token.hasPrefix(tokenPrefix) else {
      return nil
    }

    guard let origin = PersonaStudioClient.origin(from: AppPreferences.NyxCore.knowledgeBaseURL) else {
      return nil
    }

    let project = AppPreferences.NyxCore.projectID.trimmingCharacters(in: .whitespaces)
    let collection = AppPreferences.NyxCore.collectionID.trimmingCharacters(in: .whitespaces)
    return Self(
      origin: origin,
      token: token,
      projectID: project.isEmpty ? nil : project,
      collectionID: collection.isEmpty ? nil : collection
    )
  }

  /// Knowledge snippet texts, most relevant first, formatted "[filename › heading]\ncontent".
  func search(query: String, scope: String, limit: Int) async throws -> [String] {
    struct Hit: Decodable {
      let content: String?
      let heading: String?
      let filename: String?
    }
    struct Payload: Decodable {
      let results: [Hit]?
    }

    var body: [String: Any] = ["query": query, "limit": limit]
    switch scope {
    case "project":
      guard let projectID else {
        throw ClientError.missingProject
      }
      body["projectId"] = projectID
    case "global":
      guard let collectionID else {
        throw ClientError.missingCollection
      }
      body["collectionId"] = collectionID
    default:
      break // "all": tenant-wide search, no filter
    }

    guard let url = URL(string: "\(origin)/api/v1/rag/search") else {
      throw ClientError.invalidURL
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw ClientError.http(-1, "Invalid response")
    }

    guard (200...299).contains(http.statusCode) else {
      throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    let payload: Payload
    do {
      payload = try JSONDecoder().decode(Payload.self, from: data)
    } catch {
      throw ClientError.decoding(error.localizedDescription)
    }

    return (payload.results ?? []).compactMap { hit in
      guard let text = hit.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
        return nil
      }

      let label = [hit.filename, hit.heading]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " › ")

      return label.isEmpty ? text : "[\(label)]\n\(text)"
    }
  }
}
```

- [ ] **Step 3: Register in `project.pbxproj` (4 places)**

Same 4 sections as Task 3, directly after the `PersonaStudioClient.swift` lines added there:

1. PBXBuildFile:
```
		9AB1000000000000000B000E /* AxiomClient.swift in Sources */ = {isa = PBXBuildFile; fileRef = 9AB1000000000000000B000D /* AxiomClient.swift */; };
```
2. PBXFileReference:
```
		9AB1000000000000000B000D /* AxiomClient.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AxiomClient.swift; sourceTree = "<group>"; };
```
3. Editor group children:
```
				9AB1000000000000000B000D /* AxiomClient.swift */,
```
4. Sources build phase:
```
				9AB1000000000000000B000E /* AxiomClient.swift in Sources */,
```

- [ ] **Step 4: Build**

Run (repo root): `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add MarkEditMac/Sources/Editor/AxiomClient.swift MarkEditMac/Sources/Main/AppPreferences.swift MarkEdit.xcodeproj/project.pbxproj
git commit -m "feat(axiom): REST search client with project/global/all scopes"
```

---

### Task 5: Bridge contract change + dual-protocol routing in `AppAIService`

**Files:**
- Modify: `CoreEditor/src/bridge/native/ai.ts`
- Regenerate: `MarkEditKit/Sources/Bridge/Native/Generated/NativeModuleAI.swift` (via `yarn codegen` — never by hand)
- Modify: `MarkEditKit/Sources/Bridge/Native/Modules/EditorModuleAI.swift`
- Modify: `MarkEditMac/Sources/Editor/AppAIService.swift`

**Interfaces:**
- Consumes: `PersonaStudioClient` (Task 3), `AxiomClient` (Task 4), `NyxCoreClient` + `NyxCorePromptComposer` (existing).
- Produces (used by Task 6/7):
  - TS: `AIPersona` gains `source?: string; circleId?: string; circleName?: string`. New `AIKnowledgeConfig = { availableScopes: string[]; defaultScope: string }`. `NativeModuleAI.getKnowledgeConfig(): Promise<string>`; `refactorWithPersona` args become `{ personaID; personaName; circleID?: string; selection; context?; knowledgeScope: string }`.
  - Swift: `AIService` protocol gains `func knowledgeConfig() async -> AIKnowledgeConfig`; `refactorWithPersona(personaID:personaName:circleID:selection:context:knowledgeScope:)`. `AppAIService.testKnowledge() async -> (success: Bool, message: String)` for Task 7.

- [ ] **Step 1: Update the TS bridge definition**

In `CoreEditor/src/bridge/native/ai.ts`, replace the `AIPersona` interface and the `NativeModuleAI` interface (keep `AIAction`, `AIRefactorResponse`, `AIPersonaListResponse` as-is):

```ts
export interface AIPersona {
  id: string;
  name: string;
  description?: string;
  // 'mcp' (global personas via MCP token) or 'studio' (Persona Studio circles).
  source?: string;
  circleId?: string;
  circleName?: string;
}

export interface AIKnowledgeConfig {
  // Subset of ['off', 'project', 'global', 'all'], always contains 'off'.
  availableScopes?: string[];
  defaultScope?: string;
  error?: string;
}

/**
 * @shouldExport true
 * @invokePath ai
 * @bridgeName NativeBridgeAI
 */
export interface NativeModuleAI extends NativeModule {
  isConfigured(): Promise<boolean>;
  refactor(args: { action: AIAction; selection: string; context?: string }): Promise<string>;

  // nyxCore: personas and knowledge-grounded rewriting.
  //
  // All return JSON-encoded strings (parsed on the web side), matching the
  // convention used by refactor. listPersonas yields an AIPersonaListResponse,
  // getKnowledgeConfig yields an AIKnowledgeConfig, refactorWithPersona yields
  // an AIRefactorResponse.
  listPersonas(): Promise<string>;
  getKnowledgeConfig(): Promise<string>;
  refactorWithPersona(args: {
    personaID: string;
    personaName: string;
    circleID?: string;
    selection: string;
    context?: string;
    knowledgeScope: string;
  }): Promise<string>;
}
```

- [ ] **Step 2: Regenerate the bridge**

Run: `cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn codegen`
Expected: exits 0; `git status` shows `MarkEditKit/Sources/Bridge/Native/Generated/NativeModuleAI.swift` modified (new `getKnowledgeConfig`, changed `refactorWithPersona` parameters).

- [ ] **Step 3: Update `EditorModuleAI.swift`**

In `MarkEditKit/Sources/Bridge/Native/Modules/EditorModuleAI.swift`:

Replace the `AIPersona` struct with:

```swift
public struct AIPersona: Codable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var description: String?
  public var source: String?
  public var circleId: String?
  public var circleName: String?

  public init(
    id: String,
    name: String,
    description: String? = nil,
    source: String? = nil,
    circleId: String? = nil,
    circleName: String? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.source = source
    self.circleId = circleId
    self.circleName = circleName
  }
}
```

Below `AIPersonaListResponse`, add:

```swift
public struct AIKnowledgeConfig: Codable, Equatable, Sendable {
  public var availableScopes: [String]
  public var defaultScope: String

  public init(availableScopes: [String], defaultScope: String) {
    self.availableScopes = availableScopes
    self.defaultScope = defaultScope
  }
}
```

Replace the `AIService` protocol and the two persona methods of `EditorModuleAI` with:

```swift
@MainActor
public protocol AIService: AnyObject {
  func isConfigured() async -> Bool
  func refactor(action: AIAction, selection: String, context: String?) async -> AIRefactorResponse
  func listPersonas() async -> AIPersonaListResponse
  func knowledgeConfig() async -> AIKnowledgeConfig
  func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> AIRefactorResponse
}
```

and in `EditorModuleAI`:

```swift
  public func getKnowledgeConfig() async -> String {
    let response = await service.knowledgeConfig()
    return response.jsonEncoded
  }

  public func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> String {
    let response = await service.refactorWithPersona(
      personaID: personaID,
      personaName: personaName,
      circleID: circleID,
      selection: selection,
      context: context,
      knowledgeScope: knowledgeScope
    )
    return response.jsonEncoded
  }
```

Check the regenerated `NativeModuleAI.swift` for the exact parameter order/optionality of `refactorWithPersona` and `getKnowledgeConfig` and match `EditorModuleAI` to it — the generated protocol is the source of truth.

- [ ] **Step 4: Rewrite the nyxCore paths in `AppAIService.swift`**

In `MarkEditMac/Sources/Editor/AppAIService.swift`, replace `listPersonas()` and `refactorWithPersona(...)` with the following, and add the new helpers:

```swift
  func listPersonas() async -> AIPersonaListResponse {
    // Persona Studio tokens (nyx_pa_) use the REST API; MCP tokens use JSON-RPC.
    if let studio = PersonaStudioClient.current() {
      do {
        let personas = try await studio.listPersonas()
        guard !personas.isEmpty else {
          return .init(error: "No published circles for this token.")
        }

        return .init(personas: personas.map {
          AIPersona(
            id: $0.id,
            name: $0.name,
            description: $0.description,
            source: "studio",
            circleId: $0.circleID,
            circleName: $0.circleName
          )
        })
      } catch {
        return .init(error: error.localizedDescription)
      }
    }

    guard let client = NyxCoreClient.personas() else {
      return .init(error: "Enable nyxCore and add a persona token (nyx_pa_ or nyx_mt_) in Settings → AI.")
    }

    do {
      let personas = try await client.listPersonas()
      return .init(personas: personas.map {
        AIPersona(id: $0.id, name: $0.name, description: $0.description, source: "mcp")
      })
    } catch {
      return .init(error: error.localizedDescription)
    }
  }

  func knowledgeConfig() async -> AIKnowledgeConfig {
    var scopes = ["off"]
    let token = (AppPreferences.NyxCore.knowledgeToken ?? "").trimmingCharacters(in: .whitespaces)
    let hasProject = !AppPreferences.NyxCore.projectID.trimmingCharacters(in: .whitespaces).isEmpty
    let hasCollection = !AppPreferences.NyxCore.collectionID.trimmingCharacters(in: .whitespaces).isEmpty

    if token.hasPrefix(AxiomClient.tokenPrefix) {
      if hasProject {
        scopes.append("project")
      }
      if hasCollection {
        scopes.append("global")
      }
      scopes.append("all")
    } else if !token.isEmpty && hasProject {
      // Legacy MCP knowledge token: only project-scoped search is possible.
      scopes.append("project")
    }

    let preferred = Self.resolvedDefaultScope()
    let defaultScope = scopes.contains(preferred) ? preferred : (scopes.count > 1 ? scopes[1] : "off")
    return AIKnowledgeConfig(availableScopes: scopes, defaultScope: defaultScope)
  }

  func refactorWithPersona(
    personaID: String,
    personaName: String,
    circleID: String?,
    selection: String,
    context: String?,
    knowledgeScope: String
  ) async -> AIRefactorResponse {
    // Knowledge is best-effort for both protocols: failures never block the rewrite.
    let knowledge = await loadKnowledge(scope: knowledgeScope, query: selection)
    let user = NyxCorePromptComposer.userPrompt(selection: selection, context: context, knowledge: knowledge)

    // Persona Studio: the rewrite runs server-side (persona voice + billing in nyxCore).
    if let studio = PersonaStudioClient.current() {
      do {
        let content = try await studio.chat(
          personaID: personaID,
          circleID: circleID,
          system: NyxCorePromptComposer.editorContract,
          user: user,
          maxTokens: AppPreferences.AI.maxTokens
        )
        return .init(result: content)
      } catch {
        return .init(error: error.localizedDescription)
      }
    }

    // MCP: fetch the persona's skill prompts, then generate locally via Anthropic.
    guard let personaClient = NyxCoreClient.personas() else {
      return .init(error: "Enable nyxCore and add a persona token (nyx_pa_ or nyx_mt_) in Settings → AI.")
    }

    do {
      let personaPrompt = try await personaClient.personaPrompt(personaID: personaID)
      let system = NyxCorePromptComposer.systemPrompt(personaName: personaName, personaPrompt: personaPrompt)
      return await complete(system: system, userMessage: user)
    } catch {
      return .init(error: error.localizedDescription)
    }
  }

  /// Test hook for Settings → AI: runs a 1-result search in the default scope
  /// and surfaces errors instead of swallowing them.
  func testKnowledge() async -> (success: Bool, message: String) {
    let scope = Self.resolvedDefaultScope()
    guard scope != "off" else {
      return (false, "Knowledge is off — pick a default scope first.")
    }

    do {
      let snippets: [String]
      if let axiom = AxiomClient.current() {
        snippets = try await axiom.search(query: "test", scope: scope, limit: 1)
      } else if scope == "project", let legacy = NyxCoreClient.knowledge() {
        snippets = try await legacy.search(query: "test", limit: 1)
      } else {
        return (false, "Add a knowledge token (nyx_ax_) in Settings → AI.")
      }
      return (true, "Connected — \(snippets.count) result(s)")
    } catch {
      return (false, error.localizedDescription)
    }
  }

  // MARK: - Knowledge

  /// The effective default scope, migrating from the legacy useKnowledge flag
  /// when the new preference has never been set.
  private static func resolvedDefaultScope() -> String {
    let stored = AppPreferences.NyxCore.knowledgeScope
    if !stored.isEmpty {
      return stored
    }
    return AppPreferences.NyxCore.useKnowledge ? "project" : "off"
  }

  private func loadKnowledge(scope: String, query: String) async -> [String] {
    guard scope != "off", AppPreferences.NyxCore.enabled else {
      return []
    }

    let limit = max(1, AppPreferences.NyxCore.knowledgeLimit)
    if let axiom = AxiomClient.current() {
      return (try? await axiom.search(query: query, scope: scope, limit: limit)) ?? []
    }

    // Legacy MCP fallback: project scope only.
    guard scope == "project", let legacy = NyxCoreClient.knowledge() else {
      return []
    }
    return (try? await legacy.search(query: query, limit: limit)) ?? []
  }
```

- [ ] **Step 5: Build everything**

Run:
```bash
cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn build
cd /Users/oliverbaer/Projects/nyx-markedit && xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```
Expected: `yarn build` fails at TS type-check if `index.ts` still passes `useKnowledge` to `refactorWithPersona` — **that is expected at this point only if Task 6 has not been applied**. To keep every commit green, apply the minimal `index.ts` bridge-call fix now (part of this task): in `runPersona`, replace the `refactorWithPersona` call with

```ts
      await this.runRewrite(sel, () => window.nativeModules.ai.refactorWithPersona({
        personaID: persona.id,
        personaName: persona.name,
        circleID: persona.circleId,
        selection: selectedText,
        context,
        knowledgeScope: this.useKnowledge ? 'project' : 'off',
      }));
```

(The full scope switcher replaces `this.useKnowledge` in Task 6.) Re-run both builds.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add CoreEditor/src/bridge/native/ai.ts CoreEditor/src/modules/ai/index.ts MarkEditKit/Sources/Bridge/Native/Generated/ MarkEditKit/Sources/Bridge/Native/Modules/EditorModuleAI.swift MarkEditMac/Sources/Editor/AppAIService.swift
git commit -m "feat(ai): dual-protocol persona routing + knowledge scopes across the bridge"
```

---

### Task 6: Toolbar scope switcher + persona grouping (TS)

**Files:**
- Modify: `CoreEditor/src/modules/ai/index.ts`

**Interfaces:**
- Consumes: `AIKnowledgeConfig`, updated `AIPersona` from Task 5; CSS classes `cm-md-aiScopeRow`, `cm-md-aiScopeSelected`, `cm-md-aiPersonaGroup` from Task 2.
- Produces: final toolbar behavior; no exports.

- [ ] **Step 1: Extend labels and state**

In `CoreEditor/src/modules/ai/index.ts`:

Import `AIKnowledgeConfig` (extend the existing bridge import):

```ts
import { AIAction, AIKnowledgeConfig, AIPersona, AIPersonaListResponse } from '../../bridge/native/ai';
```

Extend `ToolbarLabels` and `defaultLabels` (replace the `knowledge: string;` entry and its default):

```ts
  knowledgeTitle: string;
  scopeOff: string;
  scopeProject: string;
  scopeGlobal: string;
  scopeAll: string;
```

```ts
  knowledgeTitle: 'Knowledge',
  scopeOff: 'Off',
  scopeProject: 'Project',
  scopeGlobal: 'Global',
  scopeAll: 'All',
```

Replace the class fields `private useKnowledge = true;` and `private knowledgeToggleEl…` with:

```ts
    private knowledgeScope: string | undefined;
    private knowledgeConfig: AIKnowledgeConfig | undefined;
```

- [ ] **Step 2: Load the knowledge config with the personas**

Replace the body of `loadPersonas()` with:

```ts
    private async loadPersonas() {
      if (this.personas !== undefined || this.personasLoading) {
        return;
      }

      this.personasLoading = true;
      this.renderPersonaList();

      try {
        const [rawPersonas, rawConfig] = await Promise.all([
          window.nativeModules.ai.listPersonas(),
          window.nativeModules.ai.getKnowledgeConfig(),
        ]);

        let response: AIPersonaListResponse;
        try {
          response = typeof rawPersonas === 'string' ? JSON.parse(rawPersonas) as AIPersonaListResponse : rawPersonas;
        } catch {
          response = { error: 'Invalid persona response payload.' };
        }

        try {
          this.knowledgeConfig = typeof rawConfig === 'string' ? JSON.parse(rawConfig) as AIKnowledgeConfig : rawConfig;
        } catch {
          this.knowledgeConfig = { availableScopes: ['off'], defaultScope: 'off' };
        }

        if (this.knowledgeScope === undefined) {
          this.knowledgeScope = this.knowledgeConfig.defaultScope ?? 'off';
        }

        if (isNonEmpty(response.error)) {
          this.personas = [];
          this.personaError = response.error;
        } else {
          this.personas = response.personas ?? [];
          this.personaError = undefined;
        }
      } catch (err) {
        this.personas = [];
        this.personaError = err instanceof Error ? err.message : String(err);
      } finally {
        this.personasLoading = false;
        this.renderPersonaList();
      }
    }
```

- [ ] **Step 3: Replace `renderPersonaList()` (scope row + circle grouping)**

```ts
    private renderPersonaList() {
      this.personaList.replaceChildren();
      this.renderScopeRow();

      if (this.personasLoading) {
        const info = document.createElement('span');
        info.className = 'cm-md-aiPersonaInfo';
        info.textContent = activeLabels.personaLoading;
        this.personaList.appendChild(info);
        return;
      }

      if (this.personas === undefined || this.personas.length === 0) {
        const info = document.createElement('span');
        info.className = 'cm-md-aiPersonaInfo';
        info.textContent = isNonEmpty(this.personaError) ? this.personaError : activeLabels.noPersonas;
        this.personaList.appendChild(info);
        return;
      }

      // Group Persona Studio personas by circle; MCP personas have no group.
      const grouped = new Map<string, AIPersona[]>();
      for (const persona of this.personas) {
        const key = persona.circleName ?? '';
        const list = grouped.get(key) ?? [];
        list.push(persona);
        grouped.set(key, list);
      }

      for (const [circleName, personas] of grouped) {
        if (circleName.length > 0 && grouped.size > 1) {
          const header = document.createElement('span');
          header.className = 'cm-md-aiPersonaGroup';
          header.textContent = circleName;
          this.personaList.appendChild(header);
        }

        for (const persona of personas) {
          const pBtn = document.createElement('button');
          pBtn.type = 'button';
          pBtn.textContent = persona.name;
          if (isNonEmpty(persona.description)) {
            pBtn.title = persona.description;
          }
          pBtn.addEventListener('click', () => {
            this.personaList.style.display = 'none';
            void this.runPersona(persona);
          });
          this.personaList.appendChild(pBtn);
        }
      }
    }

    /** Knowledge scope switcher: Off / Project / Global / All. */
    private renderScopeRow() {
      const row = document.createElement('div');
      row.className = 'cm-md-aiScopeRow';

      const title = document.createElement('span');
      title.className = 'cm-md-aiPersonaInfo';
      title.textContent = activeLabels.knowledgeTitle;
      row.appendChild(title);

      const available = this.knowledgeConfig?.availableScopes ?? ['off'];
      const entries: [string, string][] = [
        ['off', activeLabels.scopeOff],
        ['project', activeLabels.scopeProject],
        ['global', activeLabels.scopeGlobal],
        ['all', activeLabels.scopeAll],
      ];

      for (const [scope, label] of entries) {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.textContent = label;
        btn.disabled = !available.includes(scope);
        if (btn.disabled) {
          btn.title = 'Not available — check knowledge token, Project ID, or Collection ID in Settings';
        }
        if (scope === (this.knowledgeScope ?? 'off')) {
          btn.classList.add('cm-md-aiScopeSelected');
        }
        btn.addEventListener('click', event => {
          event.stopPropagation();
          this.knowledgeScope = scope;
          this.renderPersonaList();
        });
        row.appendChild(btn);
      }

      this.personaList.appendChild(row);
    }
```

- [ ] **Step 4: Pass the scope in `runPersona`**

Replace the `refactorWithPersona` call (interim version from Task 5 Step 5) with:

```ts
      await this.runRewrite(sel, () => window.nativeModules.ai.refactorWithPersona({
        personaID: persona.id,
        personaName: persona.name,
        circleID: persona.circleId,
        selection: selectedText,
        context,
        knowledgeScope: this.knowledgeScope ?? 'off',
      }));
```

- [ ] **Step 5: Build + tests**

Run: `cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn build && yarn test`
Expected: PASS. ESLint will flag any leftover reference to `useKnowledge`/`knowledgeToggleEl` — remove them if it does.

- [ ] **Step 6: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add CoreEditor/src/modules/ai/index.ts
git commit -m "feat(toolbar): knowledge scope switcher + circle-grouped personas"
```

---

### Task 7: Settings → AI restructure

**Files:**
- Modify: `MarkEditMac/Sources/Settings/AISettingsView.swift`

**Interfaces:**
- Consumes: `AppPreferences.NyxCore.collectionID` / `.knowledgeScope` (Task 4), `AppAIService.testKnowledge()` (Task 5).
- Produces: final Settings UI; nothing downstream.

- [ ] **Step 1: Update state variables**

In `AISettingsView.swift`, replace the `nyxUseKnowledge` state (line ~29) with:

```swift
  @State private var nyxCollectionID: String = AppPreferences.NyxCore.collectionID
  @State private var nyxKnowledgeScope: String = {
    let stored = AppPreferences.NyxCore.knowledgeScope
    if !stored.isEmpty {
      return stored
    }
    return AppPreferences.NyxCore.useKnowledge ? "project" : "off"
  }()
  @State private var knowledgeStatus: String = ""
  @State private var knowledgeStatusIsError: Bool = false
  @State private var knowledgeTesting: Bool = false
```

- [ ] **Step 2: Fix the persona token placeholder + description**

Replace the persona-token `SecureField` block (lines ~114-124) with:

```swift
        VStack(alignment: .leading) {
          SecureField("", text: $nyxPersonaToken, prompt: Text("nyx_pa_… / nyx_mt_…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxPersonaToken) {
              AppPreferences.NyxCore.personaToken = nyxPersonaToken.trimmingCharacters(in: .whitespaces)
            }

          Text("Persona Studio token (nyx_pa_) or MCP token (nyx_mt_) — detected automatically. Stored in the Keychain.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Persona token")
```

- [ ] **Step 3: Rework the knowledge section**

Replace the knowledge section (the `Section` containing the knowledge token, endpoint, project ID, and the old "Ground rewrites…" toggle, lines ~135-172) with:

```swift
      // Knowledge credentials (Axiom REST, with legacy MCP fallback)
      Section {
        VStack(alignment: .leading) {
          SecureField("", text: $nyxKnowledgeToken, prompt: Text("nyx_ax_…"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxKnowledgeToken) {
              AppPreferences.NyxCore.knowledgeToken = nyxKnowledgeToken.trimmingCharacters(in: .whitespaces)
            }

          Text("Axiom token (nyx_ax_). A tenant-wide token enables the Global and All scopes; a project token is pinned to its project. Stored in the Keychain.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Knowledge token")

        TextField("", text: $nyxKnowledgeBaseURL)
          .textFieldStyle(.roundedBorder)
          .onChange(of: nyxKnowledgeBaseURL) {
            AppPreferences.NyxCore.knowledgeBaseURL = nyxKnowledgeBaseURL
          }
          .formLabel("Knowledge endpoint")

        VStack(alignment: .leading) {
          TextField("", text: $nyxProjectID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxProjectID) {
              AppPreferences.NyxCore.projectID = nyxProjectID.trimmingCharacters(in: .whitespaces)
            }

          Text("Project for the \"Project\" scope.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Project ID")

        VStack(alignment: .leading) {
          TextField("", text: $nyxCollectionID, prompt: Text("UUID"))
            .textFieldStyle(.roundedBorder)
            .onChange(of: nyxCollectionID) {
              AppPreferences.NyxCore.collectionID = nyxCollectionID.trimmingCharacters(in: .whitespaces)
            }

          Text("Standalone Axiom collection for the \"Global\" scope. Optional.")
            .formDescription()
        }
        .formLabel(alignment: .top, "Collection ID")

        Picker("", selection: $nyxKnowledgeScope) {
          Text("Off").tag("off")
          Text("Project").tag("project")
          Text("Global").tag("global")
          Text("All").tag("all")
        }
        .pickerStyle(.segmented)
        .onChange(of: nyxKnowledgeScope) {
          AppPreferences.NyxCore.knowledgeScope = nyxKnowledgeScope
        }
        .formLabel("Default scope")
      }
```

- [ ] **Step 4: Add the "Test knowledge" button**

In the last `Section` (the one with "Test personas"), extend the `HStack` after the persona test status `Text`:

```swift
          Button("Test knowledge") {
            runKnowledgeTest()
          }
          .disabled(knowledgeTesting || nyxKnowledgeToken.trimmingCharacters(in: .whitespaces).isEmpty)

          if knowledgeTesting {
            ProgressView().scaleEffect(0.6)
          }

          if !knowledgeStatus.isEmpty {
            Text(knowledgeStatus)
              .foregroundStyle(knowledgeStatusIsError ? .red : .green)
              .font(.callout)
          }
```

And add the handler next to `runNyxConnectionTest()`:

```swift
  private func runKnowledgeTest() {
    knowledgeTesting = true
    knowledgeStatus = ""
    knowledgeStatusIsError = false

    Task { @MainActor in
      let result = await AppAIService().testKnowledge()
      knowledgeTesting = false
      knowledgeStatusIsError = !result.success
      knowledgeStatus = result.message
    }
  }
```

- [ ] **Step 5: Build**

Run (repo root): `xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git add MarkEditMac/Sources/Settings/AISettingsView.swift
git commit -m "feat(settings): persona/knowledge token groups, scopes, test knowledge"
```

---

### Task 8: Full build, install, end-to-end verification

**Files:** none (verification only).

- [ ] **Step 1: Full rebuild + all tests**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit/CoreEditor && yarn build && yarn test
cd /Users/oliverbaer/Projects/nyx-markedit && xcodebuild build -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -5
```
Expected: Jest PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Install the app**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
BUILT=$(xcodebuild -project MarkEdit.xcodeproj -scheme MarkEditMac -destination 'platform=macOS' -showBuildSettings CODE_SIGNING_ALLOWED=NO 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ {print $3; exit}')
rm -rf /Applications/MarkEdit.app && cp -R "$BUILT/MarkEdit.app" /Applications/
xattr -dr com.apple.quarantine /Applications/MarkEdit.app
```
Expected: app copies without error and launches.

- [ ] **Step 3: Manual verification checklist (user has the tokens)**

Ask the user to verify, with real tokens in Settings → AI:

1. Persona Studio token (`nyx_pa_`) in "Persona token" → "Test personas" shows `Connected — N personas` (or the explicit "No published circles" message).
2. MCP token (`nyx_mt_`) in the same field → "Test personas" still works (global personas).
3. Axiom token (`nyx_ax_`) + Project ID → "Test knowledge" shows `Connected — 1 result(s)`.
4. Select text → toolbar appears **without covering the selection** (top-of-document selection flips it below); drag grip moves it; colors match the active editor theme (test a dark theme while macOS is light).
5. Persona ▾ → scope row shows enabled scopes only; pick a Studio persona → rewrite replaces the selection.

- [ ] **Step 4: Update the session checkpoint and push**

```bash
cd /Users/oliverbaer/Projects/nyx-markedit
git push -u origin feat/nyxcore-dual-protocol
gh pr create --repo nyxCore-Systems/nyx.markEdit --base main \
  --title "nyxCore dual-protocol personas, Axiom knowledge scopes, toolbar redesign" \
  --body "Accepts Persona Studio (nyx_pa_) tokens via the REST API and MCP tokens via JSON-RPC, routed by prefix. Knowledge search moves to the Axiom REST API with Off/Project/Global/All scopes (legacy MCP fallback kept). Floating toolbar: flip-to-fit positioning, edge clamping, drag grip, editor-theme colors. Spec: docs/superpowers/specs/2026-07-02-nyxcore-dual-protocol-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: PR created against `main` (includes the not-yet-merged `fix/nyxcore-persona-token-split` commits — this PR supersedes that branch's PR).
