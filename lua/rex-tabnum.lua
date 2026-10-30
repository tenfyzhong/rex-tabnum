-- Start from a rexpack events callback, never from the configuration VM.
local M = {}

local function disappeared(err)
    local message = tostring(err)
    return message:find("code=session_not_found", 1, true)
        or message:find("code=window_not_found", 1, true)
end

-- Use a byte limit as well as preserving UTF-8 boundaries (also safe on Lua 5.1).
local function truncate(text, limit)
    if #text <= limit then return text end
    local stop = limit + 1
    while stop > 1 do
        local byte = text:byte(stop)
        if byte < 128 or byte >= 192 then break end
        stop = stop - 1
    end
    return text:sub(1, stop - 1)
end

function M.start(api)
    local attached, pending = {}, {}
    local function sync(session_id)
        if not session_id then return end
        if not attached[session_id] then
            local result, err = api.session.attach{ session_id = session_id }
            if not result then
                if disappeared(err) then return end
                error("tab numbering: " .. tostring(err))
            end
            attached[session_id] = true
        end
        local view, err = api.session.view{ session_id = session_id }
        if not view then
            if disappeared(err) then
                attached[session_id] = nil
                return
            end
            error("tab numbering: " .. tostring(err))
        end
        for index, window in ipairs(view.windows or {}) do
            -- A leading '<digits>. ' is reserved for the managed index.
            local title = (window.label or ""):gsub("^%d+%. ", "", 1)
            if window.focused_block_id then
                local terminal = api.block.call("com.superlogical.terminal", "title", {
                    session_id = session_id,
                    block_id = window.focused_block_id,
                })
                if terminal and terminal.title and terminal.title ~= "" then
                    -- Do not strip digits from the program's own title.
                    title = terminal.title
                end
            end
            local prefix = tostring(index - 1) .. ". "
            local label = prefix .. truncate(title, 128 - #prefix)
            -- Renaming emits more view/label events. No-op writes must be skipped.
            if label ~= window.label then
                local result, write_err = api.session.set_window_label{
                    session_id = session_id,
                    window_id = window.window_id,
                    label = label,
                }
                if not result and not disappeared(write_err) then
                    error("tab numbering: " .. tostring(write_err))
                end
            end
        end
    end

    -- One timer per session: bursts coalesce without indefinitely postponing
    -- an update when a program emits a continuous stream of title changes.
    local function schedule(session_id)
        if not session_id or pending[session_id] then return end
        pending[session_id] = api.after(0.1, function()
            pending[session_id] = nil
            sync(session_id)
        end)
    end
    local function changed(ctx) schedule(ctx.session_id) end
    api.on("terminal.title_changed", changed)
    api.on("window_created", changed)
    api.on("window_closed", changed)
    api.on("window_label_changed", changed)
    -- Covers focus changes and drag/reorder as well as structural changes.
    api.on("session_view_changed", changed)
    api.on("session_created", function(_, event)
        if event.session then schedule(event.session.session_id) end
    end)
    api.on("session_destroyed", function(_, event)
        local session_id = event.session_id
        attached[session_id] = nil
        if pending[session_id] then
            pending[session_id]:cancel()
            pending[session_id] = nil
        end
    end)

    local sessions, err = api.call("session.list")
    if not sessions then error("tab numbering: " .. tostring(err)) end
    for _, session in ipairs(sessions.sessions or {}) do sync(session.session_id) end
    return sync
end

return M
