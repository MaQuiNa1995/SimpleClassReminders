local addonName, addon = ...
addon.L = addon.L or {}
local L = addon.L

-- Constantes
local HEALTHSTONE_ITEM_IDS = {
    224464, -- Con talento de warlock
    5512,   -- Normal
}
local FORTITUDE_SPELL_ID = 21562 -- Palabra de poder: Entereza
local DEVOTION_AURA_SPELL_ID = 465 -- Aura de devocion

local LETHAL_POISONS = {
    [2823]   = true, -- Deadly Poison
    [8679]   = true, -- Wound Poison
    [315584] = true, -- Instant Poison
}

local NON_LETHAL_POISONS = {
    [3408]   = true, -- Crippling Poison
    [5761]   = true, -- Numbing Poison
    [381637] = true, -- Atrophic Poison
}


-- =========================
-- Funciones Utilitarias
-- =========================

local function PlayerClass()
    local _, class = UnitClass("player")
    return class
end

local function PlayerIs(class)
    return PlayerClass() == class
end

local function PlayerHasHealthstone()
    for _, itemID in ipairs(HEALTHSTONE_ITEM_IDS) do
        local count = GetItemCount(itemID, false, false)
        if count and count > 0 then
            return true
        end
    end
    return false
end

local function GroupHasWarlock()
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unit = "raid" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                if class == "WARLOCK" then
                    return true
                end
            end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then
                local _, class = UnitClass(unit)
                if class == "WARLOCK" then
                    return true
                end
            end
        end
    end
    return false
end

local function PlayerShouldHavePet()
    return PlayerIs("WARLOCK") or PlayerIs("HUNTER")
end

local function PlayerHasPet()
    return UnitExists("pet")
end

local function CanShow()
    return not UnitIsDeadOrGhost("player") and not UnitHasVehicleUI("player")
end

-- =========================
-- Bufos
-- =========================

local function UnitHasAuraBySpellId(unit, spellID)
    if AuraUtil and AuraUtil.ForEachAura then
        local found = false
        AuraUtil.ForEachAura(unit, "HELPFUL", nil, function(aura)
            if aura and aura.spellId == spellID then
                found = true
                return true -- corta
            end
        end)
        if found then return true end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local index = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
            if not aura then break end
            if aura.spellId == spellID then
                return true
            end
            index = index + 1
        end
    end

    return false
end

local function GroupAllHaveFortitude()

    if not UnitHasAuraBySpellId("player", FORTITUDE_SPELL_ID) then
        return false
    end

 	local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    elseif IsInGroup() then
        prefix, count = "party", GetNumSubgroupMembers()
    end

    if prefix then
        for i = 1, count do
            local unit = prefix .. i
            if UnitExists(unit)
               and not UnitIsDeadOrGhost(unit)
               and not UnitHasAuraBySpellId(unit, FORTITUDE_SPELL_ID)
            then
                return false
            end
        end
    end

    return true
end

local function PlayerHasPoison(poisonSpellIDs)
    local i = 1
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end

        if aura.spellId and poisonSpellIDs[aura.spellId] then
            return true
        end
        i = i + 1
    end
    return false
end


local function PlayerHasLethalPoison()
    return PlayerHasPoison(LETHAL_POISONS)
end

local function PlayerHasNonLethalPoison()
    return PlayerHasPoison(NON_LETHAL_POISONS)
end


-- ==================================================
-- Anchor
-- Frame utilitario para colocar los mensajes
-- ==================================================
local anchor = CreateFrame("Frame", nil, UIParent)
anchor:SetPoint("TOP", UIParent, "TOP", 0, -80)
anchor:SetSize(1, 1)

local function StyleText(fs)
	-- gris
    fs:SetTextColor(0.7, 0.7, 0.7, 1)   
	-- sombra visible
    fs:SetShadowOffset(2, -2)         
	-- negro
    fs:SetShadowColor(0, 0, 0, 1)
end

-- =========================
-- TEXTOS
-- =========================

-- General - Piedras de brujo
local stoneText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
stoneText:SetPoint("TOP", anchor, "TOP", 0, 0)
stoneText:SetText(L.NO_HEALTHSTONE)
StyleText(stoneText)
stoneText:Hide()

-- Sacerdote
local fortitudeText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
fortitudeText:SetPoint("TOP", anchor, "TOP", 0, -60)
fortitudeText:SetText(L.NO_FORTITUDE)
StyleText(fortitudeText)
fortitudeText:Hide()

-- Paladin
local devotionText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
devotionText:SetPoint("TOP", anchor, "TOP", 0, -60)
devotionText:SetText(L.NO_DEVOTION)
StyleText(devotionText)
devotionText:Hide()

-- Mascotas
local petText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
petText:SetPoint("TOP", anchor, "TOP", 0, -120)
petText:SetText(L.NO_PET)
StyleText(petText)
petText:Hide()

-- Rogue - veneno letal
local lethalPoisonText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
lethalPoisonText:SetPoint("TOP", anchor, "TOP", 0, -60)
lethalPoisonText:SetText(L.NO_LETHAL_POISON)
StyleText(lethalPoisonText)
lethalPoisonText:Hide()

-- Rogue - veneno no letal
local nonLethalPoisonText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
nonLethalPoisonText:SetPoint("TOP", anchor, "TOP", 0, -120)
nonLethalPoisonText:SetText(L.NO_NON_LETHAL_POISON)
StyleText(nonLethalPoisonText)
nonLethalPoisonText:Hide()

-- =========================
-- Logica de alertas
-- =========================

local function UpdateAlerts()
	if not CanShow() then
	    stoneText:Hide()
	    petText:Hide()
	    fortitudeText:Hide()
		devotionText:Hide()
		lethalPoisonText:Hide()
		nonLethalPoisonText:Hide()
	    return
	end

	-- Piedra de Brujo
	stoneText:SetShown((PlayerIs("WARLOCK") or GroupHasWarlock()) and not PlayerHasHealthstone())

	-- Mascota
	petText:SetShown(PlayerShouldHavePet() and not PlayerHasPet())

	-- Palabra de Poder Entereza
	fortitudeText:SetShown(PlayerIs("PRIEST") and not GroupAllHaveFortitude())

	-- Aura de devocion
	devotionText:SetShown(PlayerIs("PALADIN") and not UnitHasAuraBySpellId("player", DEVOTION_AURA_SPELL_ID))
	
	-- Venenos de rogue
	if PlayerIs("ROGUE") then
	    lethalPoisonText:SetShown(not PlayerHasLethalPoison())
	    nonLethalPoisonText:SetShown(not PlayerHasNonLethalPoison())
	else
	    lethalPoisonText:Hide()
	    nonLethalPoisonText:Hide()
	end
	
end

-- =========================
-- Registro de Eventos
-- =========================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_AURA")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")


f:SetScript("OnEvent", function(_, event, unit)
    if unit and unit ~= "player" then return end
    UpdateAlerts()
end)

UpdateAlerts()
