# ELPA Compatibility — Measured (spec-primitives §5 step 8)

**Headline: 15 of 75 corpus files load fully (vertico 6, use-package 3,
corfu 3, compat-macs + compat-pkg + cape-keyword); 1664 of 2263 forms
(74%) evaluate.** The first measurement (2026-09-03) put this at 1 file
/ 797 of 1944 (41%) and retired the old "~90%"; the 2026-09-04 wave
then landed the definition-form family and the reader gaps it pointed
at. Re-run the instrument after every compat change and re-land the
numbers; a stale number here is the same failure mode the audit caught.

## The corpus

The blessed modern helper stack itself plus the foundation libraries it
builds on, vendored **verbatim** from GNU ELPA on 2026-09-03 (pin,
versions and tar sha256s: `vendor/elpa-corpus/README.md`):

seq 2.24, compat 31.0.0.2, map 3.3.1, dash 2.20.0, use-package 2.4.6,
cape 2.9, corfu 2.14, consult 3.7, marginalia 2.12, orderless 1.7,
tempel 1.14, vertico 2.13 — **75 top-level `.el` files**.

The question this corpus answers is the one the "~90%" claim never did:
*can ymacs load its own blessed stack?*

## Method (`src/elpa/corpus.lisp`, `src/elpa/elisp-reader.lisp`, `src/elpa/defmacros.lisp`)

Per file, a three-rung depth ladder:

- **0 READ** — the Elisp reader cannot read the file whole.
- **1 LOAD** — reads; at least one form fails to evaluate (missing
  primitive, unmet feature, load-time error).
- **2 PROVIDE** — every form evaluated and the file's own `(provide …)`
  ran.

The evaluator is the **shipped compat layer** (`src/elpa/compat.lisp`,
`src/elpa/defmacros.lisp`) bound under its Elisp names — never a
measurement-friendly fake; what fails, fails into the report. The only
measurement machinery beyond it: `require` resolves against the vendored
corpus (package.el semantics), provide is tracked per file, and each
measurement starts from a **scrubbed Elisp package** so run N's defuns
cannot answer run N+1's probes. Two features are **provided by the
shipped image**, not faked: `cl-lib` (CL itself is ymacs's cl-lib
implementation — `cl-defmethod` maps to `cl:defmethod`, `cl-incf` to
`cl:incf`) and `subr-x` (the `if-let`/`thread-first` macro family is
implemented for real in defmacros.lisp). `emacs-major-version` is
bound to 30 — the vendored manuals' version. SBCL's evaluator runs in
interpret mode (measuring 76 real packages under the compiler blew the
dynamic space), with a full sweep per package. Contract tests:
`tests/elpa-corpus-tests.lisp` — they assert the instrument's structure
and the definition macros' real semantics, never the corpus numbers.

## Numbers (measured 2026-09-04, corpus pinned 2026-09-03)

Raw data: `elpa-compat-measurement.json` (next to this file).

| depth | files | % of corpus |
|---|---|---|
| 0 READ — unreadable by the Elisp reader | 1 | 1% |
| 1 LOAD — reads, some forms fail | 59 | 79% |
| 2 PROVIDE — fully evaluated + provided | **15** | 20% |

- Forms evaluated: **1664 / 2263 (73.5%)**. (The form total grew from
  1944 because 8 previously-unreadable files now read — their forms
  count even when some fail.)
- Depth-2 files: **`compat.el` and `compat-macs.el`** (compat's own
  bootstrap and macro definitions — the honest cascade works),
  `use-package.el`, `use-package-jump.el`, `use-package-lint.el`,
  `cape-keyword.el`, `corfu-history.el`, `corfu-info.el`,
  `corfu-quick.el`, and six vertico support modes (`vertico-buffer`,
  `-quick`, `-reverse`, `-sort`, `-suspend`, `-unobtrusive`).
