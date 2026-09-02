# Vendored GNU Emacs Manuals (Texinfo sources)

The GNU Emacs manuals are the reference base for ymacs' compatibility work.
They are vendored here **verbatim, unmodified**, pinned to a GNU release.

- **Pin:** GNU Emacs 30.1 (`@set EMACSVER 30.1`)
- **Source:** `https://ftp.gnu.org/gnu/emacs/emacs-30.1.tar.xz` (doc/emacs,
  doc/lispref), fetched 2026-09-02
- **Licence:** GFDL-1.3-or-later **as declared by the manuals themselves —
  WITH their Invariant Sections and cover texts** (see the permission
  statement in `emacs/emacs.texi` and `lisp/elisp.texi`). These are verbatim
  third-party copies under their own licence notice; they are NOT part of
  ymacs' own documentation grant (ymacs docs elsewhere in the repo are
  GFDL-1.3-or-later with no Invariant Sections).
- **Contents:** `emacs/` — the Emacs manual (62 .texi files);
  `lisp/` — the Emacs Lisp reference manual (57 .texi files).

## Law: never edit the vendored files

Because the corpus carries invariant sections, it must stay byte-verbatim —
a modified GFDL copy with invariant sections is a licence trap. ymacs'
changes live OUTSIDE the corpus:

1. **`divergences.org`** (this directory) — the numbered ledger of every
   deliberate divergence or extension, each citing the Emacs manual node
   (and where useful, the .texi file) it diverges from.
2. **`docs/manual.org`** — ymacs' own manual, marked `[parity]`,
   `[ymacs extension]`, or `[divergence #N]` per chapter.

## Re-pinning

`fetch.sh <version>` re-downloads and re-extracts a new release pin
(streamed; nothing else is stored). Bump the pin, commit, and re-diff the
corpus if needed to catch upstream changes worth tracking.
