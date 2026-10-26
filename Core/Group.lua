-- Daño de los demás miembros del grupo.
-- ESO solo informa a cada jugador de su propio daño, así que cada miembro mide el
-- suyo y lo comparte mediante LibGroupCombatStats. La librería envía el DPS en miles
-- y el daño en decenas de miles, así que las cifras de los demás son aproximadas;
-- las tuyas son exactas.
-- En combates de jefe, la vida que pierde el jefe menos lo que ya se conoce da una
-- estimación del daño de los miembros que no comparten sus datos ("resto del grupo").

local NM = NirnhonedMetrics
local U = NM.Utils
local G = {}
NM.Group = G

local lgcs   -- objeto devuelto por LibGroupCombatStats.RegisterAddon

-- Si el resto estimado es menor que esta parte de la vida perdida por los jefes, no
-- se muestra (lo normal es que sean redondeos y escudos, no otro jugador).
local REST_MIN_SHARE = 0.03

-- Devuelve daño total, DPS y daño a jefes de un miembro.
local function MemberValues(dps, fight)
    local lib = LibGroupCombatStats
    if dps.dmgType == lib.DAMAGE_TOTAL then
        local damage = dps.dmg * 10000
        return damage, dps.dps * 1000, damage
    elseif dps.dmgType == lib.DAMAGE_BOSS then
        -- En combates de jefe la librería comparte el DPS total (dps, en miles) y el
        -- DPS al jefe (dmg, en centenas), pero no el daño: se estima con la duración.
        local duration = NM.Fight.Duration(fight)
        local overall = dps.dps * 1000
        return overall * duration, overall, dps.dmg * 100 * duration
    end
end

-- Copia en el combate los últimos datos recibidos de cada miembro. Solo se usan los
-- que cambiaron después de empezar el combate (los anteriores son del combate previo).
function G.Update(fight)
    if not lgcs or not fight or not IsUnitGrouped("player") then return end
    for tag, stats in lgcs:Iterate() do
        local dps = stats.dps
        if not stats.isPlayer and stats.name and dps and (dps._lastChanged or 0) >= fight.start then
            local damage, value, bossDamage = MemberValues(dps, fight)
            if damage and damage > 0 then
                local member = fight.group[stats.name]
                if not member then
                    member = {
                        name = U.FormatName(stats.name),
                        account = stats.displayName,
                    }
                    fight.group[stats.name] = member
                end
                if tag and DoesUnitExist(tag) then member.classId = GetUnitClassId(tag) end
                member.damage = damage
                member.dps = value
                member.bossDamage = bossDamage
            end
        end
    end
    fight.grouped = true
end

-- Daño estimado de los miembros que no comparten sus datos, o nil si no hay.
function G.RestOfGroup(fight)
    if not NM.sv.showRest or not fight.grouped or fight.bossHealthLost <= 0 then return nil end
    local known = fight.myBossDamage
    for _, member in pairs(fight.group) do
        known = known + (member.bossDamage or 0)
    end
    local rest = fight.bossHealthLost - known
    if rest < fight.bossHealthLost * REST_MIN_SHARE then return nil end
    return rest
end

function G.Init()
    -- Pedir "DPS" hace que la librería comparta tu DPS con el grupo; sin pedirlo
    -- se siguen recibiendo los datos de los demás.
    lgcs = LibGroupCombatStats.RegisterAddon(NM.name, NM.sv.shareDps and { "DPS" } or {})
end
