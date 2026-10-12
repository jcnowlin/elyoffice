#!/usr/bin/env bash
# Fetches the official LibreOffice Windows Aarch64 build and unpacks the
# kernel Ely stages (program/, share/, presets/), never installing it.
# Idempotent: skips when engines/lo-win-arm64/.version matches.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=$root/engines/lo-win-arm64

lo_version=${ELY_LO_VERSION:-26.8.0}
msi="LibreOffice_${lo_version}_Win_aarch64.msi"
url="https://download.documentfoundation.org/libreoffice/stable/${lo_version}/win/aarch64/${msi}"

if [ "$(cat "$out/.version" 2>/dev/null)" = "$lo_version" ] && [ -d "$out/program" ]; then
  echo "extract-official-lo-win-arm64: $lo_version already in $out"
  exit 0
fi

command -v 7z >/dev/null || {
  echo "extract-official-lo-win-arm64: needs 7z (choco install 7zip)" >&2
  exit 1
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "extract-official-lo-win-arm64: downloading $msi"
curl -fsSL --retry 3 -o "$work/$msi" "$url"

# The MSI's files land under a LibreOffice program folder; normalize the
# layout to what stage.sh expects: program/, share/, presets/ at top.
echo "extract-official-lo-win-arm64: extracting"
7z x -y -o"$work/x" "$work/$msi" >/dev/null
base=$(find "$work/x" -maxdepth 3 -type d -name program | head -n 1)
[ -n "$base" ] || {
  echo "extract-official-lo-win-arm64: no program/ in $msi" >&2
  exit 1
}
base=$(dirname "$base")

rm -rf "$out"
mkdir -p "$out"
for part in program share presets; do
  [ -d "$base/$part" ] && mv "$base/$part" "$out/"
done
# The notices stage.sh copies beside the kernel.
for f in LICENSE.html NOTICE CREDITS.fodt; do
  src=$(find "$base" -maxdepth 2 -name "$f" | head -n 1)
  [ -n "$src" ] && cp "$src" "$out/"
done
[ -d "$out/program" ] || {
  echo "extract-official-lo-win-arm64: extraction missed program/" >&2
  exit 1
}
echo "$lo_version" >"$out/.version"
echo "extract-official-lo-win-arm64: $out ($lo_version)"
