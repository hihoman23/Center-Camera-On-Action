function widget:GetInfo()
    return {
        name    = "Attacked Unit Ping",
        desc    = "Adds button that sends camera to attacked units.",
        author  = "hihoman23",
        date    = "2023",
        license = "GNU GPL, v3 or later",
        layer   = 0,
        enabled = true --  loaded by default?
    }
end

local attackedUnit
local whenAttacked
local reactTime = 5 --how long you have to press the button to send camera to attacked unit

function widget:GameFrame(n)

end

function widget:UnitDamaged(unitID)

end
