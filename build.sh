#!/usr/bin/env bash
# Builds MeetOwned's LGPL-only FFmpeg for 64-bit Windows.
#
# Runs in an MSYS2 MINGW64 shell (the GitHub workflow uses one; so can you,
# see README.md). Everything it makes lands in ./dist:
#   meetowned-ffmpeg-<version>-lgpl-win64-shared.zip   bin/ with the exes,
#                                                      the DLLs and the licence
#   ...zip.sha256                                      its SHA-256
#   ffmpeg-<version>.tar.xz (+ .asc)                   the exact source built
#   build.log                                          configure and make output
#   release-notes.md                                   buildconf and component lists
set -euo pipefail

FFMPEG_VERSION="9.0.2"
# SHA-256 of https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz. Its .asc was
# checked against the FFmpeg release signing key
# FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8 before this was pinned.
FFMPEG_SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"

# The configure line. Every component is named; nothing is autodetected.
# --enable-mediafoundation and --enable-w32threads come after
# --disable-autodetect, which would otherwise switch both off (the ffmpeg
# program will not build without a thread library).
CONFIGURE_FLAGS=(
  --arch=x86_64
  --target-os=mingw32
  --enable-shared
  --disable-static
  --disable-autodetect
  --enable-mediafoundation
  --enable-w32threads
  --disable-network
  --disable-doc
  --disable-debug
  --disable-everything
  --enable-protocol=file,pipe
  --enable-demuxer=rawvideo,mov,mp3,amr,ogg,wav,aac,matroska,image2,flac,avi,asf
  --enable-muxer=mp4,ipod,wav,rawvideo,image2
  --enable-decoder=h264,aac,mp3,mp3float,amrnb,amrwb,opus,vorbis,pcm_s16le,pcm_s24le,pcm_s32le,pcm_u8,pcm_f32le,rawvideo,flac,alac,wmav1,wmav2,ac3,eac3,pcm_alaw,pcm_mulaw,adpcm_ms,adpcm_ima_wav,bmp
  --enable-encoder=h264_mf,aac,pcm_s16le,rawvideo,mjpeg
  --enable-parser=h264,aac,mpegaudio,opus,vorbis,amr,flac,ac3
  --enable-bsf=aac_adtstoasc,h264_mp4toannexb,extract_extradata,null
  --enable-filter=amix,aresample,aformat,scale,format,fps,trim,atrim,null,anull
  --enable-indev=gdigrab
  --enable-swscale
  --enable-swresample
  --enable-ffmpeg
  --enable-ffprobe
  --disable-ffplay
)

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="$ROOT/work"
DIST="$ROOT/dist"
PREFIX="$WORK/prefix"
NAME="meetowned-ffmpeg-${FFMPEG_VERSION}-lgpl-win64-shared"
TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
LOG="$DIST/build.log"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST"
exec > >(tee -a "$LOG") 2>&1

fail() { echo "FAILED: $*"; exit 1; }

echo "== toolchain"
gcc --version | head -1
nasm --version
uname -a

echo "== source"
curl -fsSL --retry 5 -o "$DIST/$TARBALL" "https://ffmpeg.org/releases/$TARBALL"
curl -fsSL --retry 5 -o "$DIST/$TARBALL.asc" "https://ffmpeg.org/releases/$TARBALL.asc"
echo "$FFMPEG_SHA256 *$DIST/$TARBALL" | sha256sum -c - || fail "source tarball does not match its pinned SHA-256"
tar -xJf "$DIST/$TARBALL" -C "$WORK"
SRC="$WORK/ffmpeg-$FFMPEG_VERSION"

echo "== configure"
cd "$SRC"
./configure --prefix="$PREFIX" "${CONFIGURE_FLAGS[@]}" | tee "$WORK/configure.out" \
  || { tail -50 ffbuild/config.log; fail "configure"; }

echo "== licence checks on the configuration"
for flag in GPL NONFREE VERSION3; do
  grep -q "^#define CONFIG_${flag} 0$" config.h || fail "CONFIG_${flag} is not 0"
done
grep -q '^License: LGPL version 2.1 or later$' "$WORK/configure.out" \
  || fail "configure did not report LGPL version 2.1 or later"
