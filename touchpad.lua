#!/usr/bin/env lua
local input = require("lua-input")
local time = require("time")
local codes = input.linux.input_event_codes
local gettime = time.monotonic

-- debug print wrapper
local function dprint(...)
	io.write("\027[33m")
	print(...)
	io.write("\027[0m")
end



--[[ Setup Devices ]]--
-- These functions are used to perform the create and setup the uinput devices.

-- open touchscreen device for absolute positions
local x_max, y_max
local function setup_touchscreen(touch_dev)
	-- open and grab the touchscreen.
	dprint("setup_touchscreen", assert(touch_dev))
	local touch = assert(input.linux.new_input_source_linux(touch_dev, true, true), "Can't open touchscreen device!")
	touch:grab(1)
	-- grabbing prevents other applications from using this touchscreen.
	-- We can still forward touch events to other applications via the proxy touchscreen device.

	-- get info on the touch axis
	local x_info = assert(touch:abs_info(codes.ABS_MT_POSITION_X))
	x_max = x_info.maximum

	local y_info = assert(touch:abs_info(codes.ABS_MT_POSITION_Y))
	y_max = y_info.maximum

	return touch
end

-- create mouse device for relative positions/clicks
local function setup_mouse(extra_keys)
	-- create mouse device via /dev/uinput
	local mouse = assert(input.linux.new_input_sink_linux(), "Can't create mouse device!")
	dprint("setup_mouse", mouse)

	-- enable relative mouse movement related events
	mouse:set_bit("EVBIT", codes.EV_REL)
	mouse:set_bit("RELBIT", codes.REL_X)
	mouse:set_bit("RELBIT", codes.REL_Y)

	-- The mouse might also send key events, e.g. left/right mouse button.
	mouse:set_bit("EVBIT", codes.EV_KEY)
	for _, key in ipairs(extra_keys) do
		dprint("Mouse extra key:", key)
		mouse:set_bit("KEYBIT", key)
	end

	-- call the dev_setup function to register the completed mouse
	assert(mouse:dev_setup("Virtual mouse for PinePhone", 0x1234, 0x5678, false))

	return mouse
end

-- (optional) create a new touchscreen device for forwarding touch events
-- (in case no region matches the touchscreen just forwards events)
local function setup_proxy_touchscreen(orig_touchscreen)
	local proxy_touchscreen = assert(input.linux.new_input_sink_linux(), "Can't create proxy touchscreen device!")
	dprint("setup_proxy_touchscreen", orig_touchscreen, proxy_touchscreen)
	assert(proxy_touchscreen:set_bit("EVBIT", codes.EV_KEY))
	assert(proxy_touchscreen:set_bit("KEYBIT", codes.BTN_TOUCH))

	assert(proxy_touchscreen:set_bit("EVBIT", codes.EV_ABS))
	assert(proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_SLOT))
	assert(proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_TRACKING_ID))
	assert(proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_POSITION_X))
	assert(proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_POSITION_Y))

	local x_info = assert(orig_touchscreen:abs_info(codes.ABS_MT_POSITION_X), "Can't get abs_info for x axis")
	assert(proxy_touchscreen:abs_setup(
		codes.ABS_MT_POSITION_X,
		x_info.value,
		x_info.minimum,
		x_info.maximum,
		x_info.fuzz,
		x_info.flat,
		x_info.resolution
	), "abs_setup for ABS_MT_POSITION_X axis failed!")

	local y_info = assert(orig_touchscreen:abs_info(codes.ABS_MT_POSITION_Y), "Can't get abs_info for x axis")
	assert(proxy_touchscreen:abs_setup(
		codes.ABS_MT_POSITION_Y,
		y_info.value,
		y_info.minimum,
		y_info.maximum,
		y_info.fuzz,
		y_info.flat,
		y_info.resolution
	), "abs_setup for ABS_MT_POSITION_Y axis failed!")

	assert(proxy_touchscreen:dev_setup("Virtual touchscreen proxy for PinePhone", 0x2345, 0x6789, false))

	return proxy_touchscreen
end

