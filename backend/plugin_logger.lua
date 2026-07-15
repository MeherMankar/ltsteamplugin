-- Logger: tries Millennium built-in logger, falls back to print()
local ok, m_logger = pcall(require, "logger")

local M = {}
local PREFIX = "[LuaTools]"

function M.log(msg)
    msg = tostring(msg)
    if ok then pcall(function() m_logger:info(msg) end)
    else print(PREFIX .. " " .. msg) end
end

function M.info(msg)
    M.log(msg)
end

function M.warn(msg)
    msg = tostring(msg)
    if ok then pcall(function() m_logger:warn(msg) end)
    else print(PREFIX .. " WARNING: " .. msg) end
end

function M.error(msg)
    msg = tostring(msg)
    if ok then pcall(function() m_logger:error(msg) end)
    else print(PREFIX .. " ERROR: " .. msg) end
end

return M
