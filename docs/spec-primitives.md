# ymacs Primitives Law — Frame, Window, Buffer, and the ymacs Surfaces

Owner directive, 2026-09-02. This document is the design SSOT for the ymacs
rebuild. It supersedes the volume-claims of the v0.1.x wave (see §9) wherever
they conflict. Everything here is law until the owner amends it; the manual
(`docs/manual.org`) tracks what is *implemented* against this law.

---

## 0. Prime directive

Maximum Emacs compatibility, with more surfaces than Emacs ships out of the
box — and with sane choices wherever Emacs carries sixty-year-old baggage.
The resolution of "maximum compat" vs "sane deviations" is fixed by one rule:

> **Compat rule.** Every concept Emacs packages can observe (buffers, modes,
> keymaps, the kill-ring, macros, registers, the minibuffer protocol) behaves
> exactly as Emacs. Every ymacs addition is an *additive, window-scoped
> component* that no package is required to know about. Divergences are
> deliberate, numbered, and tracked in `docs/emacs-manual/divergences.org`.

## 1. Primitives

Emacs has three primitives: Frame, Window, Buffer. ymacs keeps all three and
gives Frame and Window superpowers.

### 1.1 Buffer — unchanged in role, re-owned underneath

A buffer is the unit of content: name, point, mark, local modes, keymap,
undo history, kill-ring participation — the full Emacs contract stays.

Ownership change (owner directive): **the buffer's content model and its
rendering belong to `emd-renderer`** (libyggterm), not to ymacs and not to
yedit:

- A buffer's text is an **emd document** — the typed block tree of
  `emd-renderer`. Plain text is the degenerate document (one plain block);
  org-mode text is a rich document (headings, drawers, blocks, tables as
  typed nodes).
- The **ASCII text surface** currently used by yedit (the plain-text
  render/edit surface) moves *into* `emd-renderer`, so ymacs, yedit, and any
  later libyggterm app render and edit through one engine. yedit keeps its
  app chrome; the surface underneath becomes emd-renderer's.
