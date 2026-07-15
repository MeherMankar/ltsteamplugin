-- LuaTools Millennium Lua backend
-- Patterns adapted from SteamDaddy reference plugin

local millennium  = require("millennium")
local fs          = require("fs")
local m_utils     = require("utils")
local logger      = require("plugin_logger")
local steam_utils = require("steam_utils")

-- ── JSON helpers (same pattern as SteamDaddy) ─────────────────────────────────

local function json_ok(t)
    t.success = true
    local ok, s = pcall(function() return require("cjson").encode(t) end)
    if ok then return s end
    -- manual fallback
    local parts = {}
    for k, v in pairs(t) do
        local tv = type(v)
        if tv == "boolean" then
            table.insert(parts, '"' .. k .. '":' .. (v and "true" or "false"))
        elseif tv == "number" then
            table.insert(parts, '"' .. k .. '":' .. v)
        elseif tv == "string" then
            table.insert(parts, '"' .. k .. '":"' .. v:gsub('"', '\\"') .. '"')
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function json_err(msg)
    local ok, s = pcall(function()
        return require("cjson").encode({ success = false, error = tostring(msg) })
    end)
    if ok then return s end
    return '{"success":false,"error":"' .. tostring(msg):gsub('"', '\\"') .. '"}'
end

-- ── Path helpers (inline, same pattern as SteamDaddy) ─────────────────────────

local function get_plugin_dir()
    local be_path = m_utils.get_backend_path()
    if not be_path or be_path == "" then
        local info = debug.getinfo(1, "S")
        if info and info.source and info.source:sub(1, 1) == "@" then
            local file = info.source:sub(2)
            local dir  = file:match("(.*[/\\])") or "."
            if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then dir = dir:sub(1, -2) end
            be_path = dir
        else
            be_path = "."
        end
    end
    return fs.absolute(fs.join(fs.absolute(be_path), ".."))
end

-- ── App backend bridge (127.0.0.1:6767) ──────────────────────────────────────

local BACKEND_BASE = "http://127.0.0.1:6767"

local function curl_request(method, path, body_str)
    local url = BACKEND_BASE .. path
    local cmd
    if body_str then
        local escaped = body_str:gsub('"', '\\"')
        cmd = string.format(
            'curl.exe -s -X %s "%s" -H "Content-Type: application/json" -d "%s" --connect-timeout 15',
            method, url, escaped)
    else
        cmd = string.format('curl.exe -s -X %s "%s" --connect-timeout 15', method, url)
    end
    local ok, result = pcall(m_utils.exec, cmd)
    if not ok or not result then
        return json_err("curl exec failed")
    end
    return result
end

local function backend_request(method, path, body)
    local body_str = nil
    if body then
        local ok, s = pcall(function() return require("cjson").encode(body) end)
        body_str = ok and s or nil
    end
    return curl_request(method, path, body_str)
end

-- ── Ensure the LuaTools app is running ────────────────────────────────────────

local function ensure_backend_running()
    local ok, result = pcall(m_utils.exec,
        'curl.exe -s "' .. BACKEND_BASE .. '/has/0" --connect-timeout 2')
    if ok and result and result ~= "" then return end  -- already up

    local local_appdata = m_utils.getenv("LOCALAPPDATA") or os.getenv("LOCALAPPDATA") or ""
    if local_appdata == "" then
        logger.warn("LOCALAPPDATA not available, cannot launch LuaTools backend")
        return
    end

    local exe_path = local_appdata .. "\\LuaTools\\current\\LuaTools.exe"
    if not fs.exists(exe_path) then
        logger.warn("LuaTools.exe not found at: " .. exe_path)
        return
    end

    pcall(m_utils.exec, 'start "" "' .. exe_path .. '" --minimized')
    logger.log("Launched LuaTools backend: " .. exe_path)
end

-- ── Webkit file deployment ────────────────────────────────────────────────────

local function copy_webkit_files()
    local steam_dir = steam_utils.detect_steam_install_path()
    if not steam_dir or steam_dir == "" then
        logger.error("copy_webkit_files: steam_path empty, aborting")
        return false
    end

    local plugin_dir       = get_plugin_dir()
    local target_webkit_dir = fs.join(steam_dir, "steamui", "webkit")

    if not fs.exists(target_webkit_dir) then
        fs.create_directories(target_webkit_dir)
        logger.log("Created webkit dir: " .. target_webkit_dir)
    end

    local files = {
        { src = fs.join(plugin_dir, "public", "luatools.js"),        dst = fs.join(target_webkit_dir, "luatools.js") },
        { src = fs.join(plugin_dir, "public", "steamdb-webkit.css"), dst = fs.join(target_webkit_dir, "steamdb-webkit.css") },
    }

    local all_ok = true
    for _, f in ipairs(files) do
        if not fs.exists(f.src) then
            logger.error("Source file not found: " .. f.src)
            all_ok = false
        else
            local content = m_utils.read_file(f.src)
            if not content then
                logger.error("read_file failed: " .. f.src)
                all_ok = false
            elseif not m_utils.write_file(f.dst, content) then
                logger.error("write_file failed: " .. f.dst)
                all_ok = false
            else
                logger.log("Deployed: " .. f.src .. " -> " .. f.dst)
            end
        end
    end

    return all_ok