-- (optionally) open vibrator device for force-feedback
local function pulse() end -- dummy functions for if no vibration motor is specified
local function patt() end
local function setup_vibrator(vibr_dev)
	-- the vibration motor is controlled via an event interface
	local vibr = assert(input.linux.new_input_source_linux(vibr_dev, true, true), "Can't open vibrator device!!")
	dprint("setup_vibrator", assert(vibr))
	--assert(vibr:vibr_gain(0xffff), "Can't set gain!")

	-- add function implementations:

	-- turn on the vibration motor for d seconds
	pulse = function(d)
		dprint("vibrator pulse", d)
		local pulse_effect_id = assert(vibr:vibr_effect(d*1000,0,0, 1), "Can't upload vibrator effect!")
		assert(vibr:vibr_start(pulse_effect_id, 1), "Can't start vibrator effect!")
		time.sleep(d) -- TODO: Keep track of when we don't need this event.
		vibr:vibr_remove(pulse_effect_id)
	end

	-- turn on the vibration in a pattern. Format is true(vibrate)/false(do nothing) followed by delay in s.
	patt = function(...)
		dprint("vibrator patt", ...)
		assert(select("#", ...)%2==0, "Invalid pattern!")
		for i=1, select("#", ...), 2 do
			local set = select(i, ...)
			local d = select(i+1, ...)
			d = assert(tonumber(d))
			if set then
				pulse(d)
			else
				time.sleep(d)
			end
		end
	end

	return vibr
end



--[[ Region functions ]]--
-- Regions define a rectangle and callbacks for events related to that rectangle.

-- create a basic screen region
local function make_region(name, x,y, w,h)
	local region = {
		name = assert(name),
		x = assert(tonumber(x)),
		y = assert(tonumber(y)),
		w = assert(tonumber(w)),
		h = assert(tonumber(h)),
	}
	-- Supported optional callbacks:

	--function region:on_first_pos(region, finger, down_x, down_y) end
	--function region:on_moved(region, finger, new_x, new_y) end
	--function region:on_up(region, finger) end

	return region
end

-- make a region that behaves like a touchpad
local function make_touchpad_region(name, x,y, w,h, mouse)
	local touchpad_region = make_region(name, x,y, w,h)

	-- the mouse device that receives the mouse events from the touchpad
	touchpad_region.mouse = assert(mouse)

	-- sensitivity of the touchpad.
	-- Use only integer for best precision.
	-- TODO: Accumulate error to allow arbitrary precision sensitivity?
	touchpad_region.sensitivity = 1

	-- variables that change the "orientation" of the touchpad relative to the touchscreen
	touchpad_region.transpose = false -- flip x/y coordinates
	touchpad_region.x_sign = 1
	touchpad_region.y_sign = 1

	-- change touchpad orientation(flip coordinate axis)
	function touchpad_region:orientation(orientation)
		dprint("touchpad orientation", orientation)
		if orientation == "right-up" then
			self.transpose = true
			self.y_sign = -1
		elseif orientation == "left-up" then
			self.transpose = true
			self.x_sign = -1
		elseif orientation == "bottom-up" then
			self.x_sign = -1
			self.y_sign = -1
		elseif orientation and (orientation ~= "normal") then
			error("Unknown orientation! Needs to be one of: right-up, left-up, normal")
		end
	end

	-- called when touch was detected and the finger position was obtained
	--luacheck: push ignore self
	function touchpad_region:on_first_pos(finger, down_x, down_y)
		dprint("touchpad fist_pos", self, finger, down_x, down_y)
		finger.last_x, finger.last_y = down_x, down_y
		pulse(0.05)
	end
	--luacheck: pop

	-- called every time the position of a finger was updated. x or y might not be always set.
	function touchpad_region:on_moved(finger, new_x, new_y)
		dprint("touchpad on_moved", self, finger, new_x, new_y)

		-- change coordinate system if orientation demands it
		if self.transpose then
			new_x,new_y = new_y,new_x
			finger.last_x,finger.last_y = finger.last_y,finger.last_x
		end

		-- Create relative mouse movement based on delta of last and current absolute finger position
		if new_x then
			local dx = self.sensitivity * self.x_sign * (new_x-finger.last_x)
			self.mouse:write(codes.EV_REL, codes.REL_X, dx)
			self.mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		end
		if new_y then
			local dy = self.sensitivity * self.y_sign * (new_y-finger.last_y)
			self.mouse:write(codes.EV_REL, codes.REL_Y, dy)
			self.mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		end

		-- undo transform
		if self.transpose then
			new_x,new_y = new_y,new_x
			finger.last_x,finger.last_y = finger.last_y,finger.last_x
		end

		finger.last_x = new_x or finger.last_x
		finger.last_y = new_y or finger.last_y
	end

	-- called when a finger no longer touches the screen
	--luacheck: push ignore self
	function touchpad_region:on_up(finger)
		if (finger.last_x == finger.down.x) and (finger.last_y == finger.down.y) then
			dprint("touchpad tap", self, finger)
			self.mouse:write(codes.EV_KEY, codes.BTN_LEFT, 1)
			self.mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
			pulse(0.07)
			self.mouse:write(codes.EV_KEY, codes.BTN_LEFT, 0)
			self.mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		else
			dprint("touchpad up", self, finger)
			pulse(0.05)
		end
	end
	--luacheck: pop

	return touchpad_region
