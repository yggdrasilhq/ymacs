# vendor/elpa-corpus/ — the step-8 measurement corpus (pinned)

The public corpus that measures ELPA compatibility depth
(`docs/elpa-compat-measurement.md`, instrument `src/elpa/corpus.lisp`).
Deliberately the **blessed modern helper stack itself** plus the
foundation libraries it builds on — the measurement answers the question
"can ymacs load its own blessed stack?", which the "~90%" claim never
did (owner audit 2026-09-02).

Source: **GNU ELPA** (`https://elpa.gnu.org/packages/<name>-<version>.tar`),
fetched 2026-09-03 from the `archive-contents` index of that day.
Each tarball extracts as `<name>-<version>/<name>-<version>/` and is kept
**verbatim** — same doctrine as `docs/emacs-manual/`: never edit a
vendored file in place; each package keeps its own GPL licence header.
GNU ELPA packages are GPL-compatible; this repository is
GPL-3.0-or-later, so the vendoring is licence-clean.

| package | version | sha256 (tar) |
|---|---|---|
| seq | 2.24 | 8693439fd9bc447345aa6e1b5a4121107a474c4e7de5a511bbd2b8586aa0a88f |
| compat | 31.0.0.2 | 47d8693a10087f8b20c72e6a78b628db980cb7547c4f8f517fc5d11acd8b0f38 |
| map | 3.3.1 | 979a32f889a6124816da084c4485a08b130dfe714320457fdd5d77bf9be448fd |
| dash | 2.20.0 | 28f84b0905f84520163f5dd2087e47cac042bd27b7ec34eeb293f1ada7d36cb2 |
| use-package | 2.4.6 | cecba4042a3809b702f6e66eba50f8bc92d1dcc16190e7b09cf1a7772b3abe45 |
| cape | 2.9 | e5a8a474b1de8419cc7b7a88001243f949721fa52aa973aad5cba34e13ac5839 |
| corfu | 2.14 | c6ec346e5666badce80e693ba7fbb9c0e0e02627c200b570f255ba84a4d91aa8 |
| consult | 3.7 | 63f1724728fa7fbcab315e1aef2cf13d647774374b97fb27e8f862d528dbb1a7 |
| marginalia | 2.12 | df85d9e81049cbbbb3f5841fa4f818c5221e51e15149834b1d6da4ee9215423c |
| orderless | 1.7 | 7f65412799662761e6a37d8170ce506ccb7fd236906ed94f7384ec4d65a4333c |
| tempel | 1.14 | c375d362b9d464f4dd4486ead9e091d0fa6c337457a8e32796ece6dc46f15fd4 |
| vertico | 2.13 | 3ac95cd8f9159670b0fbbb7a3f1cfb0c0a9f44c437e44482106837334b422c3a |
| pcomplete | 30.1 (from emacs-30.1) | file sha256: 406ad7c8b292cb994ce0ce5c5ee392852bcf32d05871510870ebfc62267ac347 |
| format-spec | 30.1 (from emacs-30.1) | file sha256: cf219cd3d4e1de0c29c3a7decff6f390155b68f1f67a11ec121796b3179c46f0 |
| ring | 30.1 (from emacs-30.1) | file sha256: e1cc923221198204c93f7750fe13715d45545b4f88cb24623bfb43d2140f11d5 |
| avl-tree | 30.1 (from emacs-30.1) | file sha256: 4cab85d2562a657f127877a4b08d6453809f888b2642525f68bf3422cfe4d946 |
| tabulated-list | 30.1 (from emacs-30.1) | file sha256: d80a596782d16a6979124ef0e46dc6527fb660df7ee08110b7907c93c30bc026 |
| inline | 30.1 (from emacs-30.1) | file sha256: 98bc6985eda35d32362357232afdf4680d63db077387ca1f4a47c8851b6fef9c |
| macroexp | 30.1 (from emacs-30.1) | file sha256: 49d2e3ac7b14b538b057e93318010ea42761347f8ec8c47af4b988bc87ee615b |
| ansi-color | 30.1 (from emacs-30.1) | file sha256: c2cc24d0b8ec68cfcab799750f0da0bbecfa5ae2beac5a0d4dd108181fdb0d27 |
| ansi-osc | 30.1 (from emacs-30.1) | file sha256: 20653ba7e09dd784f4292efa6590df8cacb97739f39b4e9eb465efe0cc953efc |
| comint | 30.1 (from emacs-30.1) | file sha256: 62241325133770b0521be8bc559d7b266b68434707560359798932542779aa1b |
| org | 9.7.11 (from emacs-30.1) | tar sha256: 6ccac1ae76e6af93c6de1df175e8eb406767c23da3dd2a16aa67e3124a6f138f |

**inline** (the define-inline machinery) joined on 2026-09-08 for
org-element-ast. The 2026-09-08 wave added four more emacs-30.1 `lisp/` entries
alongside pcomplete: **format-spec** (org-compat/org-macro
dependency), **ring** and **avl-tree** (org-element), and
**tabulated-list** (org-lint keymap parent; Emacs preloads it,
the corpus must vendor it) — all verbatim, same tarball.
**pcomplete** is the second emacs-30.1 `lisp/` entry (after org): the
`org-pcomplete` dependency, vendored verbatim from the SAME
emacs-30.1 tarball on 2026-09-07 so `(require (quote pcomplete))`
resolves inside the corpus. Its own depth-1 gap is unmet
`feature:comint` (the comint/ring/ansi-color chain is the queued
next vendor step).

Re-pinning: bump the version here with the new sha256, re-run the
instrument, and re-land the numbers — a pin bump that ships without new
numbers violates the honesty law.

**org** is the one entry NOT from GNU ELPA: it is the step-6 import
target (`docs/spec-primitives.md`), extracted **verbatim** from the
`lisp/org/` tree of GNU emacs-30.1 — the SAME release the vendored
manuals came from, so the whole borrowed corpus has one provenance.
`docs/emacs-manual/fetch-org.sh` re-pins it. Generated files
(`org-loaddefs.el`) are dropped; `org-version.el` ships in the tree and
stays.
