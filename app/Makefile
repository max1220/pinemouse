LUASTATIC ?= luastatic
LUASTATIC_OPTS ?= -llua5.1 -I/usr/include/lua5.1

LUATIME_O ?= ./lua-time/time.o
LUAINPUT_O ?= ./lua-input/src/input_linux.o
LUAINPUT_LUASRC ?= ./lua-input/lua/init.lua ./lua-input/lua/linux.lua ./lua-input/lua/input-event-codes.lua

.PHONY: all
all: deps touchpad detect_pattern tar
	@echo "-> Building finished."

.PHONY: clean
clean:
	rm -f touchpad.luastatic.c touchpad.lua touchpad detect_pattern.luastatic.c detect_pattern.lua detect_pattern pinemouse.tar


.PHONY: deps
deps: lua-time lua-input
	@echo "-> Building dependencies finished."

.PHONY: deps-clean
deps-clean:
	rm -rf lua-time lua-input

lua-time:
	git clone https://github.com/max1220/lua-time
	cd lua-time ; STRIP=true make clean all

lua-input:
	git clone https://github.com/max1220/lua-input -b vibr
	cd lua-input ; STRIP=true make clean all

tar:
	tar -vcf pinemouse.tar touchpad detect_pattern ../get_orientation.sh pinemouse.sh


touchpad: ../touchpad.lua
	cp -v $^ .
	$(LUASTATIC) $^ $(LUAINPUT_LUASRC) $(LUATIME_O) $(LUAINPUT_O) $(LUASTATIC_OPTS)

detect_pattern: ../detect_pattern.lua
	cp -v $^ .
	$(LUASTATIC) $^ $(LUAINPUT_LUASRC) $(LUATIME_O) $(LUAINPUT_O) $(LUASTATIC_OPTS)
