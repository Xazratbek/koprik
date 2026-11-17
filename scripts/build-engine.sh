#!/bin/bash
# Builds Ko'prik's own Wine engine: Wine 11.19 with CrossOver 26.3's patches
# (the dappermint/winecx tree that frankea/winecx-gptk also builds), packaged
# in the same Libraries/ layout Ko'prik already installs, plus DXMT, DXVK and
# MoltenVK.
#
# Runs on an Apple silicon Mac with Rosetta. The unix half of Wine is built as
# x86_64 against an Intel Homebrew in /usr/local; the Windows half is built
# with mingw-w64 from the native Homebrew. Expect one to three hours.
#
# Usage: scripts/build-engine.sh [output-dir]
# Environment overrides: WINECX_COMMIT, JOBS.
set -euo pipefail

OUT=${1:-"$PWD/build/engine"}
WINECX_REPO=https://github.com/dappermint/winecx.git
WINECX_COMMIT=${WINECX_COMMIT:-9f3f6447844add700bc0dde650e4f398fd5f69ab}
DXMT_VERSION=0.80
DXVK_TAG=v1.10.3-20230507-repack
MOLTENVK_VERSION=1.4.2
RUNTIME_VERSION=${RUNTIME_VERSION:-0.1.0}
JOBS=${JOBS:-$(( $(sysctl -n hw.ncpu) + 2 ))}
X86_BREW=/usr/local/bin/brew
X86_DEPS=(freetype gnutls gstreamer gst-plugins-base gst-plugins-good gst-libav sdl2 molten-vk pkgconf bison flex)

WORK="$OUT/work"
mkdir -p "$WORK"
cd "$WORK"

step() { printf '\n==> %s\n' "$*"; }

step "Checking Rosetta"
arch -x86_64 /usr/bin/true || softwareupdate --install-rosetta --agree-to-license

step "Native tools (mingw-w64 for the Windows half)"
brew install mingw-w64 ccache bison flex freetype pkgconf >/dev/null

step "Intel Homebrew and x86_64 libraries"
if [ ! -x "$X86_BREW" ]; then
  arch -x86_64 /bin/bash -c "NONINTERACTIVE=1 $(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
arch -x86_64 "$X86_BREW" install "${X86_DEPS[@]}"
X86_PREFIX=$(arch -x86_64 "$X86_BREW" --prefix)

step "Wine source ($WINECX_COMMIT)"
if [ ! -d winecx ]; then
  git clone --filter=blob:none "$WINECX_REPO" winecx
fi
git -C winecx fetch --depth 1 origin "$WINECX_COMMIT"
git -C winecx checkout --force "$WINECX_COMMIT"

export PATH="$(brew --prefix bison)/bin:$(brew --prefix flex)/bin:$PATH"

step "Build tools (native, so they do not run thousands of times under Rosetta)"
mkdir -p build-tools
( cd build-tools && ../winecx/configure --enable-archs=i386,x86_64 --without-x --without-wayland \
    --without-gstreamer --without-gnutls --disable-tests >/dev/null && make -j"$JOBS" __tooldeps__ )
# wrc looks for nls/locale.nls beside its own build tree, which an
# out-of-tree build does not have ("Error: unable to load locale.nls").
( cd build-tools && { make nls/locale.nls >/dev/null 2>&1 || true; } )
[ -e build-tools/nls/locale.nls ] || { rm -rf build-tools/nls; ln -s "$WORK/winecx/nls" build-tools/nls; }
ls -la build-tools/nls/locale.nls

step "Configuring Wine for x86_64"
mkdir -p build
cd build
export SDKROOT=$(xcrun --show-sdk-path)
export MACOSX_DEPLOYMENT_TARGET=15.0
export CC="ccache clang -arch x86_64"
export CXX="ccache clang++ -arch x86_64"
export PKG_CONFIG_PATH="$X86_PREFIX/lib/pkgconfig:$X86_PREFIX/share/pkgconfig"
export CPPFLAGS="-I$X86_PREFIX/include"
export LDFLAGS="-L$X86_PREFIX/lib"
export CFLAGS="-O2 -Wno-error=implicit-function-declaration"
export ac_cv_func_pipe2=no
arch -x86_64 ../winecx/configure \
  --host=x86_64-apple-darwin24 \
  --with-wine-tools=../build-tools \
  --enable-archs=i386,x86_64 \
  --disable-tests --without-x --without-wayland --without-oss --without-alsa --without-pulse \
  --without-sane --without-usb --without-v4l2 --without-pcap --without-capi --without-cups \
  --prefix=/opt/koprik-wine | tail -25

