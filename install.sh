#!/usr/bin/env sh
set -eu

src="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/bin/vps"
dest="${PORTHOLE_BIN:-$HOME/.local/bin}"

mkdir -p "$dest"
install -m 0755 "$src" "$dest/vps"
printf 'installed %s\n' "$dest/vps"

case ":$PATH:" in
  *":$dest:"*|*":$dest/:"*) ;;
  *)
    printf '\nadd this to your shell profile:\n  export PATH="%s:$PATH"\n' "$dest"
    ;;
esac
