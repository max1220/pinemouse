#!/usr/bin/env lua5.1
local input = require("lua-input")
local time = require("time")
local gettime = time.monotonic
local codes = input.linux.input_event_codes



--[[ CONFIGURATION ]]--

-- maximum length of the sequence in seconds
local pattern_max_duration = 2

-- after seq_cooldown seconds without events reset the sequence
local seq_cooldown = 4

-- translate the input key codes to a string
local seq_translate = {
	[codes.KEY_VOLUMEUP] = "+",
	[codes.KEY_VOLUMEDOWN] = "-",
}

--[[ /CONFIGURATION ]]--



-- pattern detection settings
local dev_path = assert(arg[1], "First argument must be a device(e.g. /dev/input/event1)")

-- pattern to detect in the sequence
local seq_pattern = assert(arg[2], "Second argument must be a button pattern(e.g. '+-+-+-'')")

local function pattern_detected()
	print("Pattern detected!")
	os.exit(0)
end

local seq = {}

local function handle_ev(ev)
	local now = gettime()
	if (ev.type==codes.EV_KEY) and (ev.value==1) then
		-- append symbol to sequence
		if seq_translate[ev.code] then
			table.insert(seq, {now, seq_translate[ev.code]})
		end
		-- remove overflow
		if #seq > #seq_pattern then
			table.remove(seq, 1)
		end

		-- get time between first key press and last key press in sequence
		local seq_start, seq_end = seq[1][1], seq[#seq][1]
		local seq_dur = seq_end-seq_start

		-- if the sequence is the right length, and is short enough...
		if (#seq == #seq_pattern) and (seq_dur<pattern_max_duration) then
			-- ... turn sequence into a string ...
			local seq_str = {}
			for i=1, #seq do
				table.insert(seq_str, seq[i][2])
			end
			seq_str = table.concat(seq_str)

			-- and compare to the pattern.
			if seq_str == seq_pattern then
				-- found pattern, trigger callback and reset sequence
				pattern_detected()
				seq = {}
			end
		end
	end

	--
	if (#seq>0) and (now - seq[#seq][1] > seq_cooldown) then
		seq = {}
	end
end

-- open device blocking
local dev = assert(input.linux.new_input_source_linux(dev_path, true), "Can't open device!")

print("Detecting pattern...", dev)
while true do
	local ev = dev:read()
	if ev then
		handle_ev(ev)
	end
end