step "Building Wine ($JOBS jobs)"
arch -x86_64 make -j"$JOBS"
step "Installing into staging"
arch -x86_64 make -j"$JOBS" install-lib DESTDIR="$WORK/staging"
cd "$WORK"

step "Packaging"
PKG="$OUT/Libraries"
rm -rf "$PKG"
mkdir -p "$PKG/Wine" "$PKG/DXMT" "$PKG/DXVK"
cp -R staging/opt/koprik-wine/{bin,lib,share} "$PKG/Wine/"
ln -sf ../lib/wine/x86_64-unix/wine "$PKG/Wine/bin/wine64"

# Runtime libraries Wine loads through @loader_path/../../ (the lib folder).
for lib in libMoltenVK.dylib libSDL2-2.0.0.dylib libfreetype.6.dylib libgnutls.30.dylib; do
  found=$(find "$X86_PREFIX/lib" "$X86_PREFIX/opt"/*/lib -maxdepth 1 -name "$lib" 2>/dev/null | head -1)
  [ -n "$found" ] && cp -L "$found" "$PKG/Wine/lib/"
done
mkdir -p "$PKG/Wine/lib/external"
printf 'Apple Game Porting Toolkit files are imported here by Ko'"'"'prik (Settings > Graphics).\n' > "$PKG/Wine/lib/external/README"

step "DXMT $DXMT_VERSION"
curl -fsSL -o dxmt.tar.gz "https://github.com/3Shain/dxmt/releases/download/v$DXMT_VERSION/dxmt-v$DXMT_VERSION-builtin.tar.gz"
mkdir -p dxmt && tar -xzf dxmt.tar.gz -C dxmt
cp dxmt/*/x86_64-windows/*.dll "$PKG/DXMT/" 2>/dev/null || true
mkdir -p "$PKG/DXMT/x64" "$PKG/DXMT/x32"
cp dxmt/*/x86_64-windows/*.dll "$PKG/DXMT/x64/" 2>/dev/null || true
cp dxmt/*/i386-windows/*.dll "$PKG/DXMT/x32/" 2>/dev/null || true
cp dxmt/*/x86_64-unix/winemetal.so "$PKG/Wine/lib/wine/x86_64-unix/" 2>/dev/null || true
cp dxmt/*/x86_64-windows/winemetal.dll "$PKG/Wine/lib/wine/x86_64-windows/" 2>/dev/null || true

step "DXVK $DXVK_TAG"
curl -fsSL -o dxvk.tar.gz "https://github.com/Gcenx/DXVK-macOS/releases/download/$DXVK_TAG/dxvk-macOS-async-${DXVK_TAG#v}.tar.gz" || true
if [ -s dxvk.tar.gz ]; then
  mkdir -p dxvk && tar -xzf dxvk.tar.gz -C dxvk
  mkdir -p "$PKG/DXVK/x64" "$PKG/DXVK/x32"
  cp dxvk/*/x64/*.dll "$PKG/DXVK/x64/" 2>/dev/null || true
  cp dxvk/*/x32/*.dll "$PKG/DXVK/x32/" 2>/dev/null || true
fi

cat > "$PKG/KoprikEngine.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>gptkCapable</key><true/>
  <key>dxmtVersion</key><string>$DXMT_VERSION</string>
  <key>dxvkVersion</key><string>1.10.3</string>
  <key>wineSource</key><string>$WINECX_REPO@$WINECX_COMMIT</string>
  <key>version</key><string>$RUNTIME_VERSION</string>
</dict></plist>
EOF

step "Checking the result"
"$PKG/Wine/bin/wine" --version

tar -C "$OUT" -czf "$OUT/Libraries.tar.gz" Libraries
shasum -a 256 "$OUT/Libraries.tar.gz" | tee "$OUT/Libraries.tar.gz.sha256"
echo "Done: $OUT/Libraries.tar.gz"
