#!/usr/bin/env lua5.1
local input = require("lua-input")
local time = require("time")
local codes = input.linux.input_event_codes
local gettime = time.monotonic

-- open touchscreen device for absolute positions
local touch_dev = assert(arg[1], "First argument must be the touchscreen device(e.g. /dev/input/event2)")
local touch = assert(input.linux.new_input_source_linux(touch_dev, true, true), "Can't open touchscreen device!")
touch:grab(1)

local function dprint(...)
	print("\027[33mD:",...)
	io.write("\027[0m")
end

-- create mouse device for relative positions/clicks
local mouse = assert(input.linux.new_input_sink_linux())
mouse:set_bit("EVBIT", codes.EV_KEY)
mouse:set_bit("KEYBIT", codes.BTN_LEFT)
mouse:set_bit("KEYBIT", codes.BTN_RIGHT)
mouse:set_bit("EVBIT", codes.EV_REL)
mouse:set_bit("RELBIT", codes.REL_X)
mouse:set_bit("RELBIT", codes.REL_Y)
mouse:dev_setup("Virtual mouse for PinePhone", 0x1234, 0x5678, false)


-- (optional) create a new touchscreen device for forwarding touch events
-- (in case no region matches the touchscreen just forwards events)
local proxy_touchscreen = assert(input.linux.new_input_sink_linux())
proxy_touchscreen:set_bit("EVBIT", codes.EV_ABS)
proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_SLOT)
proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_TRACKING_ID)

-- TODO: Get these values from abs_info
proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_POSITION_X)
proxy_touchscreen:set_bit("ABSBIT", codes.ABS_MT_POSITION_Y)

proxy_touchscreen:set_bit("ABSBIT", codes.ABS_X)
proxy_touchscreen:set_bit("ABSBIT", codes.ABS_Y)

proxy_touchscreen:set_bit("EVBIT", codes.EV_KEY)
proxy_touchscreen:set_bit("KEYBIT", codes.BTN_TOUCH)

local info = assert(touch:abs_info(codes.ABS_X))
local x_max = info.maximum
assert(proxy_touchscreen:abs_setup(codes.ABS_X, info.value,info.minimum,info.maximum,info.fuzz,info.flat,info.resolution))

info = assert(touch:abs_info(codes.ABS_Y))
local y_max = info.maximum
assert(proxy_touchscreen:abs_setup(codes.ABS_Y, info.value,info.minimum,info.maximum,info.fuzz,info.flat,info.resolution))

info = assert(touch:abs_info(codes.ABS_MT_POSITION_X))
assert(proxy_touchscreen:abs_setup(codes.ABS_MT_POSITION_X, info.value,info.minimum,info.maximum,info.fuzz,info.flat,info.resolution))

info = assert(touch:abs_info(codes.ABS_MT_POSITION_Y))
assert(proxy_touchscreen:abs_setup(codes.ABS_MT_POSITION_Y, info.value,info.minimum,info.maximum,info.fuzz,info.flat,info.resolution))


local x_info = touch:abs_info(codes.ABS_X)
proxy_touchscreen:abs_setup(codes.ABS_X, x_info.value,x_info.minimum,x_info.maximum,x_info.fuzz,x_info.flat,x_info.resolution)

local y_info = touch:abs_info(codes.ABS_Y)
proxy_touchscreen:abs_setup(codes.ABS_Y, y_info.value,y_info.minimum,y_info.maximum,y_info.fuzz,y_info.flat,y_info.resolution)

proxy_touchscreen:dev_setup("Virtual touchscreen proxy for PinePhone", 0x2345, 0x6789, false)

local _proxy_touchscreen = proxy_touchscreen
proxy_touchscreen = {}
function proxy_touchscreen:write(type, code, value)
	local fmt = "Writing event to PROXY: type(0x%.4x): %.20s  code(0x%.4x): %25s  value: %d"
	local type_str,code_str = input.linux:ev_to_str({type = type, code = code, value = value})
	dprint(fmt:format(type, type_str or "?", code, code_str or "?", value))
	_proxy_touchscreen:write(type, code, value)
