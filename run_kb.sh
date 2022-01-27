#!/bin/bash
cd "$(dirname "${0}")"

TOUCHSCREEN="/dev/input/by-path/platform-1c2ac00.i2c-event"
KEYBOARD="/dev/input/by-path/platform-1c2b400.i2c-event-kbd"

sudo ./touchpad_keyboard.lua "${TOUCHSCREEN}" "${KEYBOARD}" right-up
