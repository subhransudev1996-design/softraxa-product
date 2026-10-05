#!/bin/bash
# phone.sh — records a short phone billing clip: Maggi sold by the Box, then the cart.
export MSYS_NO_PATHCONV=1
T="bash tools/t.sh"
adb shell rm -f /sdcard/p.mp4
adb shell screenrecord --time-limit 24 --bit-rate 12000000 /sdcard/p.mp4 &
sleep 2
$T 200 136; sleep 1; adb shell input text maggi; sleep 1.8
adb shell input keyevent 4; sleep 1
$T 225 277; sleep 2.2
$T 327 361; sleep 2.2          # Box (12 pcs)
$T 225 570; sleep 3            # Add
sleep 6
wait
adb pull /sdcard/p.mp4 public/raw/phone.mp4
