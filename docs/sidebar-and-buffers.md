# Sidebar and Buffer Management

> Design SSOT is [spec-primitives.md](spec-primitives.md) §1.2: the sidebar
> is now a *window component* — its content is donated by the focused
> window's major/minor modes (org: search + speed-nav; gdb: breakpoints).
> Max ONE sidebar in view per frame stands.

## The Single-Sidebar Window System

Traditional Emacs creates visual clutter by splitting the active editing window to display buffer lists (`*Buffers*`), file trees, and help documentation. `ymacs` enforces a clean, distraction-free model:

1. **Maximum One Sidebar in View:**
   - At any time, `ymacs` presents at most **one** auxiliary sidebar window (contributed right panel).
   - This preserves focus and viewport real estate.

2. **Panes Hosted in the Sidebar:**
   - **Buffers:** Live, searchable list of active buffers, categorized by mode and project, with dirty status markers and quick-close actions.
   - **Outline:** Dynamic Org mode or markdown tree view for quick heading navigation.
   - **Project:** File tree browser for the current repository workspace.
   - **Inspector:** Interactive Lisp object, telemetry, and ytrace probe viewer.

3. **Dynamic Spawning & Despawning:**
   - `M-x ymacs-toggle-sidebar` (or `F8` / `C-c s`) toggles the active sidebar.
   - Sidebars despawn automatically when dismissed or when an action finishes.