end

-- make a region that behaves like a key
local function make_key_region(name, x,y, w,h, dev, key)
	local key_region = make_region(name, x,y, w,h)
	key_region.dev = assert(dev)
	key_region.key = assert(key)

	--luacheck: push ignore self
	function key_region:on_first_pos()
		dprint("key_region down", self)
		self.dev:write(codes.EV_KEY, self.key, 1)
		self.dev:write(codes.EV_SYN,codes.SYN_REPORT,0)
		pulse(0.07)
	end
	function key_region:on_up()
		dprint("key_region up", self)
		self.dev:write(codes.EV_KEY, self.key, 0)
		self.dev:write(codes.EV_SYN,codes.SYN_REPORT,0)
		pulse(0.07)
	end
	--luacheck: pop

	return key_region
end

-- check if the position x,y is any of the regions in the regions list,
-- and return first region found.
local function get_region_for_pos(regions, x,y)
	for i=1, #regions do
		local region = assert(regions[i])
		if (x>=region.x) and (y>=region.y) and (x<region.x+region.w) and (y<region.y+region.h) then
			return region
		end
	end
end


-- return a function that handles touchscreen events, and calls
-- the finger callbacks appropriately
local function make_finger_tracker(touch_regions, proxy_touchscreen)
	local finger_tracker = {}
	finger_tracker.touch_regions = touch_regions
	finger_tracker.proxy_touchscreen = proxy_touchscreen

	finger_tracker.slot = 0
	finger_tracker.tracking_id = nil

	function finger_tracker:down(finger_slot)
		dprint("Finger down", finger_slot)
		local finger = self[finger_slot]
		assert(not finger, "Attempted to remove non-existing finger!")
		self[finger_slot] = { time = gettime() }
	end
	function finger_tracker:first_pos(finger_slot)
		local finger = assert(self[finger_slot], "First position for non-existing finger!")
		local region = get_region_for_pos(self.touch_regions, finger.x, finger.y)
		dprint("First pos ", finger_slot, finger.x, finger.y, region and region.name or "PROXY area(ignore)")
		finger.down = {x=finger.x, y=finger.y}
		if region then
			finger.region = region
			if region.on_first_pos then
				region:on_first_pos(finger, finger.x, finger.y)
			end
		elseif self.proxy_touchscreen then
			self:proxy_first_pos(finger_slot, self.tracking_id, finger.x, finger.y)
		end
	end
	function finger_tracker:moved(finger_slot, x, y)
		local finger = assert(self[finger_slot], "non-existing finger moved!")
		finger.x = x or finger.x
		finger.y = y or finger.y

		if finger.x and finger.y and (not finger.down) then
			return self:first_pos(finger_slot)
		end

		if finger.down and finger.region and finger.region.on_moved then
			finger.region:on_moved(finger, x,y)
		elseif finger.down and (not finger.region) and self.proxy_touchscreen then
			self:proxy_moved(finger_slot, x,y)
		end
		--dprint("Finger moved", finger_slot, self[finger_slot].x, self[finger_slot].y)
	end
	function finger_tracker:up(finger_slot)
		dprint("Finger up", finger_slot)
		local finger = assert(self[finger_slot], "non-existing finger released!")

		if finger.region and finger.region.on_up then
			finger.region:on_up(finger)
		elseif (not finger.region) and self.proxy_touchscreen then
			self:proxy_up(finger_slot)
		end

		self[finger_slot] = nil
	end

	function finger_tracker:proxy_first_pos(finger_slot, tracking_id, x, y)
		dprint("PROXY on_first_pos", finger_slot, tracking_id, x, y)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_TRACKING_ID, tracking_id)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_X, x)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_Y, y)
		self.proxy_touchscreen:write(codes.EV_SYN, codes.SYN_REPORT, 0)
	end
	function finger_tracker:proxy_moved(finger_slot, x ,y)
		dprint("PROXY on_moved", finger_slot, x, y)
		if x then
			self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
			self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_X, x)
			self.proxy_touchscreen:write(codes.EV_SYN,codes.SYN_REPORT,0)
		end
		if y then
			self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
			self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_Y, y)
			self.proxy_touchscreen:write(codes.EV_SYN,codes.SYN_REPORT,0)
		end
	end
	function finger_tracker:proxy_up(finger_slot)
		dprint("PROXY on_up", finger_slot)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
		self.proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_TRACKING_ID, -1)
		self.proxy_touchscreen:write(codes.EV_SYN, codes.SYN_REPORT, 0)
	end

	function finger_tracker:handle_touch_ev(touch_ev)
		if not touch_ev.type == codes.EV_ABS then
			return
		end

		if touch_ev.code == codes.ABS_MT_TRACKING_ID then
			dprint("tracking_id", touch_ev.value)
			self.tracking_id = touch_ev.value
			if (touch_ev.value == -1) and self.tracking_id then
				self:up(self.slot)
			else
				self:down(self.slot)
			end
		elseif touch_ev.code == codes.ABS_MT_SLOT then
			dprint("slot", touch_ev.value)
			self.slot = touch_ev.value
		elseif touch_ev.code == codes.ABS_MT_POSITION_X then
			self:moved(self.slot, touch_ev.value, nil)
		elseif touch_ev.code == codes.ABS_MT_POSITION_Y then
			self:moved(self.slot, nil, touch_ev.value)
		end
	end

	return finger_tracker
