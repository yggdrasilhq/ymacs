#!/usr/bin/env bash
set -euo pipefail
echo "Installing ymacs..."
if ! command -v sbcl >/dev/null 2>&1; then
  echo "sbcl not found — installing..."
  sudo apt-get update && sudo apt-get install -y sbcl
fi
if [ -f build.lisp ]; then
  echo "Building ymacs binary image..."
  sbcl --noinform --disable-debugger --no-sysinit --no-userinit --load build.lisp
fi
mkdir -p "$HOME/.local/bin"
if [ -f ymacs-bin ]; then
  cp ymacs-bin "$HOME/.local/bin/ymacs-bin"
  chmod +x "$HOME/.local/bin/ymacs-bin"
  echo "Installed binary to $HOME/.local/bin/ymacs-bin"
fi
if [ -f bin/ymacs ]; then
  cp bin/ymacs "$HOME/.local/bin/ymacs"
  chmod +x "$HOME/.local/bin/ymacs"
  echo "Installed launcher to $HOME/.local/bin/ymacs"
fi
if [ -f docs/manual.org ]; then
  mkdir -p "$HOME/.local/share/ymacs"
  cp docs/manual.org "$HOME/.local/share/ymacs/manual.org"
  echo "Installed manual to $HOME/.local/share/ymacs/manual.org"
fi
rm -f "$HOME/.local/bin/ymacs-bin.old" 2>/dev/null || true
echo "ymacs installed successfully. Try: ymacs --help"
