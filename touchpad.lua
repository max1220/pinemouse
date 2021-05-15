#!/usr/bin/env lua5.1
local input = require("lua-input")
local time = require("time")
local codes = input.linux.input_event_codes

-- open touchscreen device for absolute positions
local touch_dev = assert(arg[1], "First argument must be the touchscreen device(e.g. /dev/input/event2)")
local touch = assert(input.linux.new_input_source_linux(touch_dev, true, true), "Can't open touchscreen device!")
touch:grab(1)

-- create mouse device for relative positions/clicks
local mouse = assert(input.linux.new_input_sink_linux())
mouse:set_bit("EVBIT", codes.EV_KEY)
mouse:set_bit("KEYBIT", codes.BTN_LEFT)
mouse:set_bit("KEYBIT", codes.BTN_RIGHT)
mouse:set_bit("EVBIT", codes.EV_REL)
mouse:set_bit("RELBIT", codes.REL_X)
mouse:set_bit("RELBIT", codes.REL_Y)
mouse:dev_setup("Virtual mouse for PinePhone", 0x1234, 0x5678, false)

local function touchpad_down(region, finger, x, y)
	print("touchpad down", region, finger, x, y)
	finger.last_x, finger.last_y = x, y
end
local function touchpad_moved(region, finger, x, y)
	--print("touchpad moved", region, finger, x, y)
	if x then
		mouse:write(codes.EV_REL, codes.REL_X, x-finger.last_x)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		finger.last_x = x
	end
	if y then
		mouse:write(codes.EV_REL, codes.REL_Y, y-finger.last_y)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		finger.last_y = y
	end
end
local function touchpad_up(region, finger)
	if (finger.last_x == finger.down.x) and (finger.last_y == finger.down.y) then
		print("touchpad tap", region, finger)
		mouse:write(codes.EV_KEY, codes.BTN_LEFT, 1)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		mouse:write(codes.EV_KEY, codes.BTN_LEFT, 0)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
	print("touchpad up", region, finger)
end


local function make_key_down(key)
	return function(region, finger, x, y)
		print("key down", key)
		mouse:write(codes.EV_KEY, key, 1)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
end
local function make_key_up(key)
	return function(region, finger)
		print("key up", key)
		mouse:write(codes.EV_KEY, key, 0)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
end


local touch_regions = {
	{
		x = 0,
		y = 0,
		w = 720,
		h = 1000,
		name = "touchpad",
		up = touchpad_up,
		down = touchpad_down,
		moved = touchpad_moved,
	},
	{
		x = 0,
		y = 1000,
		w = 360,
		h = 340,
		name = "lmb",
		down = make_key_down(codes.BTN_LEFT),
		up = make_key_up(codes.BTN_LEFT),
	},
	{
		x = 360,
		y = 1000,
		w = 360,
		h = 340,
		name = "rmb",
		down = make_key_down(codes.BTN_RIGHT),
		up = make_key_up(codes.BTN_RIGHT),
	},
	{
		x = 0,
		y = 1340,
		w = 720,
		h = 100,
		name = "bottom",
		down = function()
			print("Bottom bar pressed. Bye!")
			os.exit()
		end
	},
}
local function get_region(x,y)
	for i=1, #touch_regions do
		local region = touch_regions[i]
		if (x>=region.x) and (y>=region.y) and (x<region.x+region.w) and (y<region.y+region.h) then
			return region
		end
	end
end
local fingers = {}
local function finger_down(finger_slot)
	print("Finger down", finger_slot)
	assert(not fingers[finger_slot])
	fingers[finger_slot] = {}
end
local function finger_first_pos(finger_slot)
	local finger = assert(fingers[finger_slot])
	local region = get_region(finger.x, finger.y)
	finger.down = {x=finger.x, y=finger.y}
	if region and (region.name == "bottom") then
		print("Bottom pressed, Bye!")
		os.exit()
	elseif region then
		print("First pos ", finger_slot, finger.x, finger.y, "in region",region.name)
		finger.region = region
		if region.down then
			region:down(finger, finger.x, finger.y)
		end
	else
		print("First pos ", finger_slot, finger.x, finger.y)
	end
end
local function finger_moved(finger_slot, x, y)
	local finger = assert(fingers[finger_slot])
	finger.x = x or finger.x
	finger.y = y or finger.y

	if finger.x and finger.y and (not finger.down) then
		return finger_first_pos(finger_slot)
	end

	if finger.region and finger.region.moved then
		finger.region:moved(finger, x,y)
	end
	--print("Finger moved", finger_slot, fingers[finger_slot].x, fingers[finger_slot].y)
end
local function finger_up(finger_slot)
	print("Finger up", finger_slot)
	local finger = assert(fingers[finger_slot])

	if finger.region and finger.region.up then
		finger.region:up(finger)
	end

	fingers[finger_slot] = nil
end


local tracking_id = nil
local slot = 0
local function handle_touch_ev(touch_ev)
	if not touch_ev.type == codes.EV_ABS then
		return
	end

	if touch_ev.code == codes.ABS_MT_TRACKING_ID then
		if (touch_ev.value == -1) and tracking_id then
			finger_up(slot)
		else
			tracking_id = touch_ev.value
			finger_down(slot)
		end
	elseif touch_ev.code == codes.ABS_MT_SLOT then
		print("slot", touch_ev.value)
		slot = touch_ev.value
	elseif touch_ev.code == codes.ABS_MT_POSITION_X then
		finger_moved(slot, touch_ev.value, nil)
	elseif touch_ev.code == codes.ABS_MT_POSITION_Y then
		finger_moved(slot, nil, touch_ev.value)
	end
end


print("Translating to touchpad events...")
while true do -- TODO: Better event loop?
	local touch_ev = touch:read()
	if touch_ev then
		handle_touch_ev(touch_ev)
	end
end
