#!/bin/sh
# Run from any directory. Builds only this companion in its ignored .build directory.
set -eu
cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
mkdir -p .build
# pkg-config output intentionally expands to compiler/linker arguments.
# shellcheck disable=SC2046
cc -std=c11 -O2 -g -Wall -Wextra -Werror $(pkg-config --cflags libavformat libavcodec libavutil) -c bridge.c -o .build/bridge.o
ar rcs .build/bridge.a .build/bridge.o
odin build . -out:.build/media
