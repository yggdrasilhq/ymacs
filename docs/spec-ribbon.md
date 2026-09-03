# Spec: the ribbon component (chrome tabs + floating command bar)

Status: DESIGN v2, 2026-09-04. Supersedes the v1 attached-strip ribbon
(2026-09-03). ymacs is the forcing consumer; yggterm renders the component
from the document schema (`ribbon-bar` widget). Owner directives: the
command bar FLOATS over the viewport (it must never shrink or displace the
viewport); the tab strip does NOT float — it renders on yggterm's
background chrome, above the viewport card; visibility is wired to
`tab-bar-mode`; ribbon elements are addable/removable from ymacs Lisp.

## Anatomy — one component, two layers

    ┌──────────────────────────────────────────────────────────┐
    │ yggterm chrome (shell bg)                                │
    │  [pending-keys label]        Home  Edit  View  Help      │  ← tab strip
    │ ┌──────────────────────────────────────────────────────┐ │    (pinned)
    │ │ viewport card (the ymacs editor)                     │ │
    │ │  ┌────────────────────────────────────────────┐      │ │
    │ │  │ floating command panel (active tab groups) │      │ │  ← floats
    │ │  └────────────────────────────────────────────┘      │ │    OVER card
    │ └──────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────┘

1. **Tab strip** (pinned, chrome): the tab bar. Text tabs on the shell's
   own background; active tab = accent underline. Always visible while
   `tab-bar-mode` is on. Never overlays content; occupies its own slim
   line, like a menu bar.
2. **Command panel** (floating): the active tab's command groups, rendered
   as an opaque, bordered, shadowed panel anchored under the tab strip,
   OVERLAYING the viewport card. GUI-owned open/closed view state — a
   menu, not a layout region. Defaults closed; the editor gets the full
   card until the user asks for commands.

## State ownership

| State | Owner | How it changes |
|---|---|---|
| tabs, labels, groups, buttons, primary flags | app (ymacs) | Lisp `tab-bar-*` API → schema |
| active tab | app | `ribbon-tab:<id>` action POSTs; Lisp `tab-bar-select-tab` |
| panel open/closed | GUI (view state) | gestures only — never a POST, never schema |

The GUI never persists ribbon state; a remount (surface expiry, session
close) starts closed. The app never learns about dismissals — closing a
menu is not a command.

## Interaction contract

- Click tab X, panel closed → POST `ribbon-tab:X` (if X ≠ active), open panel.
- Click tab X, panel open, X ≠ active → POST, panel stays open.
- Click active tab, panel open → close. No POST (view gesture).
- Click anywhere outside the strip/panel (backdrop) → close. No POST.
- Escape while the strip or panel holds focus → close. No POST.
- Schema refresh while open → panel re-renders in place; open state survives.
- No ribbon in the schema, or `tab-bar-mode` off → nothing renders and the
  card keeps the full rect (unchanged v1 contract).

## Wire contract (unchanged)

The `ribbon-bar` widget schema is UNCHANGED:
`{id, action, active, tabs:[{id,label}], groups:[{label, buttons, right}]}`.
Old GUI + new app → old attached-strip render (graceful degrade). New GUI +
old app → same floating behaviour. Tabs render in the strip; `groups`
(declared for the ACTIVE tab) render in the panel. Buttons POST on the
ordinary document action channel; the strip subset vocabulary
(label/toolbar/button) keeps its v1 rendering.

## Styling law

Theme tokens only (`DocTheme`: bg/fg/muted/accent/border/chrome) — no
hardcoded colours anywhere. Hover/focus states ride ONE CSS block scoped
to `[data-document-ribbon]` with custom properties set from the tokens.
The panel is opaque (the terminal layer paints under the column); the
shadow is a neutral alpha so it reads on light and dark themes.

## z-order (the overlay seam)

Inside the document layer: tab strip (z3, position:relative) above the
floating panel (z2, absolute, below the strip) above the backdrop (z1,
fixed inset:0, transparent, click-to-close) above the card (static). The
backdrop must never cover the strip, or tab clicks would dismiss instead
of switch.

## ymacs wiring — tab-bar-mode

- `*tab-bar-tabs*` — ordered tabs: `(:id :name :groups)`; groups are
  `(:label :buttons :right)`; buttons `(:action :label :title :primary)`.
- `tab-bar-mode` — show/hide the strip (THE ribbon switch;
  `tool-bar-mode` is an alias of it — the ribbon fuses Emacs' tool bar
  and tab bar into one strip; ledger entry).
- Lisp API (each bumps `document-version`, so changes render within one
  heartbeat): `tab-bar-select-tab`, `tab-bar-add-tab`, `tab-bar-remove-tab`,
  `tab-bar-rename-tab`, `tab-bar-add-group`, `tab-bar-remove-group`,
  `tab-bar-add-button`, `tab-bar-remove-button`.
- Default tabs: home / edit / view / help seeded from the v1 group tables.
