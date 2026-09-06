#!/bin/sh
# Re-pin the vendored org corpus (vendor/elpa-corpus/README.md, the org row).
# Downloads the GNU release tarball, extracts ONLY org's lisp tree —
# the same doctrine as docs/emacs-manual/fetch.sh: verbatim, nothing else
# from the archive is stored. Org rides the SAME emacs release as the
# vendored manuals, so the whole borrowed corpus has one provenance.
set -eu
VER="${1:?usage: fetch-org.sh <emacs-version>}   e.g. fetch-org.sh 30.1"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK="${YMACS_SCRATCH:-$HOME/.yggterm/scratchpad}/emacs-org-$VER"
mkdir -p "$WORK"
cd "$WORK"
TARBALL="emacs-${VER}.tar.xz"
curl -sL --max-time 900 -o "$TARBALL" "https://ftp.gnu.org/gnu/emacs/$TARBALL"
echo "tar sha256: $(sha256sum "$TARBALL" | cut -d' ' -f1)"
tar -xJf "$TARBALL" "emacs-${VER}/lisp/org"
# The corpus layout: <name>-<ver>/<name>-<ver>/*.el (the instrument's
# corpus-package-dir glob). The inner dir carries the ORG version the
# emacs release bundles — read from org.el's heading.
ORGVER=$(sed -n 's/^;; Version: \([0-9.]*\)$/\1/p' "emacs-${VER}/lisp/org/org.el" | head -1)
test -n "$ORGVER" || { echo "could not read org version from org.el" >&2; exit 1; }
rm -rf "$HERE/org-$ORGVER"
mkdir -p "$HERE/org-$ORGVER/org-$ORGVER"
mv "emacs-${VER}/lisp/org/"*.el "$HERE/org-$ORGVER/org-$ORGVER/"
rm -f "$HERE/org-$ORGVER/org-$ORGVER/org-loaddefs.el"
cd /
rm -rf "$WORK"
echo "pinned org-$ORGVER (from emacs-$VER): $(ls "$HERE/org-$ORGVER/org-$ORGVER"/*.el | wc -l) el files"
echo "now: put the tar sha256 in vendor/elpa-corpus/README.md, add org to"
echo "*corpus-packages*, re-run measure-corpus, re-land the numbers (honesty law)."