end



local transpose = false
local x_sens = 1
local y_sens = 1
if arg[2] == "right-up" then
	transpose = true
	y_sens = -1*y_sens
elseif arg[2] == "left-up" then
	transpose = true
	x_sens = -1*x_sens
elseif arg[2] == "bottom-up" then
	x_sens = -1
	y_sens = -1
elseif arg[2] and (arg[2] ~= "normal") then
	error("Unknown optional second argument! Needs to be one of: right-up, left-up, normal(default). Is: '"..tostring(arg[2]).."'")
end


local vibr_dev = arg[3]
-- (optional) open the vibration motor input device(for force feedback)
local vibr
local function ff() end
local function patt()
	for _=1, 3 do
		ff()
		ff()
		time.sleep(0.3)
	end
end
if vibr_dev then
	vibr = assert(input.linux.new_input_source_linux(vibr_dev, true, true), "Can't open!")
	vibr:vibr_gain(0xffff)
	local ff_effect_id = assert(vibr:vibr_effect(80,0,0, 0xffff), "Can't upload effect!")
	assert(vibr:vibr_start(ff_effect_id, 1), "Can't start effect")
	ff = function()
		vibr:vibr_start(ff_effect_id, 1)
	end
end



local function touchpad_down(region, finger, x, y)
	dprint("touchpad down", region, finger, x, y)
	finger.last_x, finger.last_y = x, y
	ff()
end
local function touchpad_moved(region, finger, x, y)
	--dprint("touchpad moved", region, finger, x, y)
	if transpose then
		x,y = y,x
		finger.last_x,finger.last_y = finger.last_y,finger.last_x
	end
	if x then
		mouse:write(codes.EV_REL, codes.REL_X, x_sens * (x-finger.last_x))
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
	if y then
		mouse:write(codes.EV_REL, codes.REL_Y, y_sens * (y-finger.last_y))
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
	if transpose then
		x,y = y,x
		finger.last_x,finger.last_y = finger.last_y,finger.last_x
	end
	finger.last_x = x or finger.last_x
	finger.last_y = y or finger.last_y
end
local function touchpad_up(region, finger)
	if (finger.last_x == finger.down.x) and (finger.last_y == finger.down.y) then
		dprint("touchpad tap", region, finger)
		mouse:write(codes.EV_KEY, codes.BTN_LEFT, 1)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		mouse:write(codes.EV_KEY, codes.BTN_LEFT, 0)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
	dprint("touchpad up", region, finger)
	ff()
end


local function make_key_down(key)
	return function(region, finger, x, y)
		dprint("key down", key)
		mouse:write(codes.EV_KEY, key, 1)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		ff()
	end
end
local function make_key_up(key)
	return function(region, finger)
		dprint("key up", key)
		mouse:write(codes.EV_KEY, key, 0)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
		ff()
	end
end



local touch_regions = {
	{
		x = x_max*0.1,
		y = 60,
		w = x_max*0.8,
		h = 700,
		name = "touchpad",
		up = touchpad_up,
		down = touchpad_down,
		moved = touchpad_moved,
	},
	{
		x = 0,
		y = 0,
		w = x_max*0.5,
		h = 60,
		name = "lmb",
		down = make_key_down(codes.BTN_LEFT),
		up = make_key_up(codes.BTN_LEFT),
	},
	{
		x = x_max*0.5,
		y = 0,
		w = x_max*0.5,
		h = 60,
		name = "rmb",
		down = make_key_down(codes.BTN_RIGHT),
		up = make_key_up(codes.BTN_RIGHT),
	},
	{
		x = 0,
		y = y_max-90,
		w = x_max,
		h = 90,
		name = "bottom",
		down = function()
			print("Bottom pressed, bye!")
			patt()
			os.exit(0)
		end,
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

local tracking_id = nil
local slot = 0

local function proxy_first(finger_slot, x, y)
	dprint("PROXY FIRST", finger_slot)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_TRACKING_ID, tracking_id)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_X, x)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_Y, y)
	proxy_touchscreen:write(codes.EV_SYN, codes.SYN_REPORT, 0)
