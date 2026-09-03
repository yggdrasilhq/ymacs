# ELPA Compatibility — Measured (spec-primitives §5 step 8)

**Headline: 1 of 75 corpus files loads (a keyword table); 797 of 1944
forms (41%) evaluate. The old "~90%" was a target, never a measurement**
— the owner audit of 2026-09-02 said exactly that, and this report is
the correction. Re-run the instrument after every compat change and
re-land the numbers; a stale number here is the same failure mode the
audit caught.

## The corpus

The blessed modern helper stack itself plus the foundation libraries it
builds on, vendored **verbatim** from GNU ELPA on 2026-09-03 (pin,
versions and tar sha256s: `vendor/elpa-corpus/README.md`):

seq 2.24, compat 31.0.0.2, map 3.3.1, dash 2.20.0, use-package 2.4.6,
cape 2.9, corfu 2.14, consult 3.7, marginalia 2.12, orderless 1.7,
tempel 1.14, vertico 2.13 — **75 top-level `.el` files**.

The question this corpus answers is the one the "~90%" claim never did:
*can ymacs load its own blessed stack?*

## Method (`src/elpa/corpus.lisp`, `src/elpa/elisp-reader.lisp`)

Per file, a three-rung depth ladder:

- **0 READ** — the Elisp reader cannot read the file whole.
- **1 LOAD** — reads; at least one form fails to evaluate (missing
  primitive, unmet feature, load-time error).
- **2 PROVIDE** — every form evaluated and the file's own `(provide …)`
  ran.

The evaluator is the **shipped compat layer** (`src/elpa/compat.lisp`)
bound under its Elisp names — never a measurement-friendly fake; what
fails, fails into the report. The only measurement machinery beyond it:
`require` resolves against the vendored corpus (package.el semantics),
provide is tracked per file, and each measurement starts from a
**scrubbed Elisp package** so run N's defuns cannot answer run N+1's
probes. SBCL's evaluator runs in interpret mode (measuring 76 real
packages under the compiler blew the dynamic space), with a full sweep
per package. Contract tests: `tests/elpa-corpus-tests.lisp` — they
assert the instrument's structure, never the numbers.

## Numbers (measured 2026-09-04, corpus pinned 2026-09-03)

Raw data: `elpa-compat-measurement.json` (next to this file).

| depth | files | % of corpus |
|---|---|---|
| 0 READ — unreadable by the Elisp reader | 9 | 12% |
| 1 LOAD — reads, some forms fail | 65 | 87% |
| 2 PROVIDE — fully evaluated + provided | **1** | 1% |

- Forms evaluated: **797 / 1944 (41.0%)**.
- The single depth-2 file is `cape-keyword.el` — a keyword table. No
  main package file loads.
- Per-package forms-evaluated: cape 105/135, corfu 178/246, vertico
  148/241, marginalia 88/150, tempel 61/73, orderless 54/73, seq 49/61,
  consult 69/313, compat 23/322, map 14/77, use-package 7/132,
  dash 1/121.

### Read failures (9, honest reader gaps)

- `use-package-normalize/:keyword`-style symbols (6 use-package files):
  the CL reader parses the `/` as a package prefix.
- Elisp's comma-outside-backquote (pcase patterns): `consult.el`,
  `dash.el`, `compat-29.el`.

### Top missing primitives (what forms actually failed on)

| primitive | count | | primitive | count |
|---|---|---|---|---|
| compat-defun | 162 | | defalias | 14 |
| cl-defmethod | 62 | | defvar-keymap | 13 |
| defface | 60 | | compat-defalias | 12 |
| cl-defgeneric | 37 | | define-package | 12 |
| defvar-local | 35 | | defgroup | 9 |
| eval-when-compile | 33 | | defconst | 7 |
| declare-function | 26 | | compat-version | 7 |
| compat-defmacro | 19 | | defsubst | 6 |
| define-minor-mode | 17 | | compat-guard | 6 |
| compat-defvar | 17 | | autoload | 5 |

Unmet features (required, not vendored): consult(8), use-package-core(3),
kmacro(2), cl-lib(2), xref, org, info, imenu, flymake, compile, subr-x,
dash — mostly cascade: a feature "unmet" because its file died before
its `provide`.

## What the numbers mean — the ELPA work queue

1. **Definition macros first** (load-time, everything hangs off them):
   `cl-defmethod`/`cl-defgeneric` (cl-lib), `defvar-local`,
   `defalias`/`defsubst`, `defconst`, `defface`/`defgroup`,
   `define-minor-mode`, `defvar-keymap`, `define-package`,
   `eval-when-compile`, `declare-function`, `autoload`. The `compat-*`
   family (162+19+17+12+7+6+5) is the `compat` package's own wrappers —
   its `compat.el` died early, so those 162 `compat-defun` hits cascade;
   loading compat is itself high leverage.
2. **Reader gaps**: package-prefixed symbols (`foo/:bar`) and
   comma-outside-backquote.
3. **Feature coverage**: vendore `cl-lib`, `subr-x`, `kmacro`, `xref`,
   `org`, `info`, `imenu`, `flymake`, `compile` into the corpus as they
   gain support, so the measurement can see past them.

## Rerunning

```bash
sbcl --noinform --disable-debugger --no-sysinit --no-userinit \
  --load tests/run-tests.lisp          # contract + numbers to stdout
```

Regenerate the JSON after any compat change and update this file with
the refreshed tables in the same commit. Bumping the corpus pin
(`vendor/elpa-corpus/README.md`) without re-landing numbers violates
the honesty law (AGENTS.md §1.10).
