#!/bin/bash
cd "$(dirname "${0}")"

TOUCHSCREEN="/dev/input/by-path/platform-1c2ac00.i2c-event"
VOLUMEKEYS="/dev/input/by-path/platform-1c21800.lradc-event"
VIBR="/dev/input/by-path/platform-vibrator-event"

while true; do
	./detect_pattern.lua "${VOLUMEKEYS}" "+-+-+-"
	./touchpad.lua "${TOUCHSCREEN}" "$(./get_orientation.sh)" "${VIBR}"
	sleep 1
done
