# AGENTS.md — ymacs Engineering Contract

`ymacs` is a GNU Emacs fork built on **libyggterm**, implemented in **Common Lisp**.
It delivers a modern, ultra-snappy, deeply observable Lisp editing environment with **ELPA/MELPA compatibility that is measured, not claimed** (pinned GNU ELPA corpus: 1/75 files load, 41% of forms evaluate — [docs/elpa-compat-measurement.md](docs/elpa-compat-measurement.md)), discard-the-old modern defaults, and first-class agent orchestration.

**Repository licence: GPL-3.0-or-later (code), GFDL-1.3-or-later (documentation).**
Do not introduce contradicting licence claims anywhere in this repository. All documentation under `docs/` and manual sections follow the GNU Free Documentation License (with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts).

---

## 1. Core Architecture & Product Invariants

1. **Common Lisp Core on libyggterm:**
   - The engine is implemented in Common Lisp (SBCL / ECL / portable CL core), taking advantage of true native concurrency, fast compiled execution, and dynamic interactive image manipulation.
   - ymacs communicates with yggterm over standard **OSC 7717** byte streams and loopback HTTP control servers (`libyggterm-surfaces/SKILL.md`).
2. **ELPA & MELPA Plug-and-Play Compatibility (measured on a pinned corpus):**
   - Emacs Lisp evaluation layer (`src/elpa/compat.lisp`) provides emulation of Emacs Lisp primitives, macros, and standard library forms (`defcustom`, `use-package`, `add-hook`, buffer manipulation, keymaps).
   - Measured depth (step 8, 2026-09-04): **1/75 corpus files load; 797/1944 forms evaluate**. Method, tables and the ranked gap queue: [docs/elpa-compat-measurement.md](docs/elpa-compat-measurement.md). "Standard packages install with zero friction" is the goal, not a claim — the gap queue is the work.
3. **Modern Defaults by Construction:**
   - Instant startup (<15ms cold start to initial interactive frame).
   - Modern completion, fuzzy matching, smart parens, UTF-8 everywhere, clean modern typography, and sane indentation out of the box.
   - Archaic Emacs defaults (cluttered UI bars, cryptic prompt yes/no queries, synchronous blocking network calls, backup file pollution `*~`) are eliminated.
4. **Snappy, Async & Concurrent:**
   - Background tasks, package fetching, LSP indexing, and agent queries execute in asynchronous worker threads without stalling the main UI event loop.
   - Text editing core leverages the lock-free rope / gap-buffer concepts from `yedit` and the `emd-renderer` engine from `libyggterm` for high-performance buffer rendering.
5. **Built-in ytrace Observability:**
   - `ymacs` includes first-class `ytrace` probes across the entire lifecycle: buffer insert/delete latency, redisplay cycle time, GC pauses, Lisp form evaluation time, and OSC transport frame delivery.
   - Zero-overhead when dormant; deterministic microsecond tracing when attached.
6. **Bidirectional yggterm Dynamic Control:**
   - `ymacs` can dynamically query, spawn, split, and control `yggterm` terminals and agent sessions through Common Lisp interfaces.
   - Conversely, `yggterm` agents can evaluate forms, query buffer state, inject text, or switch workspaces deterministically via headless verbs and socket RPC.
7. **Literate `init.org` Book Configuration:**
   - Default user and system configuration is written in **Org mode (`init.org`)** structured like an interactive book with clear prose, architecture explanations, and executable blocks.
8. **The One-Sidebar Window Rule:**
   - Unlike classic Emacs where `*Buffers*` splits the main editing pane, `ymacs` delegates buffer lists, project trees, and org outlines to a **libyggterm sidebar panel**.
   - **Maximum sidebar in view is ONE** (maintaining Emacs's focused frame discipline).
   - Sidebars can be dynamically spawned and despawned via keybindings or Lisp commands (`M-x ymacs-toggle-sidebar`).
9. **Primitives Law (design SSOT — `docs/spec-primitives.md`):**
   - Frame / Window / Buffer, with Window and Frame superpowers: windows carry component sets (sidebar body, command palette, mode-claimed titlebar segments); frames are yggterm rows; buffers' content model is owned by `emd-renderer` (the ASCII text surface belongs there, shared with yedit).
   - **M-x macro law:** macros record command invocations with arguments — never palette/sidebar gestures; M-x replays headless.
   - **Config law:** defaults in shipped `init.org`, user overrides ONLY in `~/.yggterm/ymacs/user.org`; theme tokens, no face proliferation; `M-x settings` opens the dual-window settings UI.
   - **Divergences from Emacs are numbered** in `docs/emacs-manual/divergences.org` against the vendored Emacs manuals (`docs/emacs-manual/`, verbatim GFDL corpus — never edit those files in place).
10. **Honesty law:** no README/manual claim without a status anchor (`docs/spec-primitives.md` §5). Volume is not progress; the audit above was caused by exactly that failure mode.

---

## 2. Agent Interaction & Buffer Operations

- **Autonomous Agent Access:** Agents can inspect, edit, and evaluate buffer content without simulating human keystrokes.
- **Headless Verbs:** `ymacs eval "(buffer-string)"`, `ymacs open-file <path>`, `ymacs buffer-list --json`.
- **Draft Stability:** Like `yedit`, buffer edits maintain value-key identity to prevent focus jumping or clobbering concurrent agent writes.

---

## 3. Privacy & Public Repo Directives

- **Invent Every Example:** Sample paths (`/home/user/workspace/project`), hostnames (`example.org`), buffer names (`widget-engine.lisp`).
- **No Private Data:** Never commit private LAN IPs, real server credentials, real personal vault paths, or personal quotes.
- **Scratch Space:** Disk-backed `~/.yggterm/scratchpad/` on fleet hosts — never `/tmp` (tmpfs/RAM).

---

## 4. Verification & Testing

- Run test suites before every commit: Common Lisp unit tests (`(asdf:test-system :ymacs)`), ELPA compat tests, and headless surface verification.
- Always maintain clean git status and sign off commits (`git commit -s`).
