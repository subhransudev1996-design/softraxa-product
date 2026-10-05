#!/bin/bash
ffmpeg -y -loglevel error -f gdigrab -framerate 1 -draw_mouse 0 -video_size 1920x1028 -i desktop -frames:v 1 "$1"
