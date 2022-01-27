#!/bin/bash
RESP="$(gdbus call --system --dest net.hadess.SensorProxy --object-path /net/hadess/SensorProxy --method org.freedesktop.DBus.Properties.Get net.hadess.SensorProxy AccelerometerOrientation)"
ORIENT="${RESP:3:-4}"

if [ "${ORIENT}" = "" ]; then
        echo normal
elif [ "${ORIENT}" = "undefined" ]; then
        echo normal
else
        echo "${ORIENT}"
fi
