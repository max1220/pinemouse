# pinemouse

A simple set of tools to help you use the PinePhones touchscreen as a
touchpad(with volume keys for left/right mouse buttons).



## Installation

This setup requires two of my Lua libraries,
 * lua-input
  - for reading kernel input events and creating new input devices
  - requires v2 branch!
 * lua-time
  - for sleep and getting time

### Mobian(untested):
```
sudo apt update -y
sudo apt install -y build-essentials git lua5.1 lua5.1-dev iblua5.1-0-dev

git clone -b v2 https://github.com/max1220/lua-input
cd lua-input
make clean all
sudo make install
cd ..

git clone https://github.com/max1220/lua-time
cd lua-time
make clean all
sudo make install
cd ..
```


## Usage

You can use the `run.sh` script to enable touchpad mode automatically when
a button sequence is detected(default is `+-+-+-`).

You can also run the `touchpad.lua` script directly.
First argument needs to be the touchscreen device(e.g. `/dev/input/event2`),
second argument needs to be the volume-keys device(e.g. `/dev/input/event1`),
