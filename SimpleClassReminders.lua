local addonName, addon = ...
addon.L = addon.L or {}
local L = addon.L

-- Constantes
local HEALTHSTONE_ITEM_IDS = {
    224464, -- Con talento de warlock
    5512,   -- Normal
}
local FORTITUDE_SPELL_ID = 21562 -- Palabra de poder: Entereza
local WILD_MARK_SPELL_ID = 1126 -- Marca de lo salvaje
local BRONZE_BLESSING_ID = 381748 -- Bendicion de bronce
local ARCANE_INTELLECT_SPELL_ID = 1459 -- Intelecto Arcano
local SKYFURY_SPELL_ID = 462854 -- Furia del cielo

local DEVOTION_AURA_SPELL_ID = 465 -- Aura de devocion

local TALENT_SUMMON_ELEMENTAL_LEARNED = false
local TALENT_SUMMON_ELEMENTAL_SPELL_ID = 31687 -- Invocar elemental

local SPEC_DK_UNHOLY = 252 -- Spec de profano


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
    if PlayerIs("WARLOCK") or PlayerIs("HUNTER") then
        return true
    end

    if PlayerIs("MAGE") then
        return TALENT_SUMMON_ELEMENTAL_LEARNED
    end

    if PlayerIs("DEATHKNIGHT") then
        local specIndex = GetSpecialization()
        if not specIndex then return false end

        local specID = GetSpecializationInfo(specIndex)
        return specID == SPEC_DK_UNHOLY
    end

    return false
end


local function PlayerHasPet()
    return UnitExists("pet")
end

local function CanShow()
    return not UnitIsDeadOrGhost("player") and not UnitHasVehicleUI("player") and not IsMounted()
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
                return found
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

local function GroupAllHaveBlessing(spellID)
	
    if not UnitHasAuraBySpellId("player", spellID) then
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
               and not UnitHasAuraBySpellId(unit, spellID)
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

local function ShamanHasWeaponEnchants()
    local hasMH, _, _, hasOH = GetWeaponEnchantInfo()

    if not hasMH and not hasOH then
        return false
    end

    -- Main hand
    local mainHandLink = GetInventoryItemLink("player", 16)
    if not mainHandLink then return false end

    -- Off hand
    local offHandLink = GetInventoryItemLink("player", 17)

    -- Baston
    if not offHandLink then
        return true
    end

    local _, _, _, _, _, _, _, _, offhandEquipLoc = GetItemInfo(offHandLink)

    -- Escudo
    if offhandEquipLoc == "INVTYPE_SHIELD" then
        return true
    end

    -- 2 armas principales (Mejora)
    return true
end




local function PlayerHasLethalPoison()
    return PlayerHasPoison(LETHAL_POISONS)
end

local function PlayerHasNonLethalPoison()
    return PlayerHasPoison(NON_LETHAL_POISONS)
end

local function DKHasWeaponRune()
    local itemLink = GetInventoryItemLink("player", 16)
    if not itemLink then return false end

    -- El formato del link es: item:ITEMID:ENCHANTID:...
    local enchantID = itemLink:match("item:%d+:(%d+):")

    return enchantID and tonumber(enchantID) ~= 0
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

-- Druida
local wildMarkText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
wildMarkText:SetPoint("TOP", anchor, "TOP", 0, -60)
wildMarkText:SetText(L.NO_MARK_OF_THE_WILD)
StyleText(wildMarkText)
wildMarkText:Hide()

-- Evoker
local bronzeBlessingText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bronzeBlessingText:SetPoint("TOP", anchor, "TOP", 0, -60)
bronzeBlessingText:SetText(L.NO_BRONZE_BLESSING)
StyleText(bronzeBlessingText)
bronzeBlessingText:Hide()

-- Mago
local arcaneIntellectText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
arcaneIntellectText:SetPoint("TOP", anchor, "TOP", 0, -60)
arcaneIntellectText:SetText(L.NO_ARCANE_INTELLECT)
StyleText(arcaneIntellectText)
arcaneIntellectText:Hide()

-- Chaman
local skyfuryText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
skyfuryText:SetPoint("TOP", anchor, "TOP", 0, -60)
skyfuryText:SetText(L.NO_SKYFURY)
StyleText(skyfuryText)
skyfuryText:Hide()

