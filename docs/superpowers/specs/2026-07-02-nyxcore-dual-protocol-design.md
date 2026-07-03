# Design: nyxCore Dual-Protocol Integration & Floating Toolbar Redesign

**Date:** 2026-07-02
**Repo:** nyx-markedit (all changes live here; nyxcore-systems is untouched)
**Base branch:** `feat/nyxcore-dual-protocol` (stacked on `fix/nyxcore-persona-token-split`)

## Problem

1. **Persona Studio tokens are rejected.** Persona Studio tokens (`nyx_pa_`, table
   `persona_api_tokens`) are only accepted by the REST endpoints
   `GET /api/v1/persona/list` and `POST /api/v1/persona/chat`. markedit sends them as
   Bearer tokens to the MCP endpoint (`/api/v1/mcp`), whose hash lookup runs against
   `mcp_api_tokens` (`nyx_mt_`/`nyx_mp_`) and returns a generic
   `401 Invalid or expired token`. Protocol mismatch, not a bug in either side.
2. **Knowledge search is limited.** The MCP tool `nyxcore_search` requires a `projectId`
   for tenant tokens and only ever searches Axiom documents (its advertised `sources`
   parameter is validated but never forwarded — dead API surface in nyxcore). Tenant-wide
   or collection-scoped search is only reachable via the Axiom REST API
   `POST /api/v1/rag/search` with an `nyx_ax_` token.
3. **The floating AI toolbar covers the selection.** Positioning uses a hardcoded
   `top = selectionTop - 44px` with only a `>= 0` clamp: selections near the top of the
   viewport clamp to `top: 0` and the toolbar lands on the selected text. No flip-below,
   no right/bottom clamping, no real size measurement. It also ignores the active editor
   theme (uses CSS `Canvas`/`CanvasText` system colors; the `--md-ai-bg` variable it
   references is defined nowhere).

## Decisions (user-approved 2026-07-02)

1. **Personas: accept both token kinds, route by prefix.** `nyx_pa_` → Persona Studio
   REST (server-side LLM call, billing/budget in nyxCore). `nyx_mt_`/`nyx_mp_` → existing
   MCP path (global personas + skill prompts, local Anthropic call).
2. **Knowledge: Axiom REST with three scopes.** One tenant-wide `nyx_ax_` token against
   `POST /api/v1/rag/search`. Scope selector: Projekt / Global / Alle (plus Aus). The
   "axiom" option from the original idea is dropped — everything searchable *is* Axiom.
3. **Floating window: upgrade the web toolbar** (no native NSPanel, no CM-tooltip
   rewrite): real size measurement, flip-to-fit, edge clamping, drag handle, colors from
   the active editor theme.

## 1. Persona connection — dual protocol

### New: `MarkEditMac/Sources/Editor/PersonaStudioClient.swift`

Stateless REST client, sibling of `NyxCoreClient`.

- `listPersonas()` → `GET <origin>/api/v1/persona/list`,
  `Authorization: Bearer nyx_pa_…`.
  Response: `{ ok, circles: [{ id, slug, name, …, personas: [{ id, name, description,
  imageUrl, category, isLead, profile }] }], requestId }`.
  Flatten circles → one entry per (circle, persona); persona display name carries the
  circle name as subtitle; keep `circleId` on the entry.
- `chat(personaId:circleId:messages:maxTokens:)` → `POST <origin>/api/v1/persona/chat`.
  Body: `{ messages: [{role, content}], personaId, circleId?, maxTokens?, useSkills: true }`.
  Success: `{ ok: true, content, conversationId, persona, model, provider, usage, requestId }`.
  Errors: `{ ok: false, error: { code, message }, requestId }` with codes
  `UNAUTHORIZED` (401), `RATE_LIMITED` (429), `VALIDATION_ERROR` (400), `FORBIDDEN` (403),
  `NOT_FOUND` (404), `BUDGET_EXCEEDED` (402), `PROVIDER_ERROR` (502), `INTERNAL_ERROR` (500).

