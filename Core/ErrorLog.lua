-- ErrorLog.lua
-- Captures Lua errors from SmartCraft and stores them in SmartCraftDB.errorLog
-- Errors persist across sessions via SavedVariables.
--
-- Usage (internal):
--   SmartCraft.ErrorLog:Wrap(funcName, func, ...)  -- safe-call with logging
--   SmartCraft.ErrorLog:Add(source, msg)           -- manual log entry
--
-- Slash command:
--   /sc errors   -- print all logged errors to chat
--   /sc clearerrors -- wipe the log

SmartCraft.ErrorLog = {}
local EL = SmartCraft.ErrorLog

EL.MAX_ENTRIES = 20   -- cap so SavedVariables doesn't bloat

-- ----------------------------------------------------------------
-- Ensure DB table exists
-- ----------------------------------------------------------------
function EL:Init()
    if not SmartCraftDB then SmartCraftDB = {} end
    if not SmartCraftDB.errorLog then SmartCraftDB.errorLog = {} end
end

-- ----------------------------------------------------------------
-- Add an entry to the log
-- ----------------------------------------------------------------
function EL:Add(source, msg)
    self:Init()
    local log = SmartCraftDB.errorLog
    table.insert(log, {
        source = source or "unknown",
        msg    = tostring(msg or ""),
        time   = date("%H:%M:%S"),
    })
    -- Trim to max
    while #log > self.MAX_ENTRIES do
        table.remove(log, 1)
    end
    -- Also print to chat immediately so errors are visible
    print(string.format("|cffff4444SmartCraft ERROR|r [%s]: %s", source, tostring(msg)))
end

-- ----------------------------------------------------------------
-- Safe-call wrapper: runs func(...), logs on error, returns ok, result
-- ----------------------------------------------------------------
function EL:Wrap(source, func, ...)
    local ok, result = pcall(func, ...)
    if not ok then
        self:Add(source, result)
    end
    return ok, result
end

-- ----------------------------------------------------------------
-- Print all logged errors to chat
-- ----------------------------------------------------------------
function EL:Print()
    self:Init()
    local log = SmartCraftDB.errorLog
    if #log == 0 then
        print("|cff00ff96SmartCraft:|r No errors logged.")
        return
    end
    print(string.format("|cff00ff96SmartCraft Error Log|r (%d entries):", #log))
    for i, entry in ipairs(log) do
        print(string.format("|cffaaaaaa[%d] %s [%s]:|r %s",
            i, entry.time, entry.source, entry.msg))
    end
end

-- ----------------------------------------------------------------
-- Clear the log
-- ----------------------------------------------------------------
function EL:Clear()
    self:Init()
    SmartCraftDB.errorLog = {}
    print("|cff00ff96SmartCraft:|r Error log cleared.")
end
