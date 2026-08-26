#!/usr/bin/env bash
# Symlink stripmeta into a directory on your PATH.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stripmeta"
[[ -f "$src" ]] || { echo "error: stripmeta not found next to install.sh" >&2; exit 1; }
chmod +x "$src"

# Prefer a user-owned directory already on PATH; fall back to /usr/local/bin.
target=""
for d in "$HOME/.local/bin" "$HOME/bin" /usr/local/bin; do
  case ":$PATH:" in *":$d:"*) target="$d"; break ;; esac
done
[[ -n "$target" ]] || target="$HOME/.local/bin"
mkdir -p "$target"

if [[ -w "$target" ]]; then
  ln -sf "$src" "$target/stripmeta"
else
  sudo ln -sf "$src" "$target/stripmeta"
fi

echo "installed: $target/stripmeta -> $src"

case ":$PATH:" in
  *":$target:"*) ;;
  *) echo
     echo "note: $target is not on your PATH. Add this to your shell profile:"
     echo "      export PATH=\"$target:\$PATH\"" ;;
esac

command -v exiftool >/dev/null 2>&1 || {
  echo
  echo "note: exiftool is not installed — stripmeta needs it."
  echo "      macOS:  brew install exiftool"
  echo "      Debian: sudo apt install libimage-exiftool-perl"
}
