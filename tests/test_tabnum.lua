package.path = "./lua/?.lua;./.test-deps/share/lua/5.1/?.lua;" .. package.path
local lu = require("luaunit")
local numbering = require("rex-tabnum")

TestNumbering = {}
function TestNumbering:setUp()
    self.windows = {
        { window_id = "a", label = "Editor" },
        { window_id = "b", label = "Logs" },
    }
    self.writes, self.handlers, self.attached, self.timers = {}, {}, {}, {}
    self.api = {
        after = function(seconds, fn)
            lu.assertEquals(seconds, 0.1)
            local timer = { fn = fn, cancelled = false }
            function timer:cancel() self.cancelled = true end
            table.insert(self.timers, timer)
            return timer
        end,
        on = function(event, fn) self.handlers[event] = fn end,
        call = function() return { sessions = { { session_id = "s" } } } end,
        session = {
            attach = function(args)
                self.attached[args.session_id] = true
                return {}
            end,
            view = function(args)
                assert(self.attached[args.session_id], "must attach before view")
                return { windows = self.windows }
            end,
            set_window_label = function(args)
                table.insert(self.writes, args)
                for _, window in ipairs(self.windows) do
                    if window.window_id == args.window_id then window.label = args.label end
                end
                return {}
            end,
        },
        block = { call = function() return { title = "fish ~/work" } end },
    }
    self.sync = numbering.start(self.api)
end
function TestNumbering:flush()
    local timers = self.timers
    self.timers = {}
    for _, timer in ipairs(timers) do
        if not timer.cancelled then timer.fn() end
    end
