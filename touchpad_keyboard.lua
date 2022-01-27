#!/usr/bin/env lua5.1
local input = require("lua-input")
local time = require("time")
local codes = input.linux.input_event_codes

-- translation table for events from the kbd.
-- key is code on the kbd value is code on the mouse.
local key_translate = {
	[codes.KEY_LEFTBRACE] = codes.BTN_LEFT,
	[codes.KEY_RIGHTBRACE] = codes.BTN_RIGHT,
}

-- open touchscreen device for absolute positions
local touch_dev = assert(arg[1], "First argument must be the touchscreen device(e.g. /dev/input/event2)")
local touch = assert(input.linux.new_input_source_linux(touch_dev, false, true), "Can't open touchscreen device!")
touch:grab(1)

-- open keyboard-like device for volume buttons
local kbd_dev = assert(arg[2], "Second argument must be keyboard device(e.g. /dev/input/event1)")
local kbd = assert(input.linux.new_input_source_linux(kbd_dev, false, true), "Can't open trigger device!")
kbd:grab(1)



-- create keyboard+mouse device for relative positions/clicks and key forwarding
local mouse = assert(input.linux.new_input_sink_linux())
mouse:set_bit("EVBIT", codes.EV_KEY)
mouse:set_bit("KEYBIT", codes.BTN_LEFT)
mouse:set_bit("KEYBIT", codes.BTN_RIGHT)

-- get list of possible keys
local keys = {}
for k in pairs(codes) do
	if k:match("^KEY_") then
		table.insert(keys, k)
	end
end
-- register all keys
for _,v in ipairs(keys) do
	mouse:set_bit("KEYBIT", codes[v])
end



mouse:set_bit("EVBIT", codes.EV_REL)
mouse:set_bit("RELBIT", codes.REL_X)
mouse:set_bit("RELBIT", codes.REL_Y)
mouse:dev_setup("Virtual mouse for PinePhone", 0x1234, 0x5678, false)


local function syn(dev)
	dev:write(codes.EV_SYN,codes.SYN_REPORT,0)
end

local sensitivity = 1
local transpose = false
local tx = 1
local ty = 1
if arg[3] == "right-up" then
	transpose = true
	ty = -1
elseif arg[3] == "left-up" then
	transpose = true
	tx = -1
elseif arg[3] == "bottom-up" then
	tx = -1
	ty = -1
end
local function mouse_rel(dev, dx, dy)
	if transpose then
		tx,ty = ty,tx
	end
	dx = dx * tx
	dy = dy * ty
	dev:write(codes.EV_REL, codes.REL_X, dx*sensitivity)
	dev:write(codes.EV_REL, codes.REL_Y, dy*sensitivity)
end

local down_x = nil
local down_y = nil
local function handle_touch_ev(touch_ev)
	--local type_str,code_str = input.linux:ev_to_str(touch_ev)
	--print("touch", now, dt, ev_fmt:format(touch_ev.type, type_str or "?", touch_ev.code, code_str or "?", touch_ev.value))
	if not down_x and (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_X) then
		down_x = touch_ev.value
	elseif not down_y and (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_Y) then
		down_y = touch_ev.value
	elseif down_x and (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_X) then
		local new_x = touch_ev.value
		local dx = new_x-down_x
		down_x = new_x
		mouse_rel(mouse, dx, 0)
		syn(mouse)
	elseif down_y and (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_Y) then
		local new_y = touch_ev.value
		local dy = new_y-down_y
		down_y = new_y
		mouse_rel(mouse, 0, dy)
		syn(mouse)
	elseif (touch_ev.type == codes.EV_KEY) and (touch_ev.code == codes.BTN_TOUCH) and (touch_ev.value == 0)then
		down_x = nil
		down_y = nil
	end
end

local function handle_kbd_ev(kbd_ev)
	--local type_str,code_str = input.linux:ev_to_str(kbd_ev)
	--print("kbd", now, dt, ev_fmt:format(kbd_ev.type, type_str or "?", kbd_ev.code, code_str or "?", kbd_ev.value))
	if (kbd_ev.type==codes.EV_KEY) and (key_translate[kbd_ev.code]) then
		-- translate key
		mouse:write(codes.EV_KEY, key_translate[kbd_ev.code], kbd_ev.value)
		syn(mouse)
	elseif (kbd_ev.type==codes.EV_KEY) and (kbd_ev.code == codes.KEY_ESC) then
		-- stop mouse mode
		os.exit(0)
	else
		-- forward all other events
		mouse:write(kbd_ev.type, kbd_ev.code, kbd_ev.value)
	end
end


print("Translating to touchpad events...")
while true do

	local touch_ev = touch:read()
	if touch_ev then
		handle_touch_ev(touch_ev)
	end

	local kbd_ev = kbd:read()
	if kbd_ev then
		handle_kbd_ev(kbd_ev)
	end

	if (not touch_ev) and (not kbd_ev) then
		-- TODO: try a blocking read?
		time.sleep(0.01)
	end
end