- Per-package forms-evaluated: consult 451/494, corfu 223/246,
  use-package 222/242, vertico 221/241, cape 124/135, marginalia
  144/150, tempel 70/73, orderless 68/73, seq 56/61, map 50/77,
  compat 33/350, dash 2/121.

### Read failures (1, honest reader gap)

- `dash.el` — the reader hits end-of-file mid-form (an Elisp token
  syntax the reader still misses). Tracked in the queue below.

The 2026-09-03 report listed 9 unreadable files; this wave fixed the
reader: `[a b c]` vector literals (consult.el died on
`[indicator ,(if …)]`), composable `?\A-\0`-style character modifier
escapes (compat-29.el's alist), and an on-demand **package shim** for
`use-package-normalize/:keyword` / `dash-expand:&hash`-style tokens —
the CL reader cannot unlearn its package markers, so missing packages
are created on demand and every occurrence resolves to the same symbol
(`src/elpa/elisp-reader.lisp`).

### Top missing primitives (what forms actually failed on)

| primitive | count | | primitive | count |
|---|---|---|---|---|
| compat-defun | 221 | | compat-guard | 8 |
| compat-defmacro | 31 | | compat-version | 8 |
| compat-defvar | 21 | | compat-require | 7 |
| compat-defalias | 14 | | consult--buffer-state | 5 |
| add-to-list | 8 | | consult--file-state | 3 |

The definition-form family that topped the 2026-09-03 table
(`cl-defmethod` 62, `defface` 60, `cl-defgeneric` 37, `defvar-local`
35, `eval-when-compile` 33, `declare-function` 26, `define-minor-mode`
17, `defvar-keymap` 13, `defalias` 14, `define-package` 12,
`defgroup` 9, `defconst` 7, `defsubst` 6, `autoload` 5) is **gone from
the missing list** — landed in `src/elpa/defmacros.lisp` with real
semantics (define-minor-mode defines the toggle and runs its body;
defvar-keymap builds a real keymap with a parent chain; cl-defmethod
gives real CL dispatch).

Unmet features (required, not vendored): kmacro(2), xref, org, info,
imenu, flymake, compile, bookmark, system-packages, bind-key,
regexp-opt, tabulated-list, bytecomp, dash — mostly cascade: a feature
"unmet" because its file died before its `provide`.

## What the numbers mean — the ELPA work queue

1. **The `compat` cascade** — compat-defun(221) + defmacro/defvar/
   defalias/guard/version/require (~300 hits) are compat's OWN wrappers,
   now that its `compat-macs.el` loads (depth 2). The compat-2x.el files
   die on an early `odd number of &KEY arguments` in their bootstrap —
   debug compat.el's own loading path (`compat-function`/`compat-call`
   macros, `compat--maybe-require`) and ~300 forms plus the whole
   compat-2x surface opens at once.
2. **dash.el** — still depth 0: the reader hits end-of-file on it.
   Bisect the token, extend the reader.
3. **Small runtime shims surfaced by the histogram**: `add-to-list(8)`,
   `string-remove-prefix(2)`, `regexp-opt(2)`, `map--plist-has-
   predicate(2)`, `map.el`'s `pcase-defmacro`/`condition-case`, and
   `defcustom`'s `:version` keyword (use-package-core fails on it).
4. **Feature coverage**: vendore `kmacro`, `xref`, `org`, `info`,
   `imenu`, `flymake`, `compile`, `bookmark`, `tabulated-list` into the
   corpus as they gain support, so the measurement can see past them.

## Rerunning

```bash
sbcl --noinform --disable-debugger --no-sysinit --no-userinit \
  --load tests/run-tests.lisp          # contract + numbers to stdout
```

Regenerate the JSON after any compat change and update this file with
the refreshed tables in the same commit. Bumping the corpus pin
(`vendor/elpa-corpus/README.md`) without re-landing numbers violates
the honesty law (AGENTS.md §1.10).
