# MarkEdit v1.34.0 Release Notes

v1.34.0 adds a **free-form prompt field** to the AI toolbar and replaces the knowledge scope buttons with a **named source picker**. Instead of choosing between "Project", "Global" and "All", you pick the project or Axiom collection by the name you gave it — and the source is visible above the field before you send, not hidden behind a menu after the fact.

The other half of this release is about honesty: when a rewrite could not consult the knowledge source you chose, it now says so.

### New

- **Prompt field** — write your own instruction for the selected text instead of picking a canned action: "expand this with the relevant facts from the Axiom", "turn these bullet points into full paragraphs", "match a formal tone". The existing Improve / Shorten / Expand / Fix Grammar buttons stay where they are.
- **Named knowledge sources** — configure any number of projects and Axiom collections in Settings → AI, each with a display name, and pick between them in the editor. The two existing Project ID / Collection ID fields keep working as before.
- **Prompt history** — your last five instructions are offered as one-tap chips. Until you have any, four worked examples show the shape of a useful instruction.
- **Keyboard flow** — `↵` runs the instruction, `⇧↵` adds a line break, `Esc` closes the panel and hands focus back to the editor.

### Improved

- **One source picker for everything** — the persona menu and the prompt field now share the same knowledge selection, so the two can no longer disagree about what the next rewrite will be grounded in.
- **The instruction shapes the search** — asking to "expand with the release criteria" searches the knowledge base for release criteria, rather than only for what the passage already says.
- **Grounding failures are visible** — knowledge retrieval stays best-effort and never blocks a rewrite, but a failure now appears as a warning beside the result. A passage expanded from the Axiom and one expanded from the model's own knowledge look identical in the document; only the warning tells them apart. An empty result is reported for the same reason.
- **Fewer invented facts** — when nothing was retrieved, the model is explicitly told not to invent sources or facts to satisfy the instruction.

### Fixed

- **Unknown knowledge scopes fail closed** — an unrecognised scope raises an error instead of silently widening the search to every document in the tenant.

### Notes

This build is **unsigned**. Requires **macOS 15.0 or later**.