end



local touch_dev = assert(arg[1], "First argument needs to be the touchscreen device(/dev/input/eventXX)!")
local orientation = assert(arg[2], "Second argument needs to be the orientation(right-up, left-up, bottom-up, normal)")
local vibr_dev = assert(arg[3], "Third argument needs to be the vibrator device(/dev/input/eventXX)!")

dprint("Aquiring required devices...")

-- open the main touchscreen input device
local touch = setup_touchscreen(touch_dev)
--touch = debug_wrap_device(touch, "\027[34mTOUCH")

-- create a new touchscreen device as "proxy target"
local proxy_touchscreen = setup_proxy_touchscreen(touch)
--proxy_touchscreen = debug_wrap_device(proxy_touchscreen, "\027[36mPROXY")

-- open the vibration motor for force feedback
setup_vibrator(vibr_dev)
--vibr = debug_wrap_device(vibr, "VIBR")

-- create mouse device(depends on extra_keys created by make_key_region) for touchpad
local extra_keys = {codes.BTN_LEFT, codes.BTN_RIGHT}
local mouse = setup_mouse(extra_keys)
--mouse = debug_wrap_device(mouse, "\027[35mMOUSE")

-- create the touch region for the touchpad
local touchpad_region = make_touchpad_region("touchpad", 0,60, x_max,850, mouse)
touchpad_region:orientation(orientation) -- use the correct orientation if provided

-- create left mouse button region in top-left corner
local lmb_region = make_key_region("lmb", 0,0, x_max*0.5,60, mouse, codes.BTN_LEFT)

-- create right mouse button region in top-right corner
local rmb_region = make_key_region("rmb", x_max*0.5,0, x_max*0.5,60, mouse, codes.BTN_RIGHT)

-- create bottom button region for quitting
local bottom_region = make_region("bottom", 0,y_max-90,x_max,90)
--luacheck: push ignore self
function bottom_region:on_first_pos()
	dprint("Bottom pressed, bye!")
	patt(true,0.1,  false,0.2,  true,0.1,  false,0.2, true,0.1)
	os.exit(0)
end
--luacheck: pop



-- this defines the regions the finger touch positions are checked against:
local touch_regions = {
	touchpad_region,
	lmb_region,
	rmb_region,
	bottom_region,
}



-- create a "finger tracker"
-- calls region callbacks based on touchscreen events associated with fingers,
-- and their associated regions.
-- This is the main dispatch algorithm.
local finger_tracker = make_finger_tracker(touch_regions, proxy_touchscreen)



-- greeting the user
patt(true,0.1,  false,0.2,  true,0.1,  false,0.2, true,0.1)
print("Touchpad ready!")
dprint("Entering main event loop...")

-- simple blocking "event loop"
while true do
	local touch_ev = assert(touch:read(), "Can't read from touch device!")
	finger_tracker:handle_touch_ev(touch_ev)
end
