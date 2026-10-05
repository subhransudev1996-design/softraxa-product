#!/bin/bash
# pshot.sh name — full-size phone screenshot into out/ph/name.png
MSYS_NO_PATHCONV=1 adb exec-out screencap -p > "$(dirname "$0")/../out/ph/$1.png"
