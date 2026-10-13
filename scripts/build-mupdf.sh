#!/usr/bin/env bash
# Builds the pinned MuPDF, with patches/mupdf, into engines/mupdf-build.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
src=$root/engines/mupdf-src
out=$root/engines/mupdf-build
jobs=$(sysctl -n hw.ncpu 2>/dev/null || nproc)

# reference/ stays read-only; the copy takes the patches.
mkdir -p "$src"
case $(uname -s) in
  MINGW* | MSYS*)
    rm -rf "$src" && mkdir -p "$src"
    # Dereference: Windows runners can't recreate symlinks, so the copy
    # materializes them as real files (the MSVC build only needs contents).
    # Exclude zxing-cpp's libzint symlinks: upstream leaves them dangling
    # (they point at a zint/ dir that doesn't exist inside zxing-cpp), and
    # --dereference chokes on them. Nothing references them: libzxing.vcxproj
    # compiles zero libzint files, and libmupdf (the only target we build)
    # doesn't link libzxing at all.
    tar -C "$root/reference/mupdf" --dereference --exclude .git --exclude '*/libzint' -cf - . | tar -C "$src" -xf -
    ;;
  *) rsync -a --delete --exclude .git "$root/reference/mupdf/" "$src/" ;;
esac
for patch in "$root"/patches/mupdf/*.patch; do
  patch -d "$src" -p1 --forward --batch --quiet <"$patch"
done
case $(uname -s) in
  MINGW* | MSYS*)
    # MSVC: the static runtime Rust links, OpenSSL from vcpkg.
    case ${ELY_ARCH:-x86_64} in
      aarch64) triplet=arm64-windows-static; platform=ARM64 ;;
      *) triplet=x64-windows-static; platform=x64 ;;
    esac
    ssl=$(cygpath -w "$root/engines/vcpkg/installed/$triplet")
    [ -f "$ssl/lib/libcrypto.lib" ] || {
      echo "build-mupdf.sh: no static OpenSSL; run engines/vcpkg/vcpkg install openssl:$triplet" >&2
      exit 1
    }
    cat >"$src/ely.props" <<PROPS
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup>
    <ClCompile>
      <RuntimeLibrary>MultiThreaded</RuntimeLibrary>
      <PreprocessorDefinitions>HAVE_LIBCRYPTO;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <AdditionalIncludeDirectories>$ssl\include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
PROPS
    msbuild=$("/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe" -latest -find 'MSBuild\**\Bin\MSBuild.exe' | tr -d '\r')
    "$msbuild" "$(cygpath -w "$src/platform/win32/mupdf.sln")" -m -nologo -v:minimal \
      -t:libmupdf -p:Configuration=Release -p:Platform="$platform" -p:PlatformToolset=v145 \
      -p:ForceImportAfterCppTargets="$(cygpath -w "$src/ely.props")"
    rm -rf "$out" && mkdir -p "$out"
    case $platform in
      ARM64) cp "$src"/platform/win32/ARM64/Release/*.lib "$out/" ;;
      *) cp "$src"/platform/win32/x64/Release/*.lib "$out/" ;;
    esac
    # licenses.sh needs the thirdparty/font lists but must not require the
    # vcxproj files (they're not in the engine cache). Save them here.
    python3 "$root/packaging/windows/mupdf-parts.py" "$src" parts >"$out/parts.txt"
    python3 "$root/packaging/windows/mupdf-parts.py" "$src" fonts >"$out/fonts.txt"
    ls "$out"
    exit 0
    ;;
esac
flags="build=release HAVE_X11=no HAVE_GLUT=no HAVE_CURL=no HAVE_LIBCRYPTO=yes tesseract=yes"
# make does not track flags; a change rebuilds all.
if [ "$(cat "$out/.flags" 2>/dev/null)" != "$flags" ]; then
  rm -rf "$out"
fi
# shellcheck disable=SC2086
make -C "$src" OUT="$out" $flags -j"$jobs" libs "$out/libmupdf-pkcs7.a"
echo "$flags" >"$out/.flags"
