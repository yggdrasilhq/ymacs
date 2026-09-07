# ELPA Compatibility — Measured (spec-primitives §5 step 8)

**Headline (2026-09-07, org rungs wave II): 64 of 203 corpus files load
fully; 10139 of 12097 forms (83.8%) evaluate. org jumped 18/127 →
44/127 files (8361/9500, 88.0%); the blessed stack rose to 20/75 files
(1680/2489). The one-form rungs landed: ob-R, ob-js, ob-perl,
ob-emacs-lisp and org-pcomplete all PROVIDE — unblocked by three small
compat fixes (defcustom's full keyword surface, add-to-list's quoted
var, intern-soft) and pcomplete.el vendored into the corpus.**
The first measurement (2026-09-03) put this at 1 file
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
tempel 1.14, vertico 2.13 — **75 top-level `.el` files** — plus **org
9.7.11** (127 `.el` files) and **pcomplete** (1 file), extracted
verbatim from `lisp/` of GNU emacs-30.1, the SAME release the vendored
manuals came from (`docs/emacs-manual/fetch-org.sh` re-pins org;
generated `org-loaddefs.el` dropped).

The question the blessed stack answers is the one the "~90%" claim
never did: *can ymacs load its own blessed stack?* org answers the
step-6 question: *how far is the real thing from loading?* — measured,
not guessed, from the day it is imported.

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

## Numbers (measured 2026-09-07 rungs wave II, corpus + pcomplete pin)

Raw data: `elpa-compat-measurement.json` (next to this file).

| depth | files | % of corpus |
|---|---|---|
| 0 READ — unreadable by the Elisp reader | 5 | 2.5% |
| 1 LOAD — reads, some forms fail | 134 | 66.0% |
| 2 PROVIDE — fully evaluated + provided | **64** | 31.5% |

- Forms evaluated: **10139 / 12097 (83.8%)** overall — the blessed stack
  **1680 / 2489 (67.5%)**, org **8361 / 9500 (88.0%)**, pcomplete
  **98 / 108** (depth 1 on the unmet `comint` chain).
