# spec-agent-fs — the ymacs agent filesystem (acme-shaped)

**Status: PROPOSED — design-shaped 2026-09-12, zero implementation.** Nothing
in this document is shipped; phases below are the landing order when GO is
ruled. Design consultations: fleet chain-of-thought entries
`0014-ymacs-acme-fs-api` and `0015-ymacs-acme-fs-mount` (gemini-3.8-flash
HIGH verdicts absorbed; the two load-bearing corrections — path-encoded
revisions and the buffer/window split — are this spec's spine). This is a
[ymacs extension]; a manual.org chapter follows only when productized.

## 1. Goal

Give Plan 9 acme's superpower to ymacs: **the editor's live state is a
filesystem**, so `cat`, `awk`, `sed`, `grep`, `diff` — every tool an agent
already speaks — shape editor state with zero client library and zero new
verbs. External programs become *peers* of the editor, not plugins.

Non-goals (each a deliberate rejection):

- **No 9p server in the daemon** — kernel 9p mounts need `CAP_SYS_ADMIN`;
  agents run unprivileged. Deferred permanently, not indefinitely. FUSE via
  `fusermount3` is the sanctioned mount path.
- **No daemon-side shell execution** — acme's `|cmd` runs arbitrary commands
  inside the editor; here that is an RCE hole *and* wrong (the agent host has
  the toolchains — ruff, cargo, venvs — the GUI host does not). Pipes execute
  agent-side.
- **No keystroke events** — token burn, secret leakage, contradicts the M-x
  macro law. Command-level events only.
- **No silent merge** — a text-level auto-merge inside a code buffer corrupts
  invisibly. Reject-on-stale, or explicit force.
- **Raw `eval` stays an owner escape hatch**, never the agent surface.

## 2. The tree

Opaque stable ids everywhere: buffers are `b<N>`, windows are `w<M>` —
**never names in paths** (buffer names carry `*`, spaces, slashes). Ids are
never reused within a daemon run. A dead id is ENOENT/404.

```
<root>/                              FUSE: ~/mnt/ymacs/   HTTP: /fs/…
  index            one TSV line per buffer:  bid TAB rev TAB dirty TAB path TAB wins
  events           backlog, newest last:     "<seq>\t<type>\t{json}" per line
  plumb            write-only: "path[:line[:col]]" → jump-or-open
  ctl              write-only global verbs:  open <path> · focus <win>
  buffers/
    b3/
      body         whole buffer text. read = snapshot; write = force (LWW)
      body@89      read at 89; write commits If-Match: 89 → EBUSY/409 if stale
      by-rev/89/body         alias of body@89 (for globs: body@* )
      revision     "89\n"
      props        key: value lines (name, path, mode, dirty, rev, lines, windows)
      ctl          write-only buffer verbs (below)
  windows/
    w1/
      buffer       → ../../buffers/b3     (pass-through; the window's buffer)
      body         → buffer/body          (read what the human is looking at)
      dot          the display selection as an addr; read and write
      ctl          write-only: show (scroll dot into view) · close · split
  by-name/
    *scratch*      → ../buffers/b1        (URL-escaped buffer names; tab-completion door)
```

The window tree exists because Emacs has background buffers acme never did:
50 buffers live, 2 windows tiled. Content hangs off **buffers** (identity +
revision), display hangs off **windows** (dot, visibility, focus); a pair of
windows on one buffer can never split-brain the content. `index` and
`by-name/` are the discovery surfaces; the TSV index is deliberately not
JSON — `awk -F'\t' '$3=="true" {print $1}'` must work cold.

### 2.1 Formatting law (spaces lie)

Every file is **line-oriented plain text first**; JSON is an alternative
representation (`?format=json` over HTTP), never the only one. `index` is
strict TSV (buffer names contain spaces). `props` is `key: value` lines.
`events` lines are `<seq>\t<type>\t{json}` so high-volume tails filter with
`grep`/`cut` before any JSON parsing.

### 2.2 The addr grammar (v1)

```
addr := term | term "," term          range from term to term
term := [0-9]+          line number (1-based)
      | "#" [0-9]+      character offset
      | "/" ere "/"     next match of POSIX ERE (grep-compatible)
      | "dot"           the window's selection (window-scoped ops only)
```

Units are **characters** (the buffer is char-indexed), not bytes. Regexp is
POSIX ERE — grep-compatible is the point; this is a documented divergence
from Emacs regexp syntax, entering the divergence ledger at implementation
time. Line-end padding, `+`/`-` relative terms, and compound addresses are
OPEN questions for the implementation wave; v1 ships the grammar above only.

### 2.3 Writes and the revision contract

Every buffer mutation is guarded by the buffer's `value_key` revision
(OCC). The mount exposes the guard **in the path**, because bash gives you
no headers:

- `body@<rev>` (and `ctl` verbs carrying `<rev>`) commit `If-Match: <rev>`.
  Stale → `EBUSY` (mount) / `409 {"current_value_key": …}` (HTTP). The
  caller re-reads, re-applies, retries — the retry loop is the design, not a
  wart.
- Plain `body` write is **force/LWW by contract, documented as such** — that
  is what `cp t body` must mean. Agents that care use `@rev`; humans who
  type `cp` get clobber-rights.
- **Why path-encoded revisions:** a pipeline's stages are separate processes
  with separate fds. fd-lifetime revision arming is an illusion — `cp` would
  arm against the *latest* revision and silently wipe the human's edit. The
  revision must survive process death in the path: `REV=$(cat b3/revision)`
  … `cp t b3/body@$REV`. (Consult 0015 S2, the round's key correction.)
- `ctl` verbs, payload on stdin: `replace <addr> <rev>`,
  `patch <rev> <addr>` (unified-diff hunk), `save` (write buffer to its
  visited file), `kill`. Header-free — `echo "replace /defun foo/,/^}/ 89" >
  b3/ctl < payload` pipes straight in.

### 2.4 Events

One global stream, monotonic `seq`, bounded ring (~10k). Emitted at the
`command-execute` choke point (the macro recorder's own vantage) plus buffer
lifecycle hooks:

```
1042	command	{"ts":…,"win":"w1","buf":"b3","name":"find-file","args":["foo.lisp"],"origin":"human"}
1043	delta	{"ts":…,"buf":"b3","op":"replace","addr":"#812,#900","rev":90,"origin":"agent:zcode-jojo"}
1044	lifecycle	{"ts":…,"buf":"b3","event":"save","rev":91}
```

HTTP access: `?cursor=<seq>&limit=` (poll), `&wait=<s>` (long-poll),
`stream=true` (SSE). Mount: reads return backlog from a cursor file the shim
keeps; `ymacs watch -f` is the `tail -f` shape. `origin` carries provenance
(`human` or `agent:<id>` from the `X-Ymacs-Agent` header), and every write's
`delta` lands here — the event stream is the audit log.

### 2.5 Plumb

`echo "src/core/buffer.lisp:197:10" > ~/mnt/ymacs/plumb` — any linter, test
failure, or grep hit can drive the editor statelessly. Daemon resolves
path→buffer (open-or-focus), jumps, returns the window id. This is the
cheapest possible integration for the whole fleet's tooling.

## 3. Transport layering

```
        ┌── CLI: ymacs cat/addr/write/patch/pipe/watch   (any host, over ssh, day one)
daemon ─┼── FUSE: ~/mnt/ymacs via ymacs-mount shim        (agent-host-local)
HTTP ───┤
tree    └── audited intents via ygg_appctl/bridge        (external GUI harnesses)
```

- The daemon stays a **stateless atomic HTTP engine**. All POSIX state
  (fds, read-chunk buffering, snapshot-at-open, `@rev` path parsing) lives
  in the agent-side shim; a crashed mount leaves zero state behind.
- **Snapshot-at-open on reads:** open() fetches body+revision once and
  serves the fd from that snapshot — `awk` sees a consistent file even while
  the human types. (The read half of checkout/commit survives consult 0015;
  only the write-arming half was rebutted.)
- `ymacs-mount` is a small zero-dependency shim (fusepy/ctypes over
  libfuse3, or a static Go/Rust binary — not a pyfuse3 dependency tree),
  user-mounts via fusermount3, base URL configurable → ssh-forwarded daemon.
- `ymacs pipe b3 --rev $REV -- awk '…'` is the client-side `|cmd` shape:
  GET, pipe locally through the agent's own toolchain, PUT with If-Match.
- External GUI harnesses (zcode seats) go through audited appctl intents,
  never raw cross-host HTTP — same audit plane as row control.

## 4. Security

Phase 0 exists because **the current control server is an unauthenticated
loopback RCE**: `POST /action {"action":"eval"}` executes arbitrary Lisp for
any local process, or any browser tab via DNS rebinding. This retrofit is
worth landing regardless of the fs decision.

- High-entropy token at `~/.yggterm/ymacs/control.token` (0600), generated
  at first daemon start; `Authorization: Bearer` on every request; CLI, shim
  and appctl layer read the file automatically.
- Bind loopback only; no network-exposed socket, ever.
- Thread pool + socket timeouts + capped concurrent streams on the control
  server (thread-per-connection + long-polls = thread exhaustion).
- `X-Ymacs-Agent` provenance header on all mutations, logged to ytrace and
  the event stream's `origin`.
- inotify (or polling fallback) on visited files: out-of-band disk edits
  invalidate the buffer's revision and emit `lifecycle` events — buffers and
  disk must not diverge silently.
- No daemon-side command execution surface is added by this spec (no `|cmd`).

## 5. Worked examples (the acceptance bar)

```bash
# awk over a live buffer, OCC-guarded across two processes
REV=$(cat ~/mnt/ymacs/buffers/b3/revision)
awk '/^(defun|defparameter)/ {…}' ~/mnt/ymacs/buffers/b3/body > t \
  && cp t ~/mnt/ymacs/buffers/b3/body@$REV          # EBUSY if human edited meanwhile

# grep UNSAVED buffers (impossible from a shell in stock Emacs)
grep -rn "value_key" ~/mnt/ymacs/by-name/*/body

# diff live buffer vs disk
diff -u ~/proj/foo.lisp ~/mnt/ymacs/by-name/foo.lisp/body

# linter/test-failure jumps, statelessly, from any tool
echo "src/core/buffer.lisp:197:10" > ~/mnt/ymacs/plumb

# dirty-buffer census in one line, no JSON parser
awk -F'\t' '$3=="true" {print $1, $4}' ~/mnt/ymacs/index

# guarded range patch with the retry loop the design intends
ymacs patch b3 --rev 89 --addr '/defun foo/,/^}/' < fix.diff || ymacs patch b3 --rev $(ymacs rev b3) …
```

## 6. Phase order (when GO)

- **P0 — token auth retrofit** on the existing control server (live defect,
  independent of everything else).
- **P1 — core tree over HTTP:** index (TSV), buffers (body, body@rev,
  revision, props, ctl), addressed reads/writes with OCC, `ymacs`
  cat/rev/write/patch/pipe subcommands. This alone delivers the bash
  experience over ssh on every host.
- **P2 — events** ring + watch (poll/long-poll/SSE) + delta/lifecycle.
- **P3 — plumb + windows** (dot/ctl/by-name) + inotify invalidation.
- **P4 — `ymacs-mount`** FUSE projection. Starts only after P1–P3 verbs
  have real usage; the mount projects them, it invents nothing.
- **Deferred permanently:** 9p server, daemon-side `|cmd`, keystroke
  events, silent merge, network-exposed sockets.

## 7. Open questions for the implementation waves

- Relative/compound addr terms (`dot+3`, `/a/-2`); line-end padding rules.
- Undo integration: is an fs mutation one undo boundary? (Lean yes — an
  agent write should undo like a human command.)
- Does `eval` migrate behind the same token/auth (yes) and should it emit
  events (lean yes, type `eval`)?
- appctl intent vocabulary for external harnesses (map 1:1 onto the ctl
  verbs or expose the whole tree through a forwarding intent?).
- FUSE shim language (fusepy vs static Go binary) — decided at P4.
