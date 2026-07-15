-- Safe logger: tries Millennium's built-in logger, falls back to print()
local ok, m_logger = pcall(require, "logger")

local M = {}

function M.log(msg)
    if ok then pcall(function() m_logger:info(tostring(msg)) end)
    else print("[LuaTools] " .. tostring(msg)) end
end

function M.warn(msg)
    if ok then pcall(function() m_logger:warn(tostring(msg)) end)
    else print("[LuaTools WARN] " .. tostring(msg)) end
end

function M.error(msg)
    if ok then pcall(function() m_logger:error(tostring(msg)) end)
    else print("[LuaTools ERROR] " .. tostring(msg)) end
end

function M.info(msg)
    M.log(msg)
end

return M
