#!/bin/sh
# Re-pin the vendored GNU Emacs manual corpus (docs/emacs-manual/README.md).
# Usage: fetch.sh <version>   e.g. fetch.sh 30.1
# Streams the GNU release tarball and extracts ONLY the two manual doc trees;
# nothing else from the archive is stored.
set -eu
VER="${1:?usage: fetch.sh <version>}"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK="${YMACS_SCRATCH:-$HOME/.yggterm/scratchpad}/emacs-texi-$VER"
mkdir -p "$WORK"
cd "$WORK"
curl -sL --max-time 600 "https://ftp.gnu.org/gnu/emacs/emacs-${VER}.tar.xz" \
  | tar -xJ --wildcards \
      "emacs-${VER}/doc/emacs/*.texi" \
      "emacs-${VER}/doc/lispref/*.texi"
rm -rf "$HERE/emacs" "$HERE/lisp"
mv "emacs-${VER}/doc/emacs" "$HERE/emacs"
mv "emacs-${VER}/doc/lispref" "$HERE/lisp"
rm -rf "$WORK"
echo "pinned emacs-${VER}: $(ls "$HERE/emacs"/*.texi | wc -l) + $(ls "$HERE/lisp"/*.texi | wc -l) texi files"
echo "now update the Pin/Source lines in $HERE/README.md and commit."