end

local function inject_webkit_files()
    millennium.add_browser_css("webkit/steamdb-webkit.css")
    millennium.add_browser_js("webkit/luatools.js")
    logger.log("Registered browser JS/CSS hooks")
end

-- ── RPC handlers ──────────────────────────────────────────────────────────────

function HasLuaToolsForApp(appid)
    logger.log("HasLuaToolsForApp: " .. tostring(appid))
    return backend_request("GET", "/has/" .. tostring(appid))
end

function DeleteLuaToolsForApp(appid)
    logger.log("DeleteLuaToolsForApp: " .. tostring(appid))
    return backend_request("POST", "/remove/" .. tostring(appid))
end

function CheckApisForApp(appid)
    logger.log("CheckApisForApp: " .. tostring(appid))
    return backend_request("POST", "/check-sources/" .. tostring(appid))
end

function StartAddViaLuaToolsFromUrl(appid, source)
    logger.log("StartAddViaLuaToolsFromUrl: " .. tostring(appid))
    return backend_request("POST", "/download/" .. tostring(appid), { source = source })
end

function GetAddViaLuaToolsStatus(appid)
    return backend_request("GET", "/download-status/" .. tostring(appid))
end

function CancelAddViaLuaTools(appid)
    logger.log("CancelAddViaLuaTools: " .. tostring(appid))
    return backend_request("POST", "/cancel/" .. tostring(appid))
end

function RestartSteam()
    logger.log("RestartSteam called")
    local steam_dir = steam_utils.detect_steam_install_path()
    local is_win = (m_utils.getenv("OS") or os.getenv("OS") or ""):find("Windows") ~= nil

    if is_win and steam_dir and steam_dir ~= "" then
        local steam_exe   = fs.join(steam_dir, "steam.exe")
        local temp_script = (m_utils.getenv("TEMP") or os.getenv("TEMP") or "C:\\Windows\\Temp")
                            .. "\\luatools_restart.cmd"
        local script_content =
            '@echo off\n' ..
            'echo Restarting Steam...\n' ..
            'taskkill /IM steam.exe /F >nul 2>&1\n' ..
            'timeout /t 2 /nobreak >nul\n' ..
            'cd /d "' .. steam_dir .. '"\n' ..
            'start "" "' .. steam_exe .. '"\n' ..
            'exit\n'

        local f = io.open(temp_script, "wb")
        if f then
            f:write(script_content)
            f:close()
            pcall(m_utils.exec, 'start /b cmd /c "' .. temp_script .. '"')
            return json_ok({ restarting = true })
        else
            logger.error("Failed to write restart script")
        end
    end

    -- Fallback: delegate to backend app
    return backend_request("POST", "/restart-steam")
end

function StartLuaToolsAdd(appid)
    logger.log("StartLuaToolsAdd: " .. tostring(appid))
    return backend_request("POST", "/add/" .. tostring(appid))
end

function GetLuaToolsAddStatus(appid)
    return backend_request("GET", "/add-status/" .. tostring(appid))
end

function PickLuaToolsAddSource(appid, source)
    logger.log("PickLuaToolsAddSource: " .. tostring(appid) .. " source=" .. tostring(source))
    return backend_request("POST", "/add-source/" .. tostring(appid), { source = source })
end

function OpenSettings()
    logger.log("OpenSettings called")
    return backend_request("POST", "/open/settings")
end

function OpenFix(appid)
    logger.log("OpenFix: " .. tostring(appid))
    return backend_request("POST", "/open/fix/" .. tostring(appid))
end

function ReadLoadedApps()
    return backend_request("GET", "/loaded-apps")
end

function DismissLoadedApps()
    return backend_request("POST", "/loaded-apps")
end

function OpenExternalUrl(args)
    local url = type(args) == "table" and args.url or args
    if url and type(url) == "string" then
        local is_win = (m_utils.getenv("OS") or ""):find("Windows") ~= nil
        if is_win then
            pcall(m_utils.exec, 'start "" "' .. url .. '"')
        end
    end
    return json_ok({ success = true })
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

local function on_load()
    logger.log("LuaTools on_load() - millennium " .. tostring(millennium.version()))
    ensure_backend_running()
    if copy_webkit_files() then
        inject_webkit_files()
    else
        logger.error("on_load: webkit copy failed - JS/CSS will NOT be injected!")
    end
    millennium.ready()
    logger.log("LuaTools ready.")
end

local function on_unload()
    logger.log("LuaTools on_unload()")
end

local function on_frontend_loaded()
    logger.log("LuaTools on_frontend_loaded() - re-injecting")
    inject_webkit_files()
end

return {
    on_load             = on_load,
    on_unload           = on_unload,
    on_frontend_loaded  = on_frontend_loaded,
    OpenExternalUrl     = OpenExternalUrl,
}