Prompt shape for a rewrite: the editor contract ("return only the rewritten passage, no
commentary") goes as a `role: "system"` message inside `messages` (passed through 1:1 to
the LLM as a supplementary message; the persona's CORE system prompt stays authoritative,
built server-side). The rewrite instruction + optional knowledge block + selection go as
the `role: "user"` message, composed by `NyxCorePromptComposer` (reuse `userPrompt(...)`).

### Routing in `AppAIService`

- `listPersonas()`: if persona token has prefix `nyx_pa_` → `PersonaStudioClient`;
  else → existing `NyxCoreClient.personas()` MCP path. Persona entries gain
  `source: "studio" | "mcp"` and optional `circleId`.
- `refactorWithPersona()`: studio persona → `PersonaStudioClient.chat(...)`, response
  `content` replaces the selection (no local Anthropic call). MCP persona → unchanged
  (skill prompt via MCP + local Anthropic `complete()`).
- Endpoint derivation: take the configured persona endpoint URL, extract the origin.
  `nyx_pa_` tokens call `<origin>/api/v1/persona/*`; MCP tokens use the URL as stored.
  Existing stored values (`https://nyxcore.cloud/api/v1/mcp`) keep working for both.
- Error mapping: REST error codes → readable strings (German UX not required; match
  existing English UI): e.g. `BUDGET_EXCEEDED` → "Persona Studio monthly budget exceeded",
  `FORBIDDEN` → "Token not allowed for this circle". Shown inline in the persona dropdown
  (existing `personaError` path) and in Settings "Test personas".

### Bridge (`yarn codegen` required)

`CoreEditor/src/bridge/native/ai.ts`: `AIPersona` gains `source: string` and
`circleId?: string`. Regenerate `NativeModuleAI.swift`.

## 2. Knowledge — Axiom REST + scope selector

### New: `MarkEditMac/Sources/Editor/AxiomClient.swift`

- `search(query:scope:limit:)` → `POST <origin>/api/v1/rag/search`,
  `Authorization: Bearer nyx_ax_…`. Origin is derived from the configured knowledge
  endpoint URL exactly like the persona endpoint derivation in §1.
  Body by scope:
  - **Projekt** → `{ query, projectId: <settings>, limit }`
  - **Global** → `{ query, collectionId: <settings>, limit }`
  - **Alle** → `{ query, limit }` (requires a tenant-wide `nyx_ax_` token; a
    project-scoped token is pinned server-side and silently degrades to its project)
  Response: `{ ok, results: [{ content, heading, filename, authority, score, … }], requestId }`.
  Map into the existing `[filename › heading]\ncontent` snippet format.

### Routing & fallback

If the knowledge token has prefix `nyx_ax_` → `AxiomClient`. If it still holds an MCP
token (`nyx_mt_`/`nyx_mp_`) → legacy `NyxCoreClient.knowledge()` MCP search (scope
selector then only offers Aus/Projekt). Nothing breaks for the current setup.

Knowledge stays **best-effort**: failures never block the rewrite (current behavior kept).

### Toolbar control + bridge

The "Use project knowledge" checkbox in the persona dropdown becomes a compact scope
switcher: **Aus / Projekt / Global / Alle**. Global is disabled when no Collection ID is
configured; Alle/Global are disabled when the token is not `nyx_ax_`.

The toolbar learns which scopes are available via a new bridge method
`ai.getKnowledgeConfig(): { availableScopes: string[], defaultScope: string }`, computed
natively from preferences (token prefix, projectId/collectionId presence). Called lazily
when the persona dropdown first opens (alongside `listPersonas`).
Bridge changes: `refactorWithPersona`'s `useKnowledge: boolean` → `knowledgeScope: string`
(`"off" | "project" | "global" | "all"`), plus the new `getKnowledgeConfig` method;
default seeded from `defaultScope`. `yarn codegen` required.

## 3. Floating toolbar redesign (CoreEditor, web)

All in `CoreEditor/src/modules/ai/index.ts` + `index.css`.

