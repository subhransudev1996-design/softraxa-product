#!/bin/bash
# t.sh X Y — tap at a point given on the 450x1000 preview (x2.8 = the phone's 1260x2800)
adb shell input tap $(( $1 * 28 / 10 )) $(( $2 * 28 / 10 ))
