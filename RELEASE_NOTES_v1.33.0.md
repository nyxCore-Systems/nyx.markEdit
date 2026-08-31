# MarkEdit v1.33.0 Release Notes

v1.33.0 introduces **dual-protocol nyxCore AI integration** with support for both Axiom and Persona Studio knowledge sources, new AI settings in Preferences, and a redesigned, draggable toolbar with knowledge scope switching. The editor now intelligently routes persona and knowledge requests across multiple AI protocols, giving you unified access to your AI personas and knowledge bases.

### New

- **Dual-protocol AI routing** — seamlessly switch between Axiom and Persona Studio personas and knowledge sources without leaving the editor.
- **Axiom search integration** — query your Axiom knowledge bases directly from the editor with project, global, and all-scopes search.
- **Persona Studio support** — list and chat with your Persona Studio personas using a `nyx_pa_` token, alongside the existing nyxCore MCP path.
- **Knowledge scope switcher** — quickly toggle between different knowledge sources directly from the toolbar.
- **AI settings pane** — new dedicated section in Preferences for managing AI personas, knowledge tokens, and scopes.
- **Draggable toolbar** — reposition the floating toolbar with a drag grip; automatically repositions to fit on screen.

### Improved

- **Persona and knowledge organization** — organize AI credentials into token groups with clear scope assignments (project-level, global, all sources).
- **Toolbar positioning** — automatic flip-to-fit logic ensures the toolbar stays visible and accessible regardless of window position.
- **Toolbar styling** — matches your editor theme colors for a more cohesive look.
- **Knowledge gating** — single source of truth for which knowledge scopes are active, preventing token spillover between protocols.

### Fixed

- **Settings window layout** — AI pane now fits properly in the fixed 580pt settings window.
- **Axiom error display** — errors from Axiom searches are now presented readably in the UI.
- **Toolbar drag behavior** — cancels in-flight drags when the toolbar is destroyed.
- **Toolbar dropdown** — fixed dropdown interaction on the personas button.

### Notes

This build is **unsigned**. Requires **macOS 15.0 or later**.
