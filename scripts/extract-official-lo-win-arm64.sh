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

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
echo "extract-official-lo-win-arm64: downloading $msi"
curl -fsSL --retry 3 -o "$work/$msi" "$url"

# Portable SHA-256 (Git Bash has sha256sum via coreutils).
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Administrative install: unpacks the MSI file tree without installing
# anything. (7z only sees the MSI's internal streams, not the payload.)
case $(uname -s) in
  MINGW* | MSYS*) ;;
  *)
    echo "extract-official-lo-win-arm64: Windows only (needs lessmsi)" >&2
    exit 1
    ;;
esac
# Extract with lessmsi (https://github.com/activescott/lessmsi): it reads the
# MSI file tables directly and is fully headless. msiexec /a hangs on the
# LibreOffice MSI under GitHub's Windows runners even with /qn (observed:
# 2h timeout with the msiexec process still alive).
lessmsi_ver=1.10.0
lessmsi_zip="$work/lessmsi-v${lessmsi_ver}.zip"
lessmsi_sha256="fdf6a3aab9c893966057004b64e2931af431a3459d323666e2e75c33a6825816"
echo "extract-official-lo-win-arm64: downloading lessmsi v${lessmsi_ver}"
curl -fsSL --retry 3 -o "$lessmsi_zip" \
  "https://github.com/activescott/lessmsi/releases/download/v${lessmsi_ver}/lessmsi-v${lessmsi_ver}.zip"
got=$(sha256_of "$lessmsi_zip")
[ "$got" = "$lessmsi_sha256" ] || {
  echo "extract-official-lo-win-arm64: lessmsi hash mismatch (got $got)" >&2
  exit 1
}
mkdir -p "$work/lessmsi"
unzip -q "$lessmsi_zip" -d "$work/lessmsi"
echo "extract-official-lo-win-arm64: extracting (lessmsi x)"
mkdir -p "$work/x"
"$work/lessmsi/lessmsi.exe" x "$(cygpath -w "$work/$msi")" "$(cygpath -w "$work/x")\\"

# Normalize the layout to what stage.sh expects: program/, share/,
# presets/ at top.
base=$(find "$work/x" -maxdepth 4 -type d -name program | head -n 1)
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
for f in LICENSE.html NOTICE CREDITS.fodt license.txt; do
  src=$(find "$base" -maxdepth 2 -name "$f" | head -n 1)
  [ -n "$src" ] && cp "$src" "$out/"
done
# licenses.sh hard-requires these; fail here, not in a later job.
for f in LICENSE.html NOTICE CREDITS.fodt license.txt; do
  [ -s "$out/$f" ] || {
    echo "extract-official-lo-win-arm64: no $f found under $base" >&2
    exit 1
  }
done
[ -d "$out/program" ] || {
  echo "extract-official-lo-win-arm64: extraction missed program/" >&2
  exit 1
}
echo "$lo_version" >"$out/.version"
echo "extract-official-lo-win-arm64: $out ($lo_version)"
