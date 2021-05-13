#!/bin/bash

TOUCHSCREEN="/dev/input/event2"
VOLUMEKEYS="/dev/input/event1"

while true; do
	./detect_pattern.lua "${VOLUMEKEYS}" "+-+-+-"
	./touchpad.lua "${TOUCHSCREEN}" "${VOLUMEKEYS}"
done
