# rex-tabnum

Number Rex tabs from zero and keep their labels in sync with the focused
terminal's title. Events run in rexpack's shared event runner; Hammerspoon and a
separate watcher are not required.

## Configure

Requires Rex and a version of [rexpack](https://github.com/tenfyzhong/rexpack)
that supports the `events` plugin callback. Save [the plugin spec](examples/rex-tabnum.lua)
as `~/.config/rex/plugins/rex-tabnum.lua`:

```lua
return {
    "tenfyzhong/rex-tabnum",
    lazy = true,
    events = function()
        require("rex-tabnum").start(rex)
    end,
}
```

## Behavior

- Number each local session independently in tab order: `0. Title`, `1. Title`.
- Number existing tabs on startup and follow creation, closure, reorder, pane
  focus, label edits, and terminal title changes.
- Prefer the focused terminal's nonempty title; otherwise retain the label body.
  Terminal titles override manual tab names. The leading `digits. ` in a fallback
  label is reserved for the index; digits in a terminal's own title are preserved.
- Limit the complete label to 128 bytes without splitting UTF-8 characters.
- Coalesce event bursts into one 100 ms timer per session without postponing
  continuously changing titles. Skip unchanged labels to prevent rename loops.
- Ignore sessions/windows deleted during synchronization; surface other errors.

The plugin has no idle polling. Only local sessions are covered, not remote hosts.

## Migrate from standalone scripts

Remove `require("rexwatcher")` from Hammerspoon's `init.lua` and reload
Hammerspoon to stop its existing listener. Then enable the spec above and reload
Rex. Verify tab numbering works and the old `watch_tab_numbers.lua` process
has exited before removing the old `tab_numbers.lua`, `watch_tab_numbers.lua`,
`hammerspoon_rex.lua`, and Hammerspoon's `rexwatcher.lua`.

## Tests

```sh
make test-deps
make test
```

LuaUnit tests run with LuaJIT/Lua 5.1 and mock the Rex API. CI runs these tests.
For acceptance against a running Rex with this plugin already configured:

```sh
REX_BIN=/absolute/path/to/rex make integration
```

The opt-in Python unittest creates and cleans up its own session, verifies title
changes and tab numbering, and reloads the actual Rex configuration. It does not
edit the configuration or close existing sessions. Reorder, focused-pane changes,
UTF-8 truncation, event coalescing, and deletion races have unit coverage.
