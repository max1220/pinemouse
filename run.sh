#!/bin/bash
set -e

TOUCHSCREEN="/dev/input/by-path/platform-1c2ac00.i2c-event"
VOLUMEKEYS="/dev/input/by-path/platform-1c21800.lradc-event"

while true; do
	./detect_pattern.lua "${VOLUMEKEYS}" "+-+-+-"
	./touchpad.lua "${TOUCHSCREEN}" "${VOLUMEKEYS}"
done