- emd-renderer gains **org-mode component extensibility**: org constructs
  arrive as typed nodes/components in emd (the same discipline as today's
  ```emd fenced components — unknown node fails loud, never a string hack in
  a renderer). ymacs' org mode then *animates* those components — exactly
  the way Emacs org mode gives superpowers to its renderer: TODO cycling,
  checkbox toggling, babel tangle, timestamps, agenda views.
- The ymacs Lisp buffer object keeps identity and state (value_key, modes,
  point/mark, modification flags) and holds a handle to the emd document.
  Concurrency laws are unchanged: value_key stability, no clobbering of
  concurrent agent writes.

Licence note: emd-renderer is MPL-2.0, file-level copyleft — a clean
dependency for GPL-3 ymacs. No licence conflict in owning buffers this way.

### 1.2 Window — the viewport, plus a component set

A window is a tile over a buffer, as in Emacs (split, resize, balance,
other-window — all parity). The ymacs superpower: **a window carries a set
of components** chosen by its buffer's major mode and its own minor modes:

| Component     | Surface                              | Example: org-mode            | Example: gdb-mode            |
|---------------|--------------------------------------|------------------------------|------------------------------|
| Sidebar body  | libyggterm rail (`AppPaneRailBody`)  | search box + speed nav (headings, TODO, agenda) | breakpoints, frames, locals, watch |
| Palette       | yggui command palette                | M-x, `org-babel` block runner | M-x, `gud` command completions |
| Titlebar      | yggterm row titlebar segments        | heading breadcrumb, TODO state toggle | target/pid, running/stopped |
| Footer        | modeline (footer widget)             | current headline, clock      | signal, thread               |

Laws:

- **Buffer-local modes stay buffer-local** (`M-x org-mode` behaves exactly
  as Emacs). Components are **window-scoped** additions derived from the
  focused window's major mode + that window's minor modes. The same org
  buffer in two windows may show different component sets.
- **The sidebar is the window's component, not a second editor.** Max ONE
  sidebar in view per frame (the v0 single-sidebar law stands). Its *content*
  follows frame focus: whichever window is focused donates its sidebar body.
- **The titlebar is mode-claimed.** Major and minor modes that want it
  declare titlebar segments (text, toggles, actions). ymacs core claims
  nothing by default beyond buffer name and dirty state. No mode → no
  segments.
- **The command palette is a window component.** See §3 for the M-x law.

In Emacs vocabulary: everything Emacs does by *splitting the frame* or
* popping a temporary buffer* (`*Completions*`, `*Help*`, `*Buffers*`) ymacs
does by *component*. Temporary-window behavior remains available as parity
fallback (`display-buffer` contracts honoured), but no ymacs facility
*requires* stealing viewport.

### 1.3 Frame — a yggterm row

Owner directive: **a new frame IS a new yggterm row from ymacs.**

- `make-frame` / `C-x 5 2` spawns a new yggterm row (its own OSC 7717
  declare: viewport document + rail), attached to the same daemon.
- The daemon owns buffers and state (the emacsclient model, already
  v0-real); **frames are cheap clients over the control server**. A frame
  can live on another host's yggterm — remote frames are just rows whose
  daemon is reachable over SSH, matching the yggterm decentralized-host
  architecture.
- Frame parameters map to row properties: `name` → row title, `titlebar`
  segments (§1.2), visibility → row presence. Deleting the last frame of a
  client is `--close`; the daemon survives, exactly like emacsclient.
- `C-x 5 f/o/0/1` map onto rows: find-file-other-frame opens the file then
  focuses/creates the row, `delete-frame` closes the row, etc.

### 1.4 Minibuffer and echo area — parity, with a new renderer

The minibuffer *state machine* (prompt, input recursion, history M-p/M-n,
`completing-read` protocol) stays Lisp-side and Emacs-shaped — packages
calling `completing-read`/`read-from-minibuffer` must work. What changes is
the *view*: the echo area renders as the footer/modeline; heavy completion
UIs (the candidate list) render in the **command palette component**, never
by splitting the window.

## 2. Surface inventory — what ymacs ships beyond stock Emacs

| # | Surface        | Carrier                                   | Who claims it                       | Emacs analogue (absent → ymacs extra)          |
|---|----------------|-------------------------------------------|-------------------------------------|------------------------------------------------|
| S1| Viewport doc   | emd-renderer document surface (OSC 7717 `viewport`) | the window's buffer + emd        | the text terminal grid                         |
| S2| Sidebar rail   | `AppPaneRailBody` contributed pane        | window major/minor modes (§1.2)     | — (Emacs splits windows instead)               |
| S3| Command palette| yggui palette component                  | window; fed by the command layer    | `M-x` + `*Completions*` split                  |
| S4| Titlebar       | yggterm row titlebar                      | window major/minor modes (mode-claimed) | —                                           |
| S5| Modeline       | footer widget                             | core + modes                        | mode-line (parity)                             |
| S6| Frame=row      | yggterm row per frame                     | core                                | an OS window                                   |

No mode may draw custom chrome: every surface is a yggui-contract widget
(text-input, list-row, section, tabs, footer) — the v0 rule stands.

## 3. The command layer and the M-x law (macro safety)

Owner directive: M-x uses the palette, and **keyboard macros that use M-x
must work, no problems**. The law that makes both true:

1. **Commands are named Lisp functions with Emacs `interactive` specs**
   (prompts, prefix-arg codes). The command layer resolves
   name → symbol → interactive spec → invocation, exactly the shape
   `execute-extended-command` has in Emacs. The v0 `find-symbol`-and-funcall
   is a placeholder to be replaced by this layer.
2. **M-x is a view over the command layer.** The palette lists commands
   (fuzzy, orderless-style), collects the interactive prompt answers, and
   *invokes the command through the layer*. The palette is never the source
   of truth for what ran.
3. **Macros record command invocations, not gestures.** `C-x (` … `C-x )`
   records the sequence of *executed commands with their arguments*
   (`(execute-extended-command "org-todo" prefix-arg)` records
   `org-todo` + args). Palette typing, sidebar clicks, and focus changes are
   NEVER recorded. Consequences (all required):
   - A macro recorded via M-x replays identically **headless**
     (`ymacs --eval`) with no palette, no surfaces, no frame at all.
   - Palette UI changes can never break recorded macros.
   - The v0 recorder (which records nothing — `*last-kbd-macro*` is never
     appended) is replaced by a recorder that hooks the command layer, the
     single choke point every input path funnels through.
4. Self-insertion and motion keys record as their commands too
   (`self-insert-command`, `next-line`, …), which is precisely how Emacs
   makes macros replayable — we keep the same property, not necessarily the
   same key-string form.
5. `C-x e`, `C-x (`, `C-x )`, `name-last-kbd-macro`, `insert-kbd-macro`
   keep Emacs semantics; `insert-kbd-macro` emits a form that replays via
   the command layer.

## 4. Configuration — no million faces, VSCode-style layering

Owner directive: sane choices; Emacs's thousand faces are NOT shipped.

- **Defaults:** the shipped `init.org` — the literate book. It is the
  default configuration, human-readable, tangled at start.
- **User overrides:** `~/.yggterm/ymacs/user.org`. Users edit ONLY this
  file. Layering is defaults ← user overrides (VSCode's settings design:
  immutable defaults, a single override file, predictable precedence).
- **Theme tokens, not faces:** ymacs ships a small closed set of semantic
  tokens (font, accent, modeline, region, …) mapped onto yggterm themes.
  A bounded `face→token` shim translates package face requests onto tokens;
  unknown faces get the default token. Face explosion is impossible by
  construction.
- **`M-x settings`:** opens a **dual-window settings system**: the sidebar
  is the fast navigation column (GNOME-settings style sections: Appearance,
  Editing, Keybindings, Modes, Packages, About), the window shows the
  selected section as a settings document. Changing a setting writes the
  override into `user.org` (the file stays hand-editable; settings UI and
  file are two views of one store). The settings schema is declared in org
  properties, so the UI is generated from the schema, not hand-mirrored.

## 5. Honest status ledger (state at this spec's writing)

What the v0.1.x wave *actually* delivered (verified 2026-09-02 by audit):

- **Real:** daemon/client split with endpoint-ping liveness; OSC 7717
  declare/close; control server with `/ping`, `/pane/*`, `/open`,
  `/action`; sidebar panes (buffers, outline, which-key, project);
  rope/gap buffer core with value_key session persistence; kill-ring,
  undo, isearch, folding, multiple-cursors modules (unit-level, no key
  input plane yet); org tangle of `init.org`; headless `--eval` verbs;
  ytrace probes; manifest; SBCL/ECL build + CI.
- **Real since 2026-09-02 (command layer unit):** named commands with
  interactive specs (`defcommand`), prefix arguments, `command-execute`
  choke point, real `execute-extended-command` (M-x), and the keyboard
  macro law — record invocations, never gestures; headless replay;
  no re-recording. Contract-tested: `tests/command-tests.lisp` (10
  tests, run in CI).
- **Skeleton / not yet real (do not claim):** no keystroke input plane
  (input arrives only as sidebar `/action` posts; the command layer is
  reachable from the palette and headless verbs, not from keys yet);
  `projectile`/`magit`/`treemacs` are name-only stubs; the "90% ELPA/
  MELPA" figure is a *target*, not a measurement; the manual's
  "Deep Dive N" appendix was template padding (removed with the
  2026-09-02 manual rewrite).
- **Headless verbs fixed (2026-09-02):** the `--eval` client never
  terminated its HTTP headers (POST format string lacked the blank
  line before the body since the Tier-A commit) — every `ymacs --eval`
  hung until killed; the daemon-spawn wait also grew 5s→15s because the
  39MB core restore misses a 5s window on loaded hosts. Found while
  live-verifying step 6; SBCL's compile-time format checker now holds
  the arg count open.
- **The rebuild order that satisfies this law** (next sessions):
  1. ~~Command layer~~ ✅ done.
  2. ~~Macro recorder at the command layer + headless replay test~~ ✅ done.
  3. ~~Key input plane~~ ✅ done (ymacs f9781d3 + yggterm 66eb48810).
  4. ~~Command palette view~~ ✅ done (2026-09-02): the MINIBUFFER is the
     palette — a Lisp state machine rendered as document-surface widgets
     (prompt section + search field + selected candidate rows), fed by the
     key plane. It is the GENERIC interactive-argument collector: any
     command whose spec needs an unsupplied value opens it (C-x C-f
     prompts "Find file: " exactly as Emacs); M-x is the command-name
     read. Orderless-style filtering, C-n/C-p/arrows/RET/TAB/C-g, mouse
     clicks accepted, C-u prefix. Palette keys mutate palette state and
     are never recorded — the invocation through the choke point is,
     with its collected arguments, and replays headless.
  5. ~~Frame=row (make-frame → row)~~ ✅ done (2026-09-02): make-frame
     spawns a yggterm row (`terminal new --kind shell --title ...`) and
     launches the ymacs client in it — the client attaches to the same
     daemon (emacsclient semantics). Live-verified end to end: the eval
     verb answers the row path; the row appears in yggterm; delete-frame
     closes the surface and leaves the row. Latent defects fixed on the
     way: the /action eval arm never existed (every --eval no-opped),
     JSON string values were not unescaped, signal handlers died on the
     first SIGHUP (1-arg lambda vs SBCL's 3-arg invocation), and
     run-daemon exited on a single loop error.
  6. emd-renderer ownership ✅ done (2026-09-02):
     - The plain-text (ASCII) surface moved into `emd-renderer` as
       `TextSurface` (libyggterm 3a74342): the degenerate one-block
       document — byte-faithful splices, Emacs line math, loud
       char-boundary failures. The Dioxus render of it stays in the
       shell per that spec's own deferred seam (spec-emd-renderer §4,
       migration item 4) — the MODEL is what no app may re-derive.
     - Org constructs are typed nodes in `emd-renderer`'s `org` module
       (headings with a keyword slot, src blocks, drawers, checkbox
       items, tables, visible Text remainder; leaf ranges tile the
       source; `cycle_todo`/`toggle_checkbox` splice byte-exactly).
     - ymacs org mode animates the contract from the Lisp side
       (line-addressed nodes, same parse decisions, contract-locked by
       the same fixtures — tests/org-tests.lisp, 14 tests in CI):
       org-todo cycles none→TODO→DONE→none through command-execute
       (macro law holds), org-checkbox-toggle flips in place, C-c C-c
       is contextual (checkbox else tangle), C-c C-n/C-p navigate,
       the Outline sidebar rows are node-driven and goto-line moves
       buffer point. Live-verified headless against the daemon:
       TODO cycle end to end + checkbox toggle on a real file.
     - Still v0 (honest): folding is point-motion only; agenda scans
       lines, not nodes; workflow keywords are the stock TODO/DONE
       pair until step 7's settings system carries user workflows.
  7. Settings system (schema org store, dual-window UI, user.org writer).
  8. ELPA compat depth measured by a public test corpus (replace the
     "90%" target with numbers).

## 6. Documentation law — the vendored Emacs manual and divergence markers

- The Emacs manuals (Texinfo sources) are vendored under
  `docs/emacs-manual/` (GFDL-1.3-or-later, same licence as ymacs docs; see
  that directory's README for provenance and pin).
- `docs/emacs-manual/divergences.org` is the **divergence ledger**: one
  entry per deliberate divergence or extension, citing the Emacs manual
  node it diverges from, the reason, and the compat cost.
- `docs/manual.org` marks every chapter with one of:
  `[parity]` — behaves as Emacs; `[ymacs extension]` — additive surface
  Emacs lacks; `[divergence #N]` — deliberate deviation, ledger entry cited.
  Anything unmarked is a bug in the manual.

## 7. What this spec does NOT cover

- The ELPA compat layer's per-package matrix (tracked in
  `docs/elpa-melpa-compatibility.md`, to be re-based on measured results).
- yedit's migration onto the moved surface (its own campaign; the seam
  contract is §1.1).
- Multi-host frame placement mechanics (needs a yggterm-side spec; only the
  frame=row law is fixed here).
- IP/licence questions beyond the MPL note in §1.1 (fingraph owns those;
  ymacs register rows already exist in the IP register).