# The external library sections configure prints: the plain one must be
# empty, and the hardware one may hold only Windows' own Media Foundation.
section() { awk -v h="$1" '$0==h{f=1;next} f&&/^$/{exit} f' "$WORK/configure.out" | tr -s ' \n' ' ' | sed 's/^ *//;s/ *$//'; }
ext="$(section 'External libraries:')"
hw="$(section 'External libraries providing hardware acceleration:')"
echo "External libraries: [${ext}]"
echo "External libraries providing hardware acceleration: [${hw}]"
[ -z "$ext" ] || fail "external libraries enabled: $ext"
[ "$hw" = "mediafoundation" ] || fail "unexpected hardware libraries: $hw"

echo "== build"
make -j"$(nproc)"
make install

echo "== package"
PKG="$WORK/pkg"
mkdir -p "$PKG/bin"
cp "$PREFIX"/bin/ffmpeg.exe "$PREFIX"/bin/ffprobe.exe "$PREFIX"/bin/*.dll "$PKG/bin/"
cp "$SRC/COPYING.LGPLv2.1" "$PKG/bin/"
cat > "$PKG/bin/SOURCE.txt" <<EOF
This is FFmpeg ${FFMPEG_VERSION}, built for MeetOwned under the GNU Lesser
General Public License version 2.1 or later (COPYING.LGPLv2.1).

The exact source it was built from, the build log and the build script are
published with each release of
https://github.com/${GITHUB_REPOSITORY:-amirtaylor1111-source/meetowned-ffmpeg-build}/releases
EOF

echo "== imports: every DLL must be one of ours or a Windows system DLL"
ours="$(cd "$PKG/bin" && ls *.dll | tr 'A-Z' 'a-z')"
for f in "$PKG"/bin/*.exe "$PKG"/bin/*.dll; do
  for dll in $(objdump -p "$f" | awk '/DLL Name:/{print $3}'); do
    lower="$(echo "$dll" | tr 'A-Z' 'a-z')"
    if echo "$ours" | grep -qx "$lower"; then continue; fi
    [ -e "/mingw64/bin/$dll" ] && fail "$(basename "$f") imports $dll from the MinGW toolchain"
    echo "$(basename "$f") -> $dll (system)"
  done
done | sort -u

echo "== what was built"
FF="$PKG/bin/ffmpeg.exe"
"$FF" -hide_banner -buildconf > "$WORK/buildconf.txt"
cat "$WORK/buildconf.txt"
for bad in --enable-gpl --enable-nonfree --enable-version3 --enable-lib; do
  grep -q -- "$bad" "$WORK/buildconf.txt" && fail "buildconf carries $bad"
done
"$FF" -hide_banner -L | grep -q "GNU Lesser General Public" || fail "ffmpeg -L is not the LGPL"
for kind in encoders decoders muxers demuxers filters; do
  "$FF" -hide_banner -$kind > "$WORK/$kind.txt"
done
"$FF" -hide_banner -encoders | grep -q ' h264_mf ' || fail "no h264_mf encoder"
"$PKG/bin/ffprobe.exe" -hide_banner -version | head -1

(cd "$WORK/pkg" && zip -9 -r "$DIST/$NAME.zip" bin)
(cd "$DIST" && sha256sum "$NAME.zip" | sed 's/ \*/  /' > "$NAME.zip.sha256")
cat "$DIST/$NAME.zip.sha256"

{
  echo "FFmpeg ${FFMPEG_VERSION} for MeetOwned: LGPL version 2.1 or later, shared, 64-bit Windows."
  echo
  echo "Built by \`build.sh\` at commit ${GITHUB_SHA:-local} on ${RUNNER_OS:-local}. The source tarball attached is the one built (SHA-256 \`$FFMPEG_SHA256\`, signed by the FFmpeg release key; the \`.asc\` is attached)."
  echo
  echo "Zip SHA-256: \`$(cut -d' ' -f1 "$DIST/$NAME.zip.sha256")\`"
  echo
  for part in buildconf encoders muxers filters decoders demuxers; do
    echo "<details><summary>ffmpeg -$part</summary>"
    echo
    echo '```'
    cat "$WORK/$part.txt"
    echo '```'
    echo "</details>"
    echo
  done
} > "$DIST/release-notes.md"

echo "== done"
ls -la "$DIST"
