# MarkEdit v2.0.0 Release Notes

v2.0.0 finishes what v1.34.0 started. The prompt field and named knowledge sources shipped in 1.34.0; this release makes the settings behind them actually reachable, lets you pick projects by name instead of pasting UUIDs, and gives the knowledge lookup access to a project's patterns, solutions and pains rather than documents alone.

There are no breaking changes and no migration — existing settings, tokens and knowledge sources keep working untouched.

### Fixed

- **Settings no longer end early** — the settings window sized itself to the selected tab with no upper bound and no way to scroll. On a display too short for the AI pane, macOS shrank the oversized window to fit and everything below the fold became unreachable, which read as "the nyxCore settings are missing" rather than "the window is too small". The window is now capped at the screen's visible height and any pane taller than that scrolls. Panes that already fit are unchanged.
- **Project patterns and insights are reachable** — the knowledge lookup for the "Project + patterns" source kind reached only documents, and dropped the token on part of the path. It now pulls the project's recorded patterns, solutions and pains as intended.
- **The AI pane fits its window** — a description under *Knowledge sources* had no width constraint. Under the form's `fixedSize`, its full single-line ideal width inflated the measured layout and produced a wrong window height.

### Improved

- **Pick projects by name** — Project ID and each knowledge source row get a *Choose* menu that lists your projects by name and fills in the UUID. The fields stay text fields, so a project the catalog does not return, or a token that cannot list projects, can still be used by pasting the id.
- **The "All" scope explains itself** — the scope descriptions now say which token unlocks which scope: a tenant-wide Axiom token enables Global and All, a project token is pinned to its project. Listing projects needs an MCP token (`nyx_mt_`); with a Persona Studio token the id is entered by hand.

### Developer

- **Build it yourself** — the README gains a *Build from source* section with the exact commands for a local Release build and a downloadable zip, mirroring what CI runs for a tagged release.
- **The repository no longer ships its own build output** — a committed `build/` directory of Xcode DerivedData (4,860 files, about 1 GB) and a built `MarkEdit.zip` have been untracked and ignored. This does not shrink the repository's history.

### Notes

This build is **unsigned** and not notarized. Gatekeeper will refuse it on first launch — open it once via right-click → *Open*. Requires **macOS 15.0 or later**.
