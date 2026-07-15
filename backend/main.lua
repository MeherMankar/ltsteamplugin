-- LuaTools Millennium Lua backend (v3.3.1 compatible — no http module)
-- Uses curl via m_utils.exec for HTTP since require("http") is only in v3.4+

local millennium  = require("millennium")
local fs          = require("fs")
local m_utils     = require("utils")
local logger      = require("plugin_logger")
local paths       = require("paths")
local steam_utils = require("steam_utils")

local ok_json, cjson = pcall(require, "cjson")
if not ok_json then
    ok_json, cjson = pcall(require, "json")
end
if not ok_json then
    -- minimal fallback encoder (strings/numbers/booleans only)
    cjson = {}
    function cjson.encode(t)
        if type(t) == "string" then return '"' .. t:gsub('"', '\\"') .. '"' end
        if type(t) == "number" or type(t) == "boolean" then return tostring(t) end
        if type(t) ~= "table" then return '"' .. tostring(t) .. '"' end
        local parts = {}
        for k, v in pairs(t) do
            table.insert(parts, '"' .. tostring(k) .. '":' .. cjson.encode(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    function cjson.decode(s) return nil end
end

-- ── App backend bridge (127.0.0.1:6767) ────────────────────────────────────────

local BACKEND_BASE = "http://127.0.0.1:6767"

local function curl_request(method, path, body)
    local url = BACKEND_BASE .. path
    local cmd

    if body then
        local escaped = body:gsub('"', '\\"')
        cmd = string.format(
            'curl.exe -s -X %s "%s" -H "Content-Type: application/json" -d "%s" --connect-timeout 15',
            method, url, escaped
        )
    else
        cmd = string.format('curl.exe -s -X %s "%s" --connect-timeout 15', method, url)
    end

    local ok, result = pcall(m_utils.exec, cmd)
    if not ok or not result then
        return cjson.encode({ success = false, error = "curl exec failed" })
    end
    return result
end

local function backend_request(method, path, body)
    local body_str = nil
    if body then body_str = cjson.encode(body) end
    return curl_request(method, path, body_str)
end

-- ── Ensure the app is running ──────────────────────────────────────────────────
local function ensure_backend_running()
    -- quick ping
    local ok, result = pcall(m_utils.exec,
        'curl.exe -s "' .. BACKEND_BASE .. '/has/0" --connect-timeout 2')
    if ok and result and result ~= "" then return end -- already up

    local local_appdata = m_utils.getenv("LOCALAPPDATA") or os.getenv("LOCALAPPDATA")
    if not local_appdata or local_appdata == "" then
        logger.warn("LOCALAPPDATA not available, cannot launch LuaTools backend")
        return
    end

    local exe_path = local_appdata .. "\\LuaTools\\current\\LuaTools.exe"
    if not fs.exists(exe_path) then
        logger.warn("LuaTools.exe not found at " .. exe_path)
        return
    end

    pcall(m_utils.exec, 'start "" "' .. exe_path .. '" --minimized')
    logger.log("Launched LuaTools backend: " .. exe_path)
end

-- ── RPC handlers (must be GLOBAL functions) ────────────────────────────────────

function HasLuaToolsForApp(appid)
    return backend_request("GET", "/has/" .. tostring(appid))
end

function DeleteLuaToolsForApp(appid)
    return backend_request("POST", "/remove/" .. tostring(appid))
end

function CheckApisForApp(appid)
    return backend_request("POST", "/check-sources/" .. tostring(appid))
end

function StartAddViaLuaToolsFromUrl(appid, source)
    return backend_request("POST", "/download/" .. tostring(appid), { source = source })
end

function GetAddViaLuaToolsStatus(appid)
    return backend_request("GET", "/download-status/" .. tostring(appid))
end

function CancelAddViaLuaTools(appid)
    return backend_request("POST", "/cancel/" .. tostring(appid))
end

function RestartSteam()
    return backend_request("POST", "/restart-steam")
end

function StartLuaToolsAdd(appid)
    return backend_request("POST", "/add/" .. tostring(appid))
end

function GetLuaToolsAddStatus(appid)
    return backend_request("GET", "/add-status/" .. tostring(appid))
end

function PickLuaToolsAddSource(appid, source)
    return backend_request("POST", "/add-source/" .. tostring(appid), { source = source })
end

function OpenSettings()
    return backend_request("POST", "/open/settings")
end

function OpenFix(appid)
    return backend_request("POST", "/open/fix/" .. tostring(appid))
end

function ReadLoadedApps()
    return backend_request("GET", "/loaded-apps")
end

function DismissLoadedApps()
    return backend_request("POST", "/loaded-apps")
end

-- ── Webkit file management ────────────────────────────────────────────────────

local function copy_webkit_files()
    local steam_dir = steam_utils.detect_steam_install_path()
    if not steam_dir or steam_dir == "" then return end

    local target_webkit_dir = fs.join(steam_dir, "steamui", "webkit")
    if not fs.exists(target_webkit_dir) then
        fs.create_directories(target_webkit_dir)
    end

    local public_dir = fs.join(paths.get_plugin_dir(), "public")

    local src_js = fs.join(public_dir, "luatools.js")
    local dst_js = fs.join(target_webkit_dir, "luatools.js")
    if fs.exists(src_js) then
        local content = m_utils.read_file(src_js)
        if content then m_utils.write_file(dst_js, content) end
    end

    local src_css = fs.join(public_dir, "steamdb-webkit.css")
    local dst_css = fs.join(target_webkit_dir, "steamdb-webkit.css")
    if fs.exists(src_css) then
        local content = m_utils.read_file(src_css)
        if content then m_utils.write_file(dst_css, content) end
    end
end

local function inject_webkit_files()
    millennium.add_browser_css("webkit/steamdb-webkit.css")
    millennium.add_browser_js("webkit/luatools.js")
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

local function on_load()
    logger.log("LuaTools Lua backend loading (millennium " .. tostring(millennium.version()) .. ")")
    ensure_backend_running()
    copy_webkit_files()
    inject_webkit_files()
    millennium.ready()
    logger.log("LuaTools ready")
end

local function on_unload()
    logger.log("LuaTools unloading")
end

local function on_frontend_loaded()
    copy_webkit_files()
end

return {
    on_load            = on_load,
    on_unload          = on_unload,
    on_frontend_loaded = on_frontend_loaded,
}
