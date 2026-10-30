LUA ?= luajit
LUAROCKS ?= luarocks

.PHONY: test-deps test integration

test-deps:
	$(LUAROCKS) --lua-version=5.1 --tree .test-deps install luaunit 3.5-1

test:
	$(LUA) tests/test_tabnum.lua

integration:
	REX_LIVE_TEST=1 python3 -m unittest discover -s tests -p test_live.py -v
