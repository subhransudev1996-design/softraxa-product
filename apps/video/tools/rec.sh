#!/bin/bash
# rec.sh out.mp4 seconds [WxH]  — records the screen's top-left WxH (default
# 1920x1028, the maximized app) at 30 fps without the mouse pointer.
ffmpeg -hide_banner -loglevel error -y -f gdigrab -framerate 30 -draw_mouse 0 -offset_x 0 -offset_y 0 -video_size "${3:-1920x1028}" -t "$2" -i desktop -c:v libx264 -preset ultrafast -crf 14 -pix_fmt yuv420p "$1"
