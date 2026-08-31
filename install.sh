#!/usr/bin/env bash
set -euo pipefail

echo "Installing ymacs..."

# Ensure Common Lisp toolchains (SBCL primary, ECL fallback)
if ! command -v sbcl >/dev/null 2>&1; then
  echo "sbcl not found — installing..."
  sudo apt-get update && sudo apt-get install -y sbcl
fi

# Build binary image (37M, <15ms startup)
if [ -f build.lisp ]; then
  echo "Building ymacs binary image..."
  sbcl --noinform --disable-debugger --no-sysinit --no-userinit --load build.lisp
else
  echo "No build.lisp — skipping binary build (interpreted fallback)"
fi

mkdir -p "$HOME/.local/bin"

# Install binary if built, else wrapper
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

echo "ymacs installed successfully."
echo "Try: ymacs --help"
