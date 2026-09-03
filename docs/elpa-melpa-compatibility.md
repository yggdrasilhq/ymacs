# ELPA & MELPA Compatibility in ymacs

`ymacs` targets plug-and-play compatibility with the Emacs Lisp ecosystem —
the *modern* stack, not the full historical archive — while retaining Common
Lisp's compiled speed, true concurrency, and ytrace observability.
**Measured depth (2026-09-04, pinned GNU ELPA corpus): 1/75 corpus files
load, 797/1944 forms evaluate — method, tables and the gap queue:
[elpa-compat-measurement.md](elpa-compat-measurement.md).**

## 1. How Compatibility Works

1. **Emacs Lisp Reader & Macro Expander**
   Reads standard `.el` files, converting Elisp symbols, scoping, and special
   forms into compiled Common Lisp equivalents.

2. **Buffer & Window API Emulation**
   `current-buffer`, `insert`, `delete-region`, `point`, `mark`,
   `save-excursion`, `with-current-buffer` map to native `ymacs` rope buffers
   with `value_key` stability.

3. **Keymap & Hook System**
   Emulates `define-key`, `global-set-key`, `add-hook`, `run-hooks`,
   `define-derived-mode`, `define-minor-mode`. Which-key is the canonical
   discovery UI (rail pane, not echo-area popup).

4. **Package Management**
   Compatible with `package.el` archive formats from ELPA/MELPA. The **only
   blessed declaration is `ymacs-use-package` (`use-package` in init.org)**.
   Packages are fetched async and byte-compiled in worker threads.

## 2. The Modern Helpers (Blessed)

Per owner steer (2026-08-31): ship the ultra-good modern helpers, discard the
old same-purpose duplicates. The packages that relied on the old ones are the
corpus that intentionally dies in v0.1 and will be shimmed later for 99.99%.

| Blessed (ships in image) | Replaces (discarded) | Notes |
|---|---|---|
| `vertico` + `consult` + `orderless` + `marginalia` | `ido`, `helm`, `ivy`, `swiper`, `smex`, `flx-ido`, `fuzzy` | Minibuffer completion |
| `corfu` + `cape` | `company`, `auto-complete` | In-buffer completion |
| `which-key` (rail pane) | `guide-key`, `which-key` echo popup | Pending-prefix overlay |
| `display-line-numbers` | `linum`, `nlinum` | Line display |
| `cl-lib` | `cl` (old) | Use `cl-lib` only |
| `project.el` + `xref` | older project navigators | Navigation |
| `use-package` | bare `require` / `package-install` loops | Declaration |

These are first-class: they register probes, which-key prefixes, and
`ylpm` features on load, and `ymacs-use-package` expands to them.

```lisp
(ymacs-use-package vertico :ensure t :init (vertico-mode 1))
(ymacs-use-package which-key :ensure t :config (which-key-mode 1))
```

## 3. Discarded Interfaces and Diagnostics

The following symbols are **intentionally absent** in v0.1. Requiring them
produces a clear diagnostic, not a silent void:

```
ido-mode, helm-mode, ivy-mode, company-mode, linum-mode,
cl, smex, flx-ido, guide-key, which-key-setup-minibuffer, quelpa, ...
```

A package that `require`s a discarded interface fails with:

> `ymacs: <feature> is a discarded old interface (replaced by the modern helper set...). The package requiring it is not loaded in v0.1; a shim will map 99.99% later.`

The shim (future) will map `helm -> vertico`, `company -> corfu`, etc., via
thin adapters that reuse the modern primitives.

## 4. Departures from Archaic Emacs

- Synchronous `url-retrieve-synchronously` runs async in background workers.
- `y-or-n-p` renders as rail chips, not minibuffer hijack.
- Backup files (`#file#`, `file~`) replaced by `~/.yggterm/ymacs/drafts/` WAL
  and `session.json` atomically.
- No `ido`/`helm`/`ivy` completion — vertico/consult is the path.

## 5. Corpus Definition

The v0.1 corpus is **vendored and pinned** under `vendor/elpa-corpus/`:
the blessed modern helper stack itself plus its foundation libraries
(seq, compat, map, dash, use-package, cape, corfu, consult, marginalia,
orderless, tempel, vertico — GNU ELPA, 2026-09-03). It is measured by
`src/elpa/corpus.lisp` on every test run; the numbers live in
[elpa-compat-measurement.md](elpa-compat-measurement.md) and the raw
data in `elpa-compat-measurement.json`. Widening to the full MELPA
top-download sampling described earlier comes after the pinned corpus
loads — no sampling past the files that fail today.
