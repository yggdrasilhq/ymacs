# ELPA Compatibility — Measured (spec-primitives §5 step 8)

**Headline (2026-09-08, org ladder wave IV): 82 of 209 corpus files
load fully; 10701 of 12516 forms (85.5%) evaluate. org reached 57/127
files (8722/9714, 89.7%) — org-list now READS whole (an elisp `##`
dispatch token) — and org-element-ast's deferred-value struct
evaluates (elisp cl-defstruct on top of cl:defstruct). macroexp.el and
five more emacs-30.1 vendors landed; the elisp macroexpand-1/macroexpand
redefinitions no longer clobber CL's own (pre-shadowed).**
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
9.7.11** (127 `.el` files) and the emacs-30.1 `lisp/` entries
**pcomplete, format-spec, ring, avl-tree, inline, macroexp,
tabulated-list** (7 files), all extracted verbatim from `lisp/` of GNU emacs-30.1, the
SAME release the vendored manuals came from (`docs/emacs-manual/
fetch-org.sh` re-pins org; generated `org-loaddefs.el` dropped).

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

## Numbers (measured 2026-09-08 ladder wave IV, corpus + macroexp vendor)

Raw data: `elpa-compat-measurement.json` (next to this file).

| depth | files | % of corpus |
|---|---|---|
| 0 READ — unreadable by the Elisp reader | 3 | 1.4% |
| 1 LOAD — reads, some forms fail | 124 | 59.3% |
| 2 PROVIDE — fully evaluated + provided | **82** | 39.2% |

- Forms evaluated: **10701 / 12516 (85.5%)** overall — the blessed stack
  **1686 / 2489 (67.7%)**, org **8722 / 9714 (89.7%)**, pcomplete
  **98 / 108** (unmet `comint` chain), tabulated-list 57/62,
  avl-tree 42/45, macroexp 44/46, format-spec/ring/inline all PROVIDE.
- **org ladder wave IV (2026-09-08): the cl-defstruct rung** —
  elisp `cl-defstruct` now rides on `cl:defstruct` (the cl-lib
  doctrine) with two elisp divergences transformed: `(:constructor
  nil)` combined with named BOA constructors drops the nil entry, and
  a leading docstring is dropped (SBCL rejects `:documentation` on
  `:type` defstructs). org-element-ast's deferred-value struct — three
  BOA constructors + `(:type vector) :named` — evaluates. **org-list
  reads whole**: elisp's `##` token (a declare-function arglist
  leftover) has a dispatch reader now. macroexp.el vendored; the
  elisp `macroexpand-1`/`macroexpand` redefinitions are pre-shadowed so
  they no longer REDEFINE CL's own mid-run (measured: without the
  shadow, macroexp.el's defun silently replaced CL's function and
  poisoned every downstream macroexpansion). `car-safe`,
  `file-name-directory`, `convert-standard-filename`,
  `make-syntax-table` (v0 object), `display-graphic-p` (nil), the
  `noninteractive` variable, and `easy-menu-define` (v0 no-op) landed.
  org-list PROVIDES (57th org file); inline now PROVIDES off macroexp.

- **org ladder wave III (2026-09-08): org-lint PROVIDES 152/152** (the
  60-hit `make-org-lint-checker` histogram entry is gone) **and the ox
  export family opened** — `ox`, `ox-ascii`, `ox-icalendar`,
  `ox-latex`, `ox-man`, `ox-md`, `ox-org` all PROVIDE. What unlocked
  it:
  - **Reader: the comma-tolerant retry never rewound.** The retry path
    re-read from wherever the failed read had stopped (mid-form), so
    the leftover `))))` fired "unmatched close parenthesis" —
    org-element-ast had been dead on this since the bootstrap wave
    introduced the retry. Now it restores the form-start position
    first.
  - **`cl-defstruct` → `cl:defstruct`** (the cl-lib doctrine — an
    omission, not a shim): org-lint's `(cl-defstruct (org-lint-checker
    (:copier nil)) …)` defines the real keyword constructor
    `make-org-lint-checker`; all 60 `org-lint-add-checker` forms
    stopped failing at once. Limitation: CL rejects
    `(:constructor nil)` combined with named constructors (the
    org-element-ast deferred-value struct) — a real elisp-side
    cl-defstruct is queued.
  - **`interactive` is a declaration that must survive CALLS** —
    ox.el's creator defcustom calls `(org-version)`, whose body
    contains `(interactive)`; with no CL counterpart, any command
    invocation exploded. Now a no-op macro at call time (spec reading
    stays the command layer's job).
  - **The variable-binding intern was silently LOWERCASE** — CL's
    `intern` does not case-convert, so the env's predefined-variable
    list bound `|emacs-version|` while the reader produces
    `EMACS-VERSION`. Latent since the env existed (nothing referenced
    those variables bare until ox.el). Fixed with `string-upcase`;
    `emacs-version` and `load-suffixes` are now really bound.
  - **Primitives**: `delq`/`remq` (non-destructive v0, documented),
    `downcase`/`upcase` (char-or-string), `copy-sequence`,
    `sequencep`, `next-line`/`previous-line` (real point math,
    column-goal polish documented), `define-inline` v0 (plain defun —
    the inlining layer is future work), `define-derived-mode` v0 (real
    keymap parentage + hook wiring; parent mode functions must be
    fbound at call).
  - **Vendors (all emacs-30.1, sha256 in
    `vendor/elpa-corpus/README.md`)**: `format-spec` 5/5 PROVIDE,
    `ring` 25/25 PROVIDE (one `cl-deftype` alias away), `avl-tree`
    36/45, `inline` 21/22, `tabulated-list` 57/62 (org-lint's keymap
    parent; Emacs preloads it, the corpus must vendor it). Corpus is
    19 packages / 208 files.

- **org rungs wave II (prior, 2026-09-07): the five one-form rungs
  PROVIDED** — `ob-R` 44/44, `ob-js` 20/20, `ob-perl` 20/20,
  `ob-emacs-lisp` 16/16, `org-pcomplete` 75/75. What unlocked it:
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

- Depth-2 named additions this wave: **`org-list`** in org; the
  `inline` vendor (via macroexp). Per-package forms-evaluated:
  consult 452/494, corfu 223/246, use-package 235/242, vertico
  223/241, cape 124/135, marginalia 145/150, tempel 71/73, orderless
  69/73, seq 59/61, map 50/77, compat 33/350, dash 2/347, pcomplete
  98/108, tabulated-list 57/62, avl-tree 42/45, macroexp 44/46.

### Read failures (3, honest reader gaps)

`dash.el` (end of file mid-form — an unclosed-constructor class the
death-offset bisect has not pinpointed yet), `org-table.el` (reader
error, position unknown), `org-duration.el` (mid-token colons —
`h:mm:ss` format symbols; MEASURED UNFIXABLE at readtable level: SBCL's
tokenizer hard-codes package markers, so this wants a real elisp
tokenizer — the structural reader project in the queue). The
2026-09-03 report listed 9 unreadable files; successive waves fixed
the reader: `[a b c]` vector literals, composable `?\A-\0`-style
character modifier escapes, an on-demand **package shim** for
`use-package-normalize/:keyword` / `dash-expand:&hash`-style tokens,
`?` as a NON-terminating macro char, stray commas outside backquotes
(with the retry rewind), the token-start colon reader, the 22-bit
string-escape guard, and the `##` dispatch token.