local shamanWeaponText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
shamanWeaponText:SetPoint("TOP", anchor, "TOP", 0, -120)
shamanWeaponText:SetText(L.NO_SHAMAN_WEAPON_ENCHANT)
StyleText(shamanWeaponText)
shamanWeaponText:Hide()

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

-- DK - runa de arma
local dkRuneText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
dkRuneText:SetPoint("TOP", anchor, "TOP", 0, -60)
dkRuneText:SetText(L.NO_DK_RUNE)
StyleText(dkRuneText)
dkRuneText:Hide()

-- =========================
-- Logica de alertas
-- =========================

local function UpdateAlerts()
	
	-- No funciona en combate por la purga de addons de blizzard
	if InCombatLockdown() then return end

	if not CanShow() then
		dkRuneText:Hide()
	    stoneText:Hide()
	    petText:Hide()
	    fortitudeText:Hide()
		wildMarkText:Hide()
		bronzeBlessingText:Hide()
		devotionText:Hide()
		lethalPoisonText:Hide()
		nonLethalPoisonText:Hide()
		arcaneIntellectText:Hide()
		skyfuryText:Hide()
	    return
	end

	-- Piedra de Brujo
	stoneText:SetShown((PlayerIs("WARLOCK") or GroupHasWarlock()) and not PlayerHasHealthstone())

	-- Mascota
	petText:SetShown(PlayerShouldHavePet() and not PlayerHasPet())

	-- Palabra de Poder: Entereza
	fortitudeText:SetShown(PlayerIs("PRIEST") and not GroupAllHaveBlessing(FORTITUDE_SPELL_ID))

	-- Marca de lo Salvaje
	wildMarkText:SetShown(PlayerIs("DRUID") and not GroupAllHaveBlessing(WILD_MARK_SPELL_ID))

	-- Bendición de Bronce
	bronzeBlessingText:SetShown(PlayerIs("EVOKER") and not GroupAllHaveBlessing(BRONZE_BLESSING_ID))
	
	-- Intelecto Arcano
	arcaneIntellectText:SetShown(PlayerIs("MAGE") and not GroupAllHaveBlessing(ARCANE_INTELLECT_SPELL_ID))

	-- Aura de devocion
	devotionText:SetShown(PlayerIs("PALADIN") and not UnitHasAuraBySpellId("player", DEVOTION_AURA_SPELL_ID))
	
	-- Furia del cielo
	skyfuryText:SetShown(PlayerIs("SHAMAN") and not GroupAllHaveBlessing(SKYFURY_SPELL_ID))
	
	-- Encantamientos de arma (Chaman)
	if PlayerIs("SHAMAN") then
	    shamanWeaponText:SetShown(not ShamanHasWeaponEnchants())
	else
	    shamanWeaponText:Hide()
	end

	
	-- Venenos de rogue
	if PlayerIs("ROGUE") then
	    lethalPoisonText:SetShown(not PlayerHasLethalPoison())
	    nonLethalPoisonText:SetShown(not PlayerHasNonLethalPoison())
	else
	    lethalPoisonText:Hide()
	    nonLethalPoisonText:Hide()
	end
	
	-- Runa de arma DK
	dkRuneText:SetShown(PlayerIs("DEATHKNIGHT") and not DKHasWeaponRune())
end

local function UpdateTalentSummonElemental()
    TALENT_SUMMON_ELEMENTAL_LEARNED = false

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local configInfo = C_Traits.GetConfigInfo(configID)
    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            if nodeInfo and nodeInfo.activeEntry then
                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                if entryInfo and entryInfo.definitionID then
                    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    if defInfo and defInfo.spellID == TALENT_SUMMON_ELEMENTAL_SPELL_ID then
                        TALENT_SUMMON_ELEMENTAL_LEARNED = true
                        return
                    end
                end
            end
        end
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
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("TRAIT_TREE_CHANGED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

f:SetScript("OnEvent", function(_, event, unit)
	
	if event == "TRAIT_CONFIG_UPDATED"
		or event == "TRAIT_TREE_CHANGED"
		or event == "PLAYER_SPECIALIZATION_CHANGED"
		or event == "PLAYER_ENTERING_WORLD"
	then
		UpdateTalentSummonElemental()
	end
	
    if unit and unit ~= "player" then return end
    UpdateAlerts()
end)

UpdateAlerts()
