;;;; spec-rendering.md --- THE RENDERING LAW: raw and rendered (DECIDED)

Status: DECIDED 2026-09-10 (owner directive "decide first"; consult:
gemini-3.8-flash-high via agy, verdicts accept-with-corrections x4 —
chain node lores/chain-of-thought/2026-09-10-ymacs-rendering.md; this
file is the SSOT). Supersedes the "buffers are emd-renderer's"
aspiration of spec-primitives.md §wherever they conflict in mechanics;
the aspiration's SPIRIT (buffer text is a document) is preserved: the
buffer keeps the true text, rendering is a PROJECTION.

## 0. The decision in one paragraph

A ymacs buffer has exactly ONE rendering state: a buffer-local Emacs
MINOR MODE, `rendered-mode`, auto-enabled for buffers whose major mode
declares a rich parser, wrapped by the Emacs-idiomatic global minor
mode `global-rendered-mode` (on by default). Raw text is `rendered-mode`
nil — there is no second mode object (two dueling globals is the
anti-pattern Gemini rebutted: an invalid state space both-true/both-
false and no per-buffer autonomy). Capable major modes register a
`prose-producer` closure mapping buffer content to CommonMark; emd IS
CommonMark (emd-renderer parses markdown), so markdown is the wire.
The schema emits the shell's EXISTING `markdown` widget (the Document
reader surface, yggui::prose) when rendering is on, else today's
multiline text-input byte-for-byte. Sensible defaults, zero config:
Info reads rich, org reads rich, code and plain files stay text; the
Emacs ceiling stays: keys drive commands through key_capture even in
rendered view, M-x rendered-mode toggles, the mode line names it, and
starting to TYPE in a rendered buffer drops to raw for editing.

## 1. Taxonomy (the owner's sketch, resolved to the Emacs idiom)

- `rendered-mode` — buffer-local minor mode. ON: the buffer projects
  through its major mode's prose producer; OFF: raw text. Auto-enabled
  at `set-buffer-major-mode` when the mode declares `:rich-parser`.
- `global-rendered-mode` — global minor mode, default ON: enables
  `rendered-mode` in every capable buffer, present and future.
- Precedence: standard Emacs minor-mode semantics — an explicit
  buffer-local toggle wins over the global; a major mode with no
  `:rich-parser` can never render rich (rendered-mode is inert there).
- Mode line: capable buffers show `Rendered` or `Raw`; incapable
  buffers show nothing (no noise). The mode line rides the ribbon
  strip label (D12).
- Toggle surfaces: `M-x rendered-mode` (palette), the ribbon
  `[Rendered | Raw]` button group on capable buffers, and — the modern
  default — typing into a rendered buffer auto-drops to raw first
  (message says so), because reading rich and editing raw is the
  VSCode-shape muscle memory without a single new knob.

## 2. The producer contract (major modes declare; markdown is the wire)

- `define-major-mode` grows `:rich-parser FN` — FN is
  `(lambda (buffer) string)` returning CommonMark.
- Buffer slots (buffer struct): `prose-producer` (the closure or nil),
  `prose-cache-tick`, `prose-cache-value`. Emission: if cache tick is
  stale, re-run the producer, refresh the cache. Info views: the tick
  is the view's node-generation (nav keys do NOT reparse — the cache
  is keyed per node switch, zero reparsing on the loopback).
- `info-mode` → `info-buffer-markdown`: node name becomes `# Name`,
  the header spine becomes a links line
  (`[n Next](info:Target) · [p Prev](info:Prev) · [u Up](info:Up)`),
  `* Menu:` entries become a list of `[label](info:Node)` links, and
  `*note X::Y` cross references become inline `[Y](info:X)` links —
  all from the parse info.lisp ALREADY does (no new parser).
- `org-mode` → `org-buffer-markdown` v0: headings, lists, tables,
  blocks, `[[file:...][text]]`/`[[url]]` links. This is the SEED of
  build-order step 6 (org typed nodes): richer interactivity (TODO
  cycles inside the view) stays step-6 work, sequenced after this wave.
- Everything without a producer (fundamental files, lisp, python, c,
  dired, eshell, scratchpad): text, unchanged. The owner's "files do
  not inherit emd-renderer" is exactly this; a future markdown-mode
  declares a producer and instantly reads rich.

## 3. Keys, links, and the reading surface

- `key_capture` stays on in rendered view: n/p/u/t/s/l/q and the rest
  of the keymap keep working — commands, not text events. In rendered
  info view, TAB/S-TAB cycle the menu entries (the Emacs Info TAB
  habit; the echo names the entry) and RET follows the selected one.
- Mouse: link clicks POST back per the shell `links_action` contract —
  `{"action":"follow-link","values":{"href":"info:Target"}}` — routed
  to `info-select-node` (http/mailto hrefs message, never launch).
- The buffer is the document: point/mark/undo live on the RAW text.
  The markdown is a view. Editing while rendered auto-drops to raw
  (§1), so no edit ever lands in a projection (D11).

## 4. Schema emission and capability (deploy law)

- Emission switch: `(and (rendered-mode-p buf) (buffer-prose-producer
  buf))` → `markdown {id: "rendered-view", source: md, read_only: true,
  links_action: "follow-link"}`; else today's text-input, byte for byte.
- The `markdown` widget kind ALREADY EXISTS in every deployed shell
  (the Document reader). New FIELDS (`read_only`, `links_action`) are
  serde-default: old shells ignore them (links inert, click-to-edit
  present), new shells honor them. No pane-death path exists; the
  strict-parse fatal (unknown KIND) is never tripped. Shell-first
  deploy to jojo still precedes the flip so links + read-only work on
  day one.
- user.org kill switch: `rendering.default = rendered | raw` (default
  rendered) — one setting, consulted by `global-rendered-mode`.

## 5. The mode line in the ribbon (D12, same wave)

- ymacs: the ribbon label now carries the mode names:
  `*info: ymacs*  Info Rendered • 21 lines [C-h-]`.
- Shell: ribbon labels get `min-width:0; overflow:hidden;
  text-overflow:ellipsis; max-width:40%` — the strip never clips again.
- The ribbon `[Rendered | Raw]` button group (right-aligned) is the
  mouse path to `M-x rendered-mode`.

## 6. Divergence ledger

- D11: capable buffers render as prose by default; rich view is a
  projection — editing happens in raw text (auto-drop), unlike GNU's
  text-grid-with-faces everywhere.
- D12: the mode line lives in the ribbon strip, not a text modeline.

## 7. Deliberately out (foresight, not omission)

Editing inside the rendered view; org TODO interactivity in the
projection; magit/dired rich surfaces; user faces (the no-million-faces
law — the prose ink is the shell's design system). Named future work:
the host capability handshake (Gemini's `#[serde(other)]` fallback card
and feature flags) belongs to the yggterm campaign; proposed on the
board, not built here.

-- zcode seat jojo, 2026-09-10, owner-directed, gemini-consulted.