- **org rungs wave II (2026-09-07): the five one-form rungs PROVIDE** —
  `ob-R` 44/44, `ob-js` 20/20, `ob-perl` 20/20, `ob-emacs-lisp` 16/16,
  `org-pcomplete` 75/75. What unlocked it:
  - **`defcustom` accepts the full keyword surface** (:version,
    :package-version, :set, :safe, :get, :initialize, :risky, :options,
    :require, :tag, :link …). ob-R/ob-js/ob-core died on `:version`,
    ol.el on `:package-version`/`:set`/`:safe`. v0 models only the
    standard-get semantics — recorded-and-ignored keywords are a
    documented limitation.
  - **`add-to-list` strips the quoted var** — the macro received
    `(quote sym)` (the reader's shape for `'sym`) and called
    symbol-name on the cons; ob-perl's top-level call died there.
  - **`intern-soft`** — the honest contract (find-or-nil, never
    interns); ob-emacs-lisp's top-level
    `(org-babel-make-language-alias "elisp" "emacs-lisp")` call needed
    it.
  - **pcomplete.el vendored** (30.1, file sha256 in
    `vendor/elpa-corpus/README.md`) — the corpus is 14 packages / 203
    files now. The vendor exposed a READER gap: Emacs strings carry
    22-bit chars (`\x3FFF7F` in pcomplete's regexp) and SBCL's
    code-char SIGNALS past #x10FFFF — out-of-range string escapes now
    land as U+FFFD, a documented v0 divergence (data, never compared).
  - **Cascade**: +26 org files provide (18→44); +4 blessed files
    (16→20); ob-core sits at 244/247, ol.el at 144/152.

- **org bootstrap (prior wave, same day): 18/127 depth-2** — `ob.el`,
  `ob-eval`, `ob-lob`, `ob-ref`, `ob-table`, and eleven language-
  specific `ob-*` loaders, plus `org-macro` and the generated
  `org-version.el`. What unlocked it:
  - **Reader: `?` is now a NON-terminating macro character.** It was
    terminating, so a symbol ending in `?` (`allow-empty?`, idiomatic
    org/lisp naming) dispatched a char literal mid-symbol and ate the
    closing parens — every depth-0 file died there.
  - **Reader: stray commas outside a backquote** (`define-inline`
    bodies in org-element-ast) now re-read once through a
    comma-tolerant readtable instead of killing the file.
  - **Reader (rung 2): a token-start colon reader** — a lone `:` in rx
    patterns (`(: string-start …)`) is the empty-name symbol Emacs
    accepts; `:keyword` tokens still read as keywords, upcased as the
    standard readtable does. ol.el and org-lint.el now read whole —
    the depth-0 class is extinct.
  - **Primitives** (shipped compat layer, honest implementations):
    `add-to-list`, `make-obsolete(-variable)`, `make-sparse-keymap`,
    `defvaralias`, `eval-after-load`, `while`, `getenv`,
    `executable-find`, `version<`/`<=`, `subr-arity`, `regexp-opt`/
    `regexp-quote`, overlays, `easy-menu-add-item`, `user-error`,
    `kbd`, a real `pcase`/`rx` subset (with documented limits),
    `gv-define-setter`, `set-keymap-parent`, `make-marker`,
    `expand-file-name`, `emacs-version`, and `org-release`/
    `org-git-version` bound to the pinned version (the generated
    header Emacs ships preloaded).

- Depth-2 files named by earlier waves stay provided (compat.el + its
  macro file, the use-package trio, cape-keyword, three corfu modes,
  six vertico modes); the rungs wave added 26 org files and 4 blessed
  files. Per-package forms-evaluated: consult 452/494, corfu 223/246,
  use-package 233/242, vertico 223/241, cape 124/135, marginalia
  145/150, tempel 70/73, orderless 69/73, seq 56/61, map 50/77,
  compat 33/350, dash 2/347, pcomplete 98/108.

### Read failures (5, honest reader gaps)

`dash.el`, `org-table.el`, `org-list.el`, `org-element-ast.el`,
`org-duration.el` — the reader still dies mid-form on each (tracked in
the queue below). The 2026-09-03 report listed 9 unreadable files;
successive waves fixed the reader: `[a b c]` vector literals
(consult.el died on `[indicator ,(if …)]`), composable
`?\A-\0`-style character modifier escapes (compat-29.el's alist), an
on-demand **package shim** for `use-package-normalize/:keyword` /
`dash-expand:&hash`-style tokens, `?` as a NON-terminating macro char,
stray commas outside backquotes, the token-start colon reader, and the
22-bit string-escape guard (pcomplete).

### Top missing primitives (what forms actually failed on)

| primitive | count | | primitive | count |
|---|---|---|---|---|
| compat-defun | 221 | | compat-guard | 8 |
| make-org-lint-checker | 60 | | compat-version | 8 |
| compat-defmacro | 31 | | compat-require | 7 |
| compat-defvar | 21 | | org-element-deferred-create | 7 |
| org-replace-disputed-keys | 16 | | org-export-create-backend | 11 |

The definition-form family that topped the 2026-09-03 table
(`cl-defmethod` 62, `defface` 60, `cl-defgeneric` 37, `defvar-local`
35, `eval-when-compile` 33, `declare-function` 26, `define-minor-mode`
17, `defvar-keymap` 13, `defalias` 14, `define-package` 12,
`defgroup` 9, `defconst` 7, `defsubst` 6, `autoload` 5) is **gone from
the missing list** — landed in `src/elpa/defmacros.lisp` with real
semantics (define-minor-mode defines the toggle and runs its body;
defvar-keymap builds a real keymap with a parent chain; cl-defmethod
gives real CL dispatch). `add-to-list` left the list this wave too.

Unmet features (required, not vendored): format-spec(5), comint(4),
bibtex(3), org-table(3), table(2), json(2), sha1(2), eshell(2),
cc-mode(2), gnus-sum(2), kmacro(2), tabulated-list(2), plus singles —
mostly cascade: a feature "unmet" because its file died before its
`provide`, or the dependency chain (comint→ring/ansi-color) is not
vendored yet.

### The org queue after this wave (top blockers)

The one-form-per-file class is CLOSED (all five rungs provide). The
next rungs, in order: **make-org-lint-checker** (60 hits — org-lint's
own cl-defmacro must first evaluate; org-lint sits at 89/152),
**org-element-ast** (depth 0, the reader death — the whole ox-* export
family is behind it), **org-export-create-backend** (11),
**feature:format-spec** (5 files), `org-replace-disputed-keys` (16),
and the comint/ring/ansi-color vendor chain to push pcomplete past
98/108.

## What the numbers mean — the ELPA work queue

1. **The `compat` cascade** — compat-defun(221) + defmacro/defvar/
   defalias/guard/version/require (~300 hits) are compat's OWN wrappers,
   now that its `compat-macs.el` loads (depth 2). The compat-2x.el files
   die on an early `odd number of &KEY arguments` in their bootstrap —
   debug compat.el's own loading path (`compat-function`/`compat-call`
   macros, `compat--maybe-require`) and ~300 forms plus the whole
   compat-2x surface opens at once.
2. **Five depth-0 files** — dash.el, org-table.el, org-list.el,
   org-element-ast.el, org-duration.el: the reader dies mid-form on
   each. Bisect the token (the door's death-offset probe recipe),
   extend the reader.
3. **Landed from the old histogram** (2026-09-07 rungs wave):
   `defcustom`'s `:version` keyword family, `add-to-list`, and
   `intern-soft`. Remaining small shims: `string-remove-prefix(2)`,
   `map--plist-has-predicate(2)`, map.el's `pcase-defmacro`/
   `condition-case`, `make-syntax-table(4)`, `easy-menu-define(4)`.
4. **Feature coverage**: vendor `format-spec`, `comint`/`ring`/
   `ansi-color`, `kmacro`, `tabulated-list`, `json` into the
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