end
function TestNumbering:testStartupAndIdempotence()
    lu.assertEquals(self.windows[1].label, "0. Editor")
    lu.assertEquals(self.windows[2].label, "1. Logs")
    self.sync("s")
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testCreateCloseAndReorder()
    table.insert(self.windows, { window_id = "c", label = "Build" })
    self.handlers.window_created({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[3].label, "2. Build")
    table.remove(self.windows, 1)
    self.handlers.window_closed({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. Logs")
    self.windows[1], self.windows[2] = self.windows[2], self.windows[1]
    self.handlers.session_view_changed({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. Build")
    lu.assertEquals(self.windows[2].label, "1. Logs")
end
function TestNumbering:testRepeatedLabelEventsDoNotLoop()
    for _ = 1, 5 do self.handlers.window_label_changed({ session_id = "s" }, {}) end
    self:flush()
    lu.assertEquals(#self.writes, 2)
    self.windows[1].label = "Renamed"
    self.handlers.window_label_changed({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. Renamed")
end
function TestNumbering:testRestartDoesNotStackPrefixes()
    numbering.start(self.api)
    lu.assertEquals(self.windows[1].label, "0. Editor")
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testDefaultLabelUsesTerminalTitle()
    self.windows = { { window_id = "window:abcdefgh", label = "Window abcdefgh", focused_block_id = "pane" } }
    self.sync("s")
    lu.assertEquals(self.windows[1].label, "0. fish ~/work")
end
function TestNumbering:testSessionScopeAndNewSession()
    self.handlers.window_created({ session_id = "other" }, {})
    self:flush()
    self.windows[1].label = "Other"
    self.handlers.session_created({}, { session = { session_id = "other" } })
    self:flush()
    lu.assertEquals(self.writes[#self.writes].session_id, "other")
end
function TestNumbering:testLongUtf8TitleFitsLimit()
    self.windows[1].label = string.rep("中", 150)
    self.sync("s")
    lu.assertTrue(#self.windows[1].label <= 128)
    lu.assertEquals(self.windows[1].label, "0. " .. string.rep("中", 41))
end
function TestNumbering:testReadFailureMakesNoWrites()
    self.api.session.view = function() return nil, "disconnected" end
    lu.assertErrorMsgContains("disconnected", self.sync, "s")
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testWriteFailureCanBeRetried()
    local write = self.api.session.set_window_label
    self.windows[1].label = "Changed"
    self.api.session.set_window_label = function() return nil, "write failed" end
    lu.assertErrorMsgContains("write failed", self.sync, "s")
    self.api.session.set_window_label = write
    self.sync("s")
    lu.assertEquals(self.windows[1].label, "0. Changed")
end
function TestNumbering:testDeletedSessionEventIsIgnored()
    self.api.session.view = function() return nil, "status=404 code=session_not_found" end
    lu.assertTrue(pcall(self.sync, "s"))
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testDeletedSessionBeforeAttachIsIgnored()
    self.api.session.attach = function() return nil, "status=404 code=session_not_found" end
    lu.assertTrue(pcall(self.sync, "deleted"))
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testWindowClosedDuringWriteIsIgnored()
    self.windows[1].label = "Closing"
    self.api.session.set_window_label = function() return nil, "code=window_not_found" end
    lu.assertTrue(pcall(self.sync, "s"))
end
function TestNumbering:testWaitsForInitialTerminalTitle()
    self.windows = { { window_id = "window:abcdefgh", label = "Window abcdefgh", focused_block_id = "pane" } }
    self.api.block.call = function() return { title = "" } end
    self.sync("s")
    lu.assertEquals(self.windows[1].label, "0. Window abcdefgh")
    self.api.block.call = function() return { title = "fish" } end
    self.handlers["terminal.title_changed"]({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. fish")
    self.api.block.call = function() return { title = "vim" } end
    self.handlers["terminal.title_changed"]({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. vim")
end
function TestNumbering:testTitleFollowsFocusedPaneAndPreservesNumberLikeText()
    self.windows[1].focused_block_id = "left"
    self.api.block.call = function(_, _, args)
        return { title = args.block_id == "left" and "9. file.lua" or "right pane" }
    end
    self.sync("s")
    lu.assertEquals(self.windows[1].label, "0. 9. file.lua")
    self.windows[1].focused_block_id = "right"
    self.handlers.session_view_changed({ session_id = "s" }, {})
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. right pane")
end
function TestNumbering:testBurstCoalescesAndUsesLatestTitle()
    self.windows[1].focused_block_id = "pane"
    self.api.block.call = function() return { title = "Latest" } end
    for _ = 1, 100 do
        self.handlers["terminal.title_changed"]({ session_id = "s" }, {})
    end
    lu.assertEquals(#self.timers, 1)
    self:flush()
    lu.assertEquals(self.windows[1].label, "0. Latest")
    lu.assertEquals(#self.writes, 3)
end
function TestNumbering:testDestroyedSessionCancelsPendingTimer()
    self.handlers.window_created({ session_id = "s" }, {})
    lu.assertEquals(#self.timers, 1)
    self.handlers.session_destroyed({}, { session_id = "s" })
    lu.assertTrue(self.timers[1].cancelled)
    self:flush()
    lu.assertEquals(#self.writes, 2)
end
function TestNumbering:testEmptyDynamicTitleRetainsLastTitle()
    self.windows[1].focused_block_id = "pane"
    self.api.block.call = function() return { title = "" } end
    self.sync("s")
    lu.assertEquals(self.windows[1].label, "0. Editor")
end
function TestNumbering:testRexpackSpecRegistersOnlyInEvents()
    local spec = dofile("examples/rex-tabnum.lua")
    lu.assertEquals(spec[1], "tenfyzhong/rex-tabnum")
    lu.assertNil(spec.init)
    lu.assertNil(spec.config)
    local old = _G.rex
    _G.rex = self.api
    local ok, err = pcall(spec.events)
    _G.rex = old
    lu.assertTrue(ok, tostring(err))
    lu.assertNotNil(self.handlers["terminal.title_changed"])
    lu.assertEquals(self.windows[1].label, "0. Editor")
end
os.exit(lu.LuaUnit.run())