- **Positioning:** extract a pure function
  `computeToolbarPosition(selStartRect, selEndRect, toolbarSize, editorRect, dragOffset?, wasFlipped?)`
  → `{ top, left, flipped }`:
  - measure the toolbar's real rect after render (no 44px constant);
  - prefer above the selection start; flip below the selection **end** when the space
    above is insufficient; sticky `wasFlipped` flag per visibility session to avoid
    flip-flutter (pattern borrowed from `TextCompletionContext.swift:76-96`);
  - clamp `left` to `[0, editorRect.width - toolbarWidth]` and `top` to
    `[0, editorRect.height - toolbarHeight]`;
  - `z-index: 550` (above CodeMirror's `.cm-tooltip` at 500).
- **Draggable:** narrow grip element on the left edge (`cm-md-aiGrip`, `cursor: grab`);
  `mousedown` → track `mousemove` deltas → update `top/left` (clamped); the drag offset
  persists until the toolbar hides, then resets. No persistence across sessions.
- **Theming:** import `globalState.colors` (`CoreEditor/src/common/store`); derive
  background, text, accent, hover and border colors from the active `EditorColors`
  palette with the current `Canvas`/`CanvasText` values as fallback when colors are
  undefined. Re-style on theme change (colors are re-set via `setEditorColors`; read at
  reposition/build time). Submenus stay opaque (keep the branch fix), 8px radius,
  subtle 1px border, grouped actions with separators, system UI font.
- **Persona list:** studio personas grouped by circle (group header = circle name);
  MCP personas flat as today. Real error text inline (keep branch behavior); when the
  studio list is empty: "No published circles for this token".

### Tests (Jest, CoreEditor)

`computeToolbarPosition` gets unit tests: above-fits, flip-below, both-clamped,
drag-offset clamping, sticky-flip. This is the only meaningfully testable unit and the
historically buggy one. No new Swift test target (none exists for MarkEditMac).

## 4. Settings → AI restructure (`AISettingsView.swift`, `AppPreferences.swift`)

nyxCore section splits into two groups:

- **Personas:** token (SecureField, placeholder `nyx_pa_… / nyx_mt_…`, description
  "Persona Studio token (nyx_pa_) or MCP token (nyx_mt_) — detected automatically"),
  endpoint (unchanged default), "Test personas" button (routes by prefix, shows
  count or mapped error).
- **Knowledge:** token (SecureField, placeholder `nyx_ax_…`, description mentions
  tenant-wide token requirement for Alle/Global), endpoint, Project ID (existing),
  **new** Collection ID (optional, enables Global), default scope picker
  (Aus/Projekt/Global/Alle, new key `nyxcore.knowledge-scope`), **new** "Test knowledge"
  button (1-result search in the selected scope).

Keychain accounts unchanged (`nyxcore.persona-token`, `nyxcore.token`); new UserDefaults
keys: `nyxcore.collection-id`, `nyxcore.knowledge-scope`. The old
`nyxcore.use-knowledge` boolean migrates: `true` → `project`, `false` → `off`.

## 5. Risks & build gotchas

- Persona Studio list only returns **published** circles with chatbot-scope personas —
  empty tenant catalogs get an explicit message, not "No personas".
- "Alle"/"Global" need a tenant-wide `nyx_ax_` token minted in the nyxCore dashboard;
  project-scoped tokens are pinned server-side (documented in the settings description).
- `persona/chat` is **not streaming** (single JSON response) — same UX as today's
  Anthropic call (busy state until done).
- New Swift files must be added to `project.pbxproj` in 4 places (explicit file list;
  continue the `9AB1000000000000000B000X` ID scheme).
- SwiftLint build plugin: `case let .x(a, b)` pattern matching, `Self(...)` in static
  references, no superfluous disables.
- Any TS/CSS change requires `yarn build` before the Xcode build (embedded dist).
- Bridge changes require `yarn codegen`; never edit generated Swift.

## Out of scope

- nyxcore-systems changes (wiring the dead `sources` param, streaming persona chat,
  a flat standalone-persona list endpoint) — candidates for later, tracked in nyxCore.
- Cross-session persistence of the dragged toolbar position.
- Unit-test target for MarkEditMac.
