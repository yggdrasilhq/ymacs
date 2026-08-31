# ymacs

> **A GNU Emacs fork on libyggterm written in Common Lisp.**
> Modern defaults. ~90% ELPA & MELPA plug-and-play compatibility. Uncompromising speed, concurrency, and deep observability.

[![CI](https://github.com/yggdrasilhq/ymacs/actions/workflows/ci.yml/badge.svg)](https://github.com/yggdrasilhq/ymacs/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Docs: GFDL 1.3](https://img.shields.io/badge/Docs-GFDL_1.3-orange.svg)](LICENSE-GFDL-1.3)

---

## What is ymacs?

`ymacs` reimagines the timeless power of Emacs on a modern, ultra-fast substrate:
- **Common Lisp Core:** Compiled performance, true native multithreading, and interactive meta-programming on a modern Lisp runtime.
- **libyggterm Integration:** Runs seamlessly inside `yggterm` desktop and remote terminal sessions via OSC 7717, leveraging high-performance visual document surfaces and sidebars.
- **~90% ELPA & MELPA Compatibility:** Plug-and-play access to the vast Emacs Lisp package ecosystem.
- **Discard the Old:** No 1980s legacy clutter. Clean modern keymaps, instant sub-15ms startup, smart completion out of the box, and sensible defaults.
- **Deep Observability:** Built-in `ytrace` dynamic probes for measuring redisplay cycles, evaluation latency, and buffer mutations.
- **Bidirectional yggterm Orchestration:** Control yggterm terminals directly from Lisp forms, and let AI agents interact with live buffers deterministically.
- **Literate Book Init:** Default configuration is authored as an interactive Org mode book (`init.org`).
- **Single Sidebar Window Model:** Buffers, project navigators, and org trees live in a dedicated, collapsible sidebar rather than cluttering the editor pane.

---

## Quick Start

### Running ymacs
```bash
# Launch interactive ymacs session
ymacs

# Open file directly
ymacs path/to/file.lisp

# Open with specific literate configuration
ymacs --config ~/.config/ymacs/init.org

# Headless evaluation / agent execution
ymacs --eval "(+ 40 2)"
```

### Key Highlights

| Feature | Classic Emacs | ymacs |
|---|---|---|
| **Core Runtime** | C + Elisp bytecode | Native Common Lisp (SBCL/ECL) + Elisp compat layer |
| **Concurrency** | Mostly single-threaded / cooperative | True native multithreading & async task workers |
| **Surface** | X11 / Wayland / ncurses TUI | libyggterm Tier A document & sidebar surfaces |
| **Buffer Listing** | Splits main window into `*Buffers*` | Single collapsible sidebar rail (max 1 in view) |
| **Observability** | `elp.el` / profiler | In-process `ytrace` microsecond probes |
| **Agent Access** | Requires external socket / IPC hacks | First-class headless verbs and deterministic buffer RPC |

---

## Documentation

- [Architecture Overview](docs/architecture.md)
- [ELPA & MELPA Compatibility Guide](docs/elpa-melpa-compatibility.md)
- [Sidebar and Buffer Management](docs/sidebar-and-buffers.md)
- [Agent & Automation Contract](docs/agent-interaction.md)
- [Literate Book Configuration](init.org)
- [Agent Operating Contract](AGENTS.md)

---

## License & Legal

- **Source Code:** Licensed under the [GNU General Public License v3.0 or later (GPL-3.0-or-later)](LICENSE).
- **Documentation:** Licensed under the [GNU Free Documentation License v1.3 or later (GFDL-1.3-or-later)](LICENSE-GFDL-1.3) with no Invariant Sections, no Front-Cover Texts, and no Back-Cover Texts.
- **Third-Party Notices:** See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
- **Trademarks:** See [TRADEMARKS.md](TRADEMARKS.md).
