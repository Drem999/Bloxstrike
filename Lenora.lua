-- basic checks before booting the main bloxstrike ui

local player = game:GetService("Players").LocalPlayer

-- early kick setup so we can boot bad executors immediately
local function kickUser(errCode, reason)
    player:Kick(string.format(
        "[Lenora Loader]\nExecutor not supported.\n\n[Error %02d - %s]\n\nDiscord: https://discord.gg/6p9UScU8gv",
        errCode, reason
    ))
end

-- hard block known trash/isolated environments that 100% crash on hooks
local execName = string.lower(identifyexecutor and identifyexecutor() or "")
if execName == "" or execName:find("solara") or execName:find("xeno") then
    player:Kick("[Lenora Loader]\nExecutor not supported.\n\nDiscord: https://discord.gg/6p9UScU8gv")
    return
end

if not xpcall then
    kickUser(0, "xpcall missing (ancient executor)")
    return
end

-- wrap everything in an xpcall loop so execution crashes don't leave lingering state
xpcall(function()
    
    -- check if getgenv is actually accessible
    if type(getgenv) ~= "function" or type(getgenv()) ~= "table" then
        return kickUser(1, "getgenv invalid")
    end
    local env = getgenv()

    -- make sure cloneref exists (vital for service obfuscation)
    if type(cloneref) ~= "function" then
        return kickUser(2, "cloneref missing")
    end
    
    local crSuccess = pcall(function()
        assert(cloneref(game:GetService("Players")) ~= nil)
    end)
    if not crSuccess then
        return kickUser(3, "cloneref broken")
    end

    -- verify hooking methods exist before trying to modify inventory controllers
    if type(hookfunction) ~= "function" or type(newcclosure) ~= "function" then
        return kickUser(4, "hooking api missing")
    end

    -- test run a hook on a local table to bypass basic mock detections
    local hookFired = false
    local testObj = { test = function() return false end }
    local originalMethod
    
    local hookSuccess = pcall(function()
        originalMethod = hookfunction(testObj.test, newcclosure(function(...)
            hookFired = true
            return originalMethod(...)
        end))
        testObj.test() -- trigger
    end)

    -- restore original state cleanly
    if originalMethod then pcall(hookfunction, testObj.test, originalMethod) end
    
    if not hookSuccess or not hookFired then
        return kickUser(5, "hookfunction failed live run")
    end

    -- fix thread identity aliases across different executors
    local setIdentityFunc = setthreadidentity or setidentity or setcontext
    if type(setIdentityFunc) ~= "function" then
        return kickUser(6, "setthreadidentity missing")
    end
    if not rawget(env, "setthreadidentity") then
        env.setthreadidentity = setIdentityFunc -- canonical patch for bloxstrike script
    end

    -- verify filesystem APIs (required for skin configs)
    local neededFS = {
        {"isfolder", isfolder}, {"makefolder", makefolder}, 
        {"readfile", readfile}, {"writefile", writefile}, 
        {"listfiles", listfiles}, {"isfile", isfile}, {"delfile", delfile}
    }
    for i, api in ipairs(neededFS) do
        if type(api[2]) ~= "function" then
            return kickUser(6 + i, "Missing filesystem function: " .. api[1])
        end
    end

    -- live sandbox read/write/delete test
    local fsSuccess = pcall(function()
        if not isfolder("Lenora") then makefolder("Lenora") end
        writefile("Lenora/_test.tmp", "ok")
        assert(isfile("Lenora/_test.tmp"))
        assert(readfile("Lenora/_test.tmp") == "ok")
        delfile("Lenora/_test.tmp")
    end)
    if not fsSuccess then
        return kickUser(14, "workspace writing sandboxed/blocked")
    end

    -- check if getconnections is functional (final benchmark for native execution health)
    local getConnsFunc = env.getconnections or getconnections
    if type(getConnsFunc) ~= "function" then
        return kickUser(15, "getconnections missing")
    end
    
    local connsTable
    local gcSuccess = pcall(function()
        connsTable = getConnsFunc(player.Changed) -- use a stable core signal instead of volatile frame loops
    end)
    if not gcSuccess or type(connsTable) ~= "table" then
        return kickUser(16, "getconnections structural failure")
    end
    
    if #connsTable > 0 then
        local hasDisableField = false
        for _, signal in next, connsTable do
            if signal.Disable then
                hasDisableField = true
                break
            end
        end
        if not hasDisableField then
            return kickUser(17, "signals missing .Disable index")
        end
    end

    -- everything checked out cleanly, pulling main script
    local SCRIPT_URL = "https://raw.githubusercontent.com/YourRepo/Lenora/main/BloxstrikeV3.lua"

    if SCRIPT_URL == "" then
        warn("[Lenora] Developer Warning: Script URL is empty!")
        return
    end

    local mainSuccess, mainError = pcall(function()
        loadstring(game:HttpGet(SCRIPT_URL, true))()
    end)
    if not mainSuccess then
        return kickUser(18, "failed to run hosted payload: " .. tostring(mainError))
    end

end, function(panicMsg)
    -- fallback catcher if the executor natively panics mid-execution
    player:Kick("[Lenora Loader Critical Panic]\n\n" .. tostring(panicMsg))
end)
