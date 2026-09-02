# ymacs Key Plane — the key-event channel and the key dispatcher

Contract spec for build-order step 3 (see [[file:spec-primitives.md]] §5).
Landed with the command layer (828b58a), the command side of this plane is
ready: keys must now reach `command-execute`.

## 1. The gap

No libyggterm surface carries key events today. yedit's input is a value-
posting `text-input` widget (keystrokes land in the DOM textarea; a
debounced ~2.5s draft sync posts the whole value). An Emacs-compatible
editor cannot work that way: it needs **per-keystroke dispatch** (C-n,
C-x C-f, M-x, self-insert) at interactive latency.

## 2. The contract — schema-declared key capture (Tier C, one door)

The vocabulary is yggterm's (libyggterm-surfaces §Tier C): a document pane
schema may declare:

    {"title": "...", "widgets": [...], "key_capture": true}

Semantics, precisely:

1. **Scope.** While THAT document pane is the active visible surface,
   keydowns are forwarded to the app instead of driving native input.
   The declaration is per-surface, never global — a key_capture surface
   on one row cannot eat keys anywhere else.
2. **The door.** Key events ride the EXISTING action POST:
   `POST <control>/action` with
   `{"pane": <pane_id>, "action": "key", "values": {"key": "<chord>"}}`.
   No new endpoint, no new transport — the same loopback `ssh -L` forward
   carries it for remote daemons, and the reply may carry `schema` (the
   per-keystroke render) exactly like any action.
3. **Chord spelling** (one event per POST; the APP owns sequences):
   - Modifiers as Emacs prefixes, in order `C-` `M-` `S-`:
     `C-f`, `M-x`, `C-M-f`, `C-S-u`.
   - Character keys spell the produced character; Shift on a printable
     key is the character itself (`A`, `?`), never `S-a`.
   - Specials: `TAB` `RET` `SPC` `DEL` `ESC` `<up>` `<down>` `<left>`
     `<right>` `<home>` `<end>` `<prior>` `<next>` `<delete>` `<f1>`…
     `<f12>`.
   - Modifier keys alone (pressing Ctrl) forward nothing.
4. **What stays shell-owned.** GTK-level accelerators never reach the DOM
   (session nav, ALT+ KeyTips). The shell's DOM-level chords keep their
   existing precedence: `Ctrl+Shift+P` (search focus) stays shell; the
   key-capture arm sits AFTER it and BEFORE the browser-only `Ctrl+F`
   arm and the preview PageUp/Home/End arm, so an editor gets `C-f`,
   `<prior>`, `<next>` and friends.
5. **Rollout safety.** The field is `serde(default)`; an older yggterm
   ignores it and the app keeps working through buttons/verbs — declare
   first, degrade to the pre-key behaviour.
6. **One door.** Only the root keydown forwards. Rail panes do not
   forward keys (a search box in a rail keeps native input); the
   keydowns of the shell's own inputs never reach the arm (they stop
   propagation today, and the arm additionally ignores events whose
   target is an editable field).
7. **Ordering.** Replies apply through the document pane's existing
   request-seq guard, so a fast typist's out-of-order replies cannot
   paint a stale buffer.

## 3. The ymacs dispatcher (the other half)

`src/ui/keyboard.lisp` — the Emacs input loop over that channel:

- `ymacs-handle-key chord` appends to the pending key sequence
  (`*key-sequence*`), then: exact binding in the major-mode map, else
  global map → `command-execute` (recording, per the macro law — a
  key-invoked command is a command invocation); else a binding that
  *starts with* the sequence → keep pending (echo in the doc pane);
  else reset (undefined).
- `self-insert-command`: a printable character with no `C-`/`M-`
  inserts at point and advances it. Macros record it like any command,
  which is what makes replay type text.
- Movement commands (`C-n` `C-p` `C-f` `C-b` `C-a` `C-e`) operate on the
  buffer at point; the reply schema re-renders the editor.
- `M-x` without an argument supply announces that the palette component
  (step 4) is its collector; the command layer and headless M-x already
  work.
- The key action handler answers with the fresh document schema, so one
  loopback round trip per keystroke renders the result — no dependence
  on the ~4s heartbeat.

## 4. Known v0 limitations (honesty law)

- The caret visible in the editor field is the DOM's; `point` is the
  app's. Per-keystroke remount shows the buffer text correctly but does
  not yet place the caret at point.
- No key repeat coalescing, no IME composition, no mouse point-setting.
- The editor widget remains a `text-input` render; a purpose-drawn
  monospace buffer surface (emd-owned, spec-primitives §1.1) supersedes
  it in step 6.

## 5. What this does NOT cover

- Rail-pane key capture (a gdb pane wanting `F5`): same mechanism,
  admitted later by the same contract when an app needs it.
- The yggui command palette component (step 4) — the M-x VIEW.
- Held-ALT app chords on native web surfaces (KeyTips §3.0.0 work).
