-- Steam utility helpers for the LuaTools plugin
local m_utils    = require("utils")
local millennium = require("millennium")
local fs         = require("fs")
local logger     = require("plugin_logger")

local steam_utils = {}

-- Cache the Steam install path after first resolution
local _steam_path_cache = nil

-- Normalize to Windows backslashes and strip trailing separator
local function normalize_path(p)
    if not p then return "" end
    p = p:gsub("/", "\\")
    if p:sub(-1) == "\\" then p = p:sub(1, -2) end
    return p
end

function steam_utils.detect_steam_install_path()
    if _steam_path_cache then return _steam_path_cache end

    local ok, path = pcall(millennium.steam_path)
    if ok and path and path ~= "" then
        _steam_path_cache = normalize_path(path)
        logger.log("Steam install path: " .. _steam_path_cache)
        return _steam_path_cache
    end

    logger.warn("millennium.steam_path() failed or returned empty")
    return ""
end

-- Returns true if a Lua script exists for the given appid in stplug-in/
function steam_utils.has_lua_for_app(appid)
    local base_path = steam_utils.detect_steam_install_path()
    if not base_path or base_path == "" then return false end

    local stplug_path   = fs.join(base_path, "config", "stplug-in")
    local lua_file      = fs.join(stplug_path, tostring(appid) .. ".lua")
    local disabled_file = fs.join(stplug_path, tostring(appid) .. ".lua.disabled")

    return fs.exists(lua_file) or fs.exists(disabled_file)
end

-- Locate the install directory for an appid.
-- Returns { success, installPath, installDir, libraryPath, path }
-- or      { success=false, error="..." }
function steam_utils.get_game_install_path_response(appid)
    appid = tostring(appid)

    local steam_path = steam_utils.detect_steam_install_path()
    if not steam_path or steam_path == "" then
        return { success = false, error = "Could not find Steam installation path" }
    end

    -- METHOD 1: Windows Registry (most reliable for installed Steam games)
    local reg_paths = {
        "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " .. appid,
        "HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " .. appid,
    }
    for _, reg_key in ipairs(reg_paths) do
        local ok, out = pcall(m_utils.exec,
            'powershell -NoProfile -Command "try{(Get-ItemProperty -LiteralPath \'' ..
            reg_key .. '\' -Name InstallLocation -ErrorAction Stop).InstallLocation}catch{}"')
        if ok and out and out ~= "" then
            out = normalize_path(out:gsub("[\r\n]+$", ""))
            if fs.exists(out) then
                return {
                    success     = true,
                    installPath = out,
                    installDir  = out:match("[^\\]+$") or out,
                    libraryPath = "",
                    path        = out,
                }
            end
        end
    end

    -- METHOD 2: libraryfolders.vdf parsing
    local library_vdf_path = fs.join(steam_path, "config", "libraryfolders.vdf")
    if not fs.exists(library_vdf_path) then
        return { success = false, error = "Could not find libraryfolders.vdf" }
    end

    local vdf_content = m_utils.read_file(library_vdf_path)
    if not vdf_content then
        return { success = false, error = "Failed to read libraryfolders.vdf" }
    end

    local all_library_paths = {}
    for path in vdf_content:gmatch('"path"%s+"([^"]+)"') do
        table.insert(all_library_paths, normalize_path(path:gsub("\\\\", "\\")))
    end

    local library_path     = nil
    local appmanifest_path = nil

    for _, lib_path in ipairs(all_library_paths) do
        local candidate = fs.join(lib_path, "steamapps", "appmanifest_" .. appid .. ".acf")
        if fs.exists(candidate) then
            library_path     = lib_path
            appmanifest_path = candidate
            break
        end
    end

    if not library_path or not appmanifest_path then
        return { success = false, error = "menu.error.notInstalled" }
    end

    local manifest_content = m_utils.read_file(appmanifest_path)
    if not manifest_content then
        return { success = false, error = "Failed to parse appmanifest" }
    end

    local install_dir = manifest_content:match('"installdir"%s+"([^"]+)"')
    if not install_dir then
        return { success = false, error = "Install directory not found in manifest" }
    end

    local full_install_path = fs.join(library_path, "steamapps", "common", install_dir)
    if not fs.exists(full_install_path) then
        return { success = false, error = "Game directory does not exist on disk" }
    end

    return {
        success     = true,
        installPath = full_install_path,
        installDir  = install_dir,
        libraryPath = library_path,
        path        = full_install_path,
    }
end

-- Open a folder in Windows Explorer
function steam_utils.open_game_folder(path)
    if not path or path == "" then return false end
    path = normalize_path(path)
    if not fs.exists(path) then return false end
    pcall(m_utils.exec, 'explorer "' .. path .. '"')
    return true
end

return steam_utils
