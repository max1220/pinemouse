#!/usr/bin/env lua5.1
local input = require("lua-input")
local time = require("time")

local gettime = time.monotonic
local codes = input.linux.input_event_codes

local touch_dev = assert(arg[1], "First argument must be the touchscreen device(e.g. /dev/input/event2)")
local kbd_dev = assert(arg[2], "Second argument must be trigger device(e.g. /dev/input/event1)")

local touch = assert(input.linux.new_input_source_linux(touch_dev), "Can't open touchscreen device!")
--local touch
local kbd = assert(input.linux.new_input_source_linux(kbd_dev), "Can't open trigger device!")


local mouse = assert(input.linux.new_input_sink_linux())
mouse:set_bit("EVBIT", codes.EV_KEY)
mouse:set_bit("KEYBIT", codes.BTN_LEFT)
mouse:set_bit("KEYBIT", codes.BTN_RIGHT)
mouse:set_bit("EVBIT", codes.EV_REL)
mouse:set_bit("RELBIT", codes.REL_X)
mouse:set_bit("RELBIT", codes.REL_Y)
mouse:dev_setup("Virtual mouse for PinePhone", 0x1234, 0x5678, false)


--local ev_fmt = "type(0x%.4x): %.20s  code(0x%.4x): %25s  value: %d"
local last = gettime()
local now,dt = last,0
local max_delay = 1
local cooldown = 3
local seq = {}
local seq_pattern = "ududud"
local translate_abs_to_rel = false
local sensitivity = 0.5

local function toggle_mode()
	if translate_abs_to_rel then -- disable
		translate_abs_to_rel = false
		touch:grab(0)
		kbd:grab(0)
		--touch:close()
		print("is now disabled")
	else -- enable
		translate_abs_to_rel = true
		--touch = assert(input.linux.new_input_source_linux(touch_dev), "Can't re-open touchscreen device!")
		touch:grab(1)
		kbd:grab(1)
		print("is now enabled")
	end
end

local last_x=0
local last_y=0
local function handle_touch_ev(touch_ev)
	--local type_str,code_str = input.linux:ev_to_str(touch_ev)
	--print("touch", now, dt, ev_fmt:format(touch_ev.type, type_str or "?", touch_ev.code, code_str or "?", touch_ev.value))
	if (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_X) then
		local new_x = touch_ev.value
		local dx = new_x-last_x
		last_x = new_x
		mouse:write(codes.EV_REL, codes.REL_X, dx*sensitivity)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	elseif (touch_ev.type == codes.EV_ABS) and (touch_ev.code == codes.ABS_Y) then
		local new_y = touch_ev.value
		local dy = new_y-last_y
		last_y = new_y
		mouse:write(codes.EV_REL, codes.REL_Y, dy*sensitivity)
		mouse:write(codes.EV_SYN,codes.SYN_REPORT,0)
	end
end

local function handle_kbd_ev(kbd_ev)
	--local type_str,code_str = input.linux:ev_to_str(kbd_ev)
	--print("kbd", now, dt, ev_fmt:format(kbd_ev.type, type_str or "?", kbd_ev.code, code_str or "?", kbd_ev.value))

	if (kbd_ev.type==codes.EV_KEY) and (kbd_ev.value==1) and (kbd_ev.code==codes.KEY_VOLUMEDOWN or kbd_ev.code==codes.KEY_VOLUMEUP) then
		table.insert(seq, {now, kbd_ev.code})
		if #seq > #seq_pattern then
			table.remove(seq, 1)
		end
		local seq_start, seq_end = seq[1][1], seq[#seq][1]
		if seq_end-seq_start>max_delay then
			local seq_str = {}
			for i=1, #seq do
				local key = seq[i][2]
				if key == codes.KEY_VOLUMEDOWN then
					table.insert(seq_str, "u")
				elseif key == codes.KEY_VOLUMEUP then
					table.insert(seq_str, "d")
				end
			end
			seq_str = table.concat(seq_str)
			if seq_str:match(seq_pattern) then
				print("Pattern detected!")
				toggle_mode()
				seq = {}
			end
		end
	end

	if (#seq>0) and (now - seq[#seq][1] > cooldown) then
		seq = {}
	end
end

local function handle_kbd_ev_mouse(kbd_ev)
	--local type_str,code_str = input.linux:ev_to_str(kbd_ev)
	--print("kbd", now, dt, ev_fmt:format(kbd_ev.type, type_str or "?", kbd_ev.code, code_str or "?", kbd_ev.value))

	local btn
	if (kbd_ev.type==codes.EV_KEY) and (kbd_ev.code==codes.KEY_VOLUMEDOWN) then
		btn = codes.BTN_RIGHT
	elseif (kbd_ev.type==codes.EV_KEY) and (kbd_ev.code==codes.KEY_VOLUMEUP) then
		btn = codes.BTN_LEFT
	end

	if btn then
		mouse:write(codes.EV_KEY, btn, kbd_ev.value)
	end

	handle_kbd_ev(kbd_ev)
end


print("Waiting for events...")
while true do
	now = gettime()
	dt = now - last
	last = now

	local touch_ev
	if translate_abs_to_rel then
		touch_ev = touch:read()
		if touch_ev then
			handle_touch_ev(touch_ev)
		end
	end

	local kbd_ev = kbd:read()
	if kbd_ev and translate_abs_to_rel then
		handle_kbd_ev_mouse(kbd_ev)
	elseif kbd_ev then
		handle_kbd_ev(kbd_ev)
	end

	if (not touch_ev) and (not kbd) then
		time.sleep(1/60)
	end
end
