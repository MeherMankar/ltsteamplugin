-- Path resolution helpers for the LuaTools plugin
local fs      = require("fs")
local m_utils = require("utils")

local paths = {}

-- Resolve the backend directory (where this file lives).
-- Tries m_utils.get_backend_path() first; falls back to debug.getinfo source path.
function paths.get_backend_dir()
    local be_path = m_utils.get_backend_path()
    if be_path and be_path ~= "" then
        return fs.absolute(be_path)
    end

    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local file = info.source:sub(2)
        local dir  = file:match("(.*[/\\])") or "."
        -- strip trailing separator
        if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then
            dir = dir:sub(1, -2)
        end
        return fs.absolute(dir)
    end

    return fs.absolute(".")
end

-- Plugin root = one level above backend/
function paths.get_plugin_dir()
    return fs.absolute(fs.join(paths.get_backend_dir(), ".."))
end

-- Convenience: resolve a file path inside backend/
function paths.backend_path(filename)
    return fs.join(paths.get_backend_dir(), filename)
end

-- Convenience: resolve a file path inside public/
function paths.public_path(filename)
    return fs.join(paths.get_plugin_dir(), "public", filename)
end

return paths