### Top missing primitives (what forms actually failed on)

| primitive | count | | primitive | count |
|---|---|---|---|---|
| compat-defun | 221 | | compat-guard | 8 |
| compat-defmacro | 31 | | compat-version | 8 |
| compat-defvar | 21 | | compat-require | 7 |
| org-replace-disputed-keys | 16 | | org-element-deferred-create | 7 |
| car-safe | 9 | | consult--buffer-state | 5 |

`make-org-lint-checker(60)` left the list this wave (org-lint
provides). The definition-form family that topped the 2026-09-03 table
(`cl-defmethod` 62, `defface` 60, `cl-defgeneric` 37, `defvar-local`
35, `eval-when-compile` 33, `declare-function` 26, `define-minor-mode`
17, `defvar-keymap` 13, `defalias` 14, `define-package` 12,
`defgroup` 9, `defconst` 7, `defsubst` 6, `autoload` 5) is **gone from
the missing list** — landed in `src/elpa/defmacros.lisp` with real
semantics (define-minor-mode defines the toggle and runs its body;
defvar-keymap builds a real keymap with a parent chain; cl-defmethod
gives real CL dispatch). `add-to-list`, `delq`, `define-inline` left
the list in the last two waves.

Unmet features (required, not vendored): comint(4), bibtex(3),
org-table(3), table(2), json(2), sha1(2), eshell(2), cc-mode(2),
org-list(2), gnus-sum(2), kmacro(2), plus singles — mostly cascade: a
feature "unmet" because its file died before its `provide`, or the
dependency chain (comint→ring/ansi-color) is not vendored yet.

### The org queue after this wave (top blockers)

- **org-element-ast 34/48 — the one structural blocker left**: its
  define-inline forms load inline.el's REAL define-inline macro
  mid-file (last defmacro wins — honest elisp semantics), and that
  macro's expansion machinery fails in the compat env. Getting it
  green means chasing inline.el's macro expansion path — after that,
  org-element (needs make-char-table, org-list/org-table features) and
  the whole ox-* depth open up.
- **org-table / org-duration / dash** — the three depth-0 files
  (causes above). The elisp tokenizer is the structural fix for the
  colon class; dash/org-table want death-offset bisects.
- **pcomplete 98/108** — the comint chain (ring is provided now;
  comint needs ansi-color/ansi-osc too).
- **ox-html 206/209, ox-publish 58/59, ox-texinfo 116/117** —
  one-to-four forms each; `org-export-with-latex` misses are the
  alphabetical load-order artifact (ox-latex defines it after
  ox-html), not compat gaps.
- **macroexp 44/46, tabulated-list 57/62, avl-tree 42/45** — small
  eval gaps in the newer vendors (make-composed-keymap,
  macroexp-warn-and-return, gv-define-simple-setter/iter).

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
3. **Landed from the old histograms** (2026-09-07/08 waves):
   `defcustom`'s keyword family, `add-to-list`, `intern-soft`,
   `delq`/`remq`, `downcase`/`upcase`, `copy-sequence`, `sequencep`,
   `define-inline` (v0), `define-derived-mode` (v0), the
   `interactive` declaration, elisp `cl-defstruct`, the `##` token,
   the variable-intern upcase fix, `car-safe`, `file-name-directory`,
   `convert-standard-filename`, `make-syntax-table` (v0),
   `easy-menu-define` (v0), `noninteractive`. Remaining small shims:
   `substitute-key-definition(3)`, `make-char-table(3)`,
   `org-replace-disputed-keys(16)`.
4. **Feature coverage**: vendor `comint`/`ansi-color`, `kmacro`,
   `json`, `table` into the corpus as they gain support, so the
   measurement can see past them.

## Rerunning

```bash
sbcl --noinform --disable-debugger --no-sysinit --no-userinit \
  --load tests/run-tests.lisp          # contract + numbers to stdout
```

Regenerate the JSON after any compat change and update this file with
the refreshed tables in the same commit. Bumping the corpus pin
(`vendor/elpa-corpus/README.md`) without re-landing numbers violates
the honesty law (AGENTS.md §1.10).