end
local function proxy_moved(finger_slot, x ,y)
	dprint("PROXY MOVED", finger_slot, x, y)
	if x then
		proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
		proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_X, x)
		proxy_touchscreen:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
	if y then
		proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
		proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_POSITION_Y, y)
		proxy_touchscreen:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
end
local function proxy_up(finger_slot)
	dprint("PROXY UP", finger_slot)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_SLOT, finger_slot)
	proxy_touchscreen:write(codes.EV_ABS, codes.ABS_MT_TRACKING_ID, -1)
	if finger_slot == 0 then
		--proxy_touchscreen:write(codes.EV_KEY, codes.BTN_TOUCH, 0)
	end
	proxy_touchscreen:write(codes.EV_SYN, codes.SYN_REPORT, 0)
end


local fingers = {}
local function finger_down(finger_slot)
	dprint("Finger down", finger_slot)
	local finger = fingers[finger_slot]
	assert(not finger)
	fingers[finger_slot] = { time = gettime() }
	--proxy_down(finger_slot)
end
local function finger_first_pos(finger_slot)
	local finger = assert(fingers[finger_slot])
	local region = get_region(finger.x, finger.y)
	finger.down = {x=finger.x, y=finger.y}
	if region then
		finger.region = region
		if region.down then
			region:down(finger, finger.x, finger.y)
		end
	else
		proxy_first(finger_slot, finger.x, finger.y)
	end
	dprint("First pos ", finger_slot, finger.x, finger.y, region and "in region "..region.name or "in PROXY area(ignore)")
end
local function finger_moved(finger_slot, x, y)
	local finger = assert(fingers[finger_slot])
	finger.x = x or finger.x
	finger.y = y or finger.y

	if finger.x and finger.y and (not finger.down) then
		finger_first_pos(finger_slot)
	end

	if finger.region and finger.region.moved then
		finger.region:moved(finger, x,y)
	elseif proxy_touchscreen then
		proxy_moved(finger_slot, x, y)
	end
	--dprint("Finger moved", finger_slot, fingers[finger_slot].x, fingers[finger_slot].y)
end
local function finger_up(finger_slot)
	dprint("Finger up", finger_slot)
	local finger = assert(fingers[finger_slot])

	if finger.region and finger.region.up then
		finger.region:up(finger)
	elseif proxy_touchscreen then
		proxy_up(finger_slot)
	end

	fingers[finger_slot] = nil
end



local function handle_touch_ev(touch_ev)
	if not touch_ev.type == codes.EV_ABS then
		return
	end

	if touch_ev.code == codes.ABS_MT_TRACKING_ID then
		tracking_id = touch_ev.value
		dprint("tracking_id", tracking_id)
		if (touch_ev.value == -1) and tracking_id then
			finger_up(slot)
		else
			finger_down(slot)
		end
	elseif touch_ev.code == codes.ABS_MT_SLOT then
		dprint("slot", touch_ev.value)
		slot = touch_ev.value
	elseif touch_ev.code == codes.ABS_MT_POSITION_X then
		finger_moved(slot, touch_ev.value, nil)
	elseif touch_ev.code == codes.ABS_MT_POSITION_Y then
		finger_moved(slot, nil, touch_ev.value)
	end
end


dprint("Translating to touchpad events...")
patt()
while true do -- TODO: Better event loop?
	local touch_ev = touch:read()
	if touch_ev then
		handle_touch_ev(touch_ev)
	end
end
