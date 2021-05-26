# pinemouse

A simple set of tools to help you use the PinePhones touchscreen as a
touchpad(with volume keys for left/right mouse buttons).



## Installation

This setup requires two of my Lua libraries,
 * lua-input
   - for reading kernel input events and creating new input devices
   - requires `vibr` branch!
   - requires kernel headers
     * you might be able to get away with your hosts, you only need one file
 * lua-time
   - for sleep and getting time



### Mobian:
```
sudo apt update -y
sudo apt install -y build-essentials git lua5.1 lua5.1-dev liblua5.1-0-dev

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


### Current default Layout

![Touchscreen regions colored in](/touch_regions.png)

(In the picture: Green is LMB, Blue is RMB, Pink is Touchpad region, Cyan is unaffected region, Red is quit touchpad)


### Customize Layout

You can easily customize the layout, and add custom keys or actions.

The default layout is created like this in the code(x_max and y_max are maximum coordinates of the touchscreen). See the bottom of `touchpad.lua`:
```
-- create the touch region for the touchpad
local touchpad_region = make_touchpad_region("touchpad", 0,60, x_max,850, mouse)
touchpad_region:orientation(orientation) -- use the correct orientation if provided

-- create left mouse button region in top-left corner
local lmb_region = make_key_region("lmb", 0,0, x_max*0.5,60, mouse, codes.BTN_LEFT)

-- create right mouse button region in top-right corner
local rmb_region = make_key_region("rmb", x_max*0.5,0, x_max*0.5,60, mouse, codes.BTN_RIGHT)

-- create bottom button region for quitting
local bottom_region = make_region("bottom", 0,y_max-90,x_max,90)
function bottom_region:on_first_pos()
	dprint("Bottom pressed, bye!")
	patt(true,0.1,  false,0.2,  true,0.1,  false,0.2, true,0.1)
	os.exit(0)
end

-- this defines the regions the finger touch positions are checked against:
local touch_regions = {
	touchpad_region,
	lmb_region,
	rmb_region,
	bottom_region,
}
```

The layout is mostly concerned with regions:
A region is a rectangle in the touchscreen coordinate system with associated
callbacks.

The simplest example is the `bottom_region`: It creates a region with no
default callbacks using `make_region(name, x,y, w,h)`.
We then set a callback for the first position of a finger
("Finger down in this region"): vibrate in a short pattern, then quit.
All other callbacks are not set.

The left and right mouse buttons are created by the `make_key_region(name, x,y, w,h, device, code)`.
This function creates a region using `make_region` and assigns callbacks for
sending the specified key code to the specified device.
If you want to add buttons other than LMB/RMB you also need to add them to
the `extra_keys` table before it's used by the `setup_mouse` function.

The `make_touchpad_region(name, x,y, w,h, mouse_dev)` creates a region using
`make_region`, and assigns callbacks that when called send events to a relative
input device("mouse").

When a region is "entered" by a finger all further events from
that finger will be forwarded to the callbacks of that region,
even if it's outside of the region rectangle.
When an event can't be associated with a region on finger down,
it and all further events from that finger are forwarded to the `proxy_touchscreen`.
This means that a region without callbacks still "blocks" the proxying
events to the `proxy_touchscreen`.



# TODO

 * create a statically linked version that includes all dependencies
   - use luastatic? `lua5.1`, `lua-db`, `lua-time`
