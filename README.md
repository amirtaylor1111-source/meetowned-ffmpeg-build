# meetowned-ffmpeg-build

The script that builds the FFmpeg shipped inside MeetOwned, and nothing else.
No application code lives here.

## What it builds

FFmpeg **9.0.2** (tag `n9.0.2`), from the release tarball
`https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz`, SHA-256
`8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e`. That
tarball's signature was checked against the FFmpeg release signing key
(`FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8`) before the hash was
pinned in `build.sh`, and the build refuses any other bytes.

It is a minimal, shared (DLL) build for 64-bit Windows, configured with
`--disable-everything --disable-autodetect` and then only the components
MeetOwned uses. Nothing outside FFmpeg is compiled in: no external libraries,
no GPL or non-free parts. The outside dependencies are Windows' own Media
Foundation, through which the `h264_mf` encoder makes H.264 video, and
Windows' own Direct3D 11 (`--enable-d3d11va`), which FFmpeg 9.0.2's
`h264_mf` source needs in order to compile at all.

The full configure line is in [`build.sh`](build.sh). In short:

| Kind | Enabled |
|---|---|
| Encoders | h264_mf, aac, pcm_s16le, rawvideo, mjpeg |
| Decoders | h264, aac, mp3, mp3float, amrnb, amrwb, opus, vorbis, flac, alac, wmav1, wmav2, ac3, eac3, pcm (s16le, s24le, s32le, u8, f32le, alaw, mulaw), adpcm_ms, adpcm_ima_wav, rawvideo, bmp |
| Demuxers | rawvideo, mov, mp3, amr, ogg, wav, aac, matroska, image2, flac, avi, asf |
| Muxers | mp4, ipod, wav, rawvideo, image2 |
| Filters | amix, aresample, aformat, scale, format, fps, trim, atrim, null, anull |
| Other | file and pipe protocols, gdigrab input, swscale, swresample, ffmpeg and ffprobe (no ffplay), no network |

Each release's notes print `ffmpeg -buildconf` and the encoder, decoder,
muxer, demuxer and filter lists of the binary actually built.

## Licence

FFmpeg built this way is under the **GNU Lesser General Public License,
version 2.1 or later** (LGPL-2.1-or-later). The build checks this rather than
assuming it: it fails if `config.h` has GPL, non-free or version 3 switched
on, if configure does not report "LGPL version 2.1 or later", if any external
library other than Media Foundation (and D3D11 for hardware) is enabled, if
`ffmpeg -buildconf` carries `--enable-gpl`, `--enable-nonfree`,
`--enable-version3` or any `--enable-lib...`, or if any exe or DLL imports a
DLL from the MinGW toolchain rather than from FFmpeg itself or Windows.

One piece of toolchain code is linked in: mingw-w64's winpthreads, linked
statically so that no toolchain DLL has to ship. It is under a permissive
MIT-style licence, whose text is `COPYING.winpthreads.txt` in the zip.

`COPYING.LGPLv2.1` is inside every zip, beside the DLLs. The build script in
this repository is offered under the same licence.

## Source offer

Every release carries, beside the binary zip:

- `ffmpeg-9.0.2.tar.xz`, the exact source built, and its `.asc` signature;
- `build.log`, the full configure and make output;
- the commit of this repository that built it, so `build.sh` and the
  workflow are the ones that ran.

They stay attached to the release for as long as the binary does.

## Reproducing it

On GitHub: fork this repository and run the **build** workflow
(Actions, build, Run workflow). It runs on `windows-latest` with MSYS2's
MINGW64 toolchain and publishes a release.

On your own Windows machine:

1. Install [MSYS2](https://www.msys2.org/) and open its **MINGW64** shell.
2. `pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf make diffutils curl tar xz zip`
3. `bash build.sh`

Everything lands in `dist/`. The zip holds `bin/` with `ffmpeg.exe`,
`ffprobe.exe`, the FFmpeg DLLs, `COPYING.LGPLv2.1` and `SOURCE.txt`; its
SHA-256 is in the `.sha256` file beside it. The compiler version is in the
first lines of `build.log`; a different compiler version gives different
bytes but the same configuration.
