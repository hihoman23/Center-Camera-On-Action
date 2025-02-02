
function widget:GetInfo()
    return {
      name = "Factory Quotas",
      desc = "Creates quotas of units that should be fulfilled(for example 5 Sheldons, 5 Sumos), will be queued before factory queue.",
      author = "hihoman23",
      date = "2024",
      license = "GNU GPL, v2 or later",
      layer = -1,
      enabled = true
    }
end

VFS.Include('luarules/configs/customcmds.h.lua')

local maxBuildProg = 0.075 -- maximum build progress that gets replaced in a repeat queue
local maxMetal = 500 -- maximum metal cost that gets replaced in a repeat queue(7.5% of a juggernaut is still over 2k metal)

local quotas = {} -- {[factID] = {[unitDefID] = amount, ...}, ...}

local allUnits = {}

local builtUnits = {} -- {[factID] = {[unitID] = true, ...}, ...}
local unitFacts = {} -- {[unitID] = factID, ...}

local possibleFacts = {}
local factoryDefIDs = {}
local factBuildOpts = {}
local metalcosts = {}

for unitDefID, uDef in pairs(UnitDefs) do
    metalcosts[unitDefID] = uDef.metalCost
    if uDef.isFactory then
        factoryDefIDs[unitDefID] = true
        factBuildOpts[unitDefID] = table.copy(uDef.buildOptions)
        for _, opt in pairs(uDef.buildOptions) do
            possibleFacts[opt] = possibleFacts[opt] or {}
            possibleFacts[opt][unitDefID] = true
        end
    end
end

----- Speeeed ------
local myTeam = Spring.GetMyTeamID()
local GiveOrderToUnit = Spring.GiveOrderToUnit
local GetFactoryCommands = Spring.GetFactoryCommands
local GetUnitDefID = Spring.GetUnitDefID
-----




--------- quota logic -------------
---@param table table
---@param f function|nil
local function findMin(table, f)
    f = f or function(i1, i2, _, _) return i1 < i2 end
    local best
    local bestKey
    for k, v in pairs(table) do
        if not best then
            best = v
            bestKey = k
        elseif f(v, best, k, bestKey) then
            best = v
            bestKey = k
        end
    end
    return best, bestKey
end

---length of all tables
---@param table table
---@return integer
function table.length(table)
    local x = 0
    for _ in pairs(table or {}) do
        x = x + 1
    end
    return x
end

local function isFactoryUsable(factoryID)
    local commandq = GetFactoryCommands(factoryID, 2)
    if not commandq then
        return true
    end
    return commandq and( #commandq == 0 or not (commandq[1].options.alt or (commandq[2] and commandq[2].options.alt)))
end

local function putInFrontOfFactQ(...)
    local factID, cmdID, params, opts = ...
    local commandq = GetFactoryCommands(factID, -1)
    local altCmds = {}
    local others = {}
    for _, cmd in ipairs(commandq) do
        if cmd.options.alt then
            altCmds[#altCmds+1] = cmd
        else
            others[#others+1] = cmd
        end
    end

    GiveOrderToUnit(factID, 13923, {}, {}) -- clear queue

    for i = #altCmds, 1, -1 do -- do alt q backwards
        local cmd = altCmds[i]
        GiveOrderToUnit(factID, cmd.id, cmd.params, cmd.options)
    end
    GiveOrderToUnit(...)
    for _, cmd in ipairs(others) do
        GiveOrderToUnit(factID, cmd.id, cmd.params, cmd.options)
    end
end

local function insertToFactQ(...)
    local factID, cmdID, params, opts = ...
    local currCmd, targetID = Spring.GetUnitWorkerTask(factID)
    local insertnormally = true
    if targetID and Spring.GetUnitStates(factID)["repeat"] then
        local _, _, _, _, buildProgress = Spring.GetUnitHealth(targetID)
        if buildProgress < maxBuildProg and metalcosts[-currCmd] and (buildProgress * metalcosts[-currCmd]) < maxMetal then -- 7.5 % is the most that it is willing to sacrifice, and maximally 500 metal
            insertnormally = false
        end
    end
    if insertnormally then
        GiveOrderToUnit(...)
    else
        putInFrontOfFactQ(...)
    end
end

local function fillQuotas()
    for factID, quota in pairs(quotas) do
        if isFactoryUsable(factID) then
            for udefid, num in pairs(quota) do
                if num == 0 then
                    quota[udefid] = nil
                end
            end
            if table.length(quota)>0 then
                local function isBetter(q1, q2, k1, k2)
                    return (table.length((builtUnits[factID] or {})[k1] or {})/q1) < (table.length((builtUnits[factID] or {})[k2] or {})/q2)
                end
                local quotaNum, uDefID = findMin(quota, isBetter)
                if quotaNum > table.length((builtUnits[factID] or {})[uDefID] or {}) then
                    insertToFactQ(factID, -uDefID, {}, {"alt"})
                end
            end
        end
    end
end

function widget:GameFrame(n)
    if n % 30 == 0 then
        fillQuotas()
    end
end



function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    if builderID and unitTeam == myTeam and factoryDefIDs[GetUnitDefID(builderID)] then
        builtUnits[builderID] = builtUnits[builderID] or {}
        builtUnits[builderID][unitDefID] = builtUnits[builderID][unitDefID] or {}
        builtUnits[builderID][unitDefID][unitID] = true
        unitFacts[unitID] = builderID
        if WG["gridmenu"] and WG["gridmenu"].forceReload then
            WG["gridmenu"].forceReload()
        end
    end
end

local function removeUnit(unitID, unitDefID, unitTeam)
    if unitTeam == myTeam and unitFacts[unitID] then --check if it was built by the same player
        builtUnits[unitFacts[unitID]][unitDefID][unitID] = nil
        unitFacts[unitID] = nil
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    removeUnit(unitID, unitDefID, unitTeam)
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if myTeam == oldTeam and myTeam ~= newTeam then
        removeUnit(unitID, unitDefID, myTeam)
    end
end

local function clearQuotas(cmd, optLine, optWords, data, isRepeat, release, actions)
    local deleteAll = optWords and (optWords[1] == "all")

    if deleteAll then
        quotas = {}
    elseif WG["gridmenu"] and WG["gridmenu"].getActiveBuilderID and WG["gridmenu"].getActiveBuilderID() then
        quotas[WG["gridmenu"].getActiveBuilderID()] = nil
    end

    if WG["gridmenu"] and WG["gridmenu"].forceReload then
        WG["gridmenu"].forceReload()
    end
end

function widget:PlayerChanged(playerID)
    if Spring.GetSpectatingState() then
        widgetHandler:RemoveWidget(self)
    end
    myTeam = Spring.GetMyTeamID()
end

function widget:Initialize()
    widget:PlayerChanged()

    for unitName, _ in pairs(quotas) do
        quotas[UnitDefNames[unitName].id] = quotas[unitName]
        quotas[unitName] = nil
    end

    widgetHandler:AddAction("delete_quotas", clearQuotas, nil, "p")

    WG.Quotas = {}
    WG.Quotas.getQuotas = function()
        return quotas
    end
    WG.Quotas.update = function(newQuotas)
        quotas = newQuotas
    end
    WG.Quotas.getUnitAmount = function(factID, unitDefID)
        return table.length((builtUnits[factID] or {})[unitDefID])
    end

end

function widget:Shutdown()
    WG.Quotas = nil
end
