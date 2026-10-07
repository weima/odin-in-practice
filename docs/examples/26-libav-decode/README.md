# Native decode and remux companion

This package covers the [foreign binding](../../chapters/ffmpeg-libav.md#libav-probe), [decoder](../../chapters/ffmpeg-libav.md#libav-decode), and [ownership/timestamp](../../chapters/ffmpeg-libav.md#libav-design) lessons. The narrow C bridge owns FFmpeg structure access; the Odin caller does not guess native layouts.

## Prerequisites and build

Linux, the pinned Odin compiler, a C11 compiler, `ar`, `pkg-config`, and FFmpeg **6.x development headers/libraries** are required: libavformat major 60, libavcodec 60, libavutil 58. A newer major is not established compatible just because it is installed. Inspect `pkg-config --modversion libavformat libavcodec libavutil`.

From the repository root:

```sh
sh docs/examples/26-libav-decode/build.sh
TZ=UTC odin test docs/examples/26-libav-decode
```

The script can be called from any directory and writes only `.build/` beside the source. Native artifacts are ignored, not published.

## Use

```sh
# Absolute regular local input; frame budget defaults to 10000.
docs/examples/26-libav-decode/.build/media decode /absolute/input.wav
# Output must not already exist; the bridge stages before publication.
docs/examples/26-libav-decode/.build/media remux /absolute/input.mp4 /absolute/output.part
```

The bridge uses a file-only protocol whitelist, rejects the final input symlink, checks the ABI/report size, bounds execution/output, retries the same decoder packet after send-side EAGAIN, and drains delayed frames at EOF. Remux rescales timestamps to the muxer's stream time base and checks trailer/flush/sync/close before publishing. Errors invalidate partial success output. These are bounded local-file examples, not a hardened arbitrary-upload service or a complete transcoder.

## Integration checks

The portable [verification harness](verify.py) needs `/usr/bin/ffmpeg`, `/usr/bin/ffprobe`, `valgrind`, Python's standard library, and the built executable. It creates small synthetic WAV/MKV/MP4 fixtures in a temporary directory, not production media:

```sh
python3 docs/examples/26-libav-decode/verify.py
```

Sixteen scenarios passed in the authoring Linux environment: decode counts against ffprobe; corrupt/missing inputs and frame budgets; URL/relative/final-symlink/nested-network rejection; remux stream/frame/timestamp checks; existing-output preservation; and no Valgrind-reported errors/definite leaks for the tested decode/remux cases. The one Odin test also passed with memory tracking.

This does not establish every codec/container, operating system, schedule, or malformed file. The fixture needs an FFmpeg build that enables the listed lavfi sources and MPEG-4 encoder; missing tools/codecs are prerequisites to resolve, not evidence that the companion passed.
