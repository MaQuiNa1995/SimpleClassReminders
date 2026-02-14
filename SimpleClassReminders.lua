local addonName, addon = ...
addon.L = addon.L or {}
local L = addon.L

-- ==================================================
-- Cache / Constantes
-- ==================================================
local _, PLAYER_CLASS = UnitClass("player")

local IN_COMBAT = false

local HEALTHSTONE_ITEM_IDS = {
    224464, -- Con talento de warlock
    5512,   -- Normal
}

local FORTITUDE_SPELL_ID            = 21562  -- Palabra de poder: Entereza
local WILD_MARK_SPELL_ID            = 1126   -- Marca de lo salvaje
local BRONZE_BLESSING_ID            = 381748 -- Bendición de bronce
local ARCANE_INTELLECT_SPELL_ID     = 1459   -- Intelecto arcano
local SKYFURY_SPELL_ID              = 462854 -- Furia del cielo
local DEVOTION_AURA_SPELL_ID        = 465    -- Aura de devoción

local TALENT_SUMMON_ELEMENTAL_LEARNED   = false
local TALENT_SUMMON_ELEMENTAL_SPELL_ID  = 31687 -- Invocar elemental

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

-- ==================================================
-- Cache de grupo (evita escanear roster en cada update)
-- ==================================================
local GROUP_HAS_WARLOCK = false

local function UpdateGroupFlags()
    GROUP_HAS_WARLOCK = false
    if not IsInGroup() then return end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    else
        prefix, count = "party", GetNumSubgroupMembers()
    end

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class == "WARLOCK" then
                GROUP_HAS_WARLOCK = true
                break
            end
        end
    end
end

-- ==================================================
-- Utilidades
-- ==================================================
local function CanShow()
    return not UnitIsDeadOrGhost("player")
        and not UnitHasVehicleUI("player")
        and not IsMounted()
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

local function PlayerHasPet()
    return UnitExists("pet")
end

local function PlayerShouldHavePet()
    if PLAYER_CLASS == "WARLOCK" or PLAYER_CLASS == "HUNTER" then
        return true
    end

    if PLAYER_CLASS == "MAGE" then
        return TALENT_SUMMON_ELEMENTAL_LEARNED
    end

    if PLAYER_CLASS == "DEATHKNIGHT" then
        local specIndex = GetSpecialization()
        if not specIndex then return false end
        local specID = GetSpecializationInfo(specIndex)
        return specID == SPEC_DK_UNHOLY
    end

    return false
end

-- ==================================================
-- Auras / Bufos
-- ==================================================
local function UnitHasAuraBySpellId(unit, spellID)
    -- Vía rápida para player
    if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil
    end

    -- AuraUtil.FindAuraBySpellId (si existe)
    if AuraUtil and AuraUtil.FindAuraBySpellId then
        return AuraUtil.FindAuraBySpellId(spellID, unit, "HELPFUL") ~= nil
    end

    -- Fallback: iterar auras (último recurso)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local i = 1
        while true do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not aura then break end
            if aura.spellId == spellID then return true end
            i = i + 1
        end
    end

    return false
end

local function GroupAllHaveBlessing(spellID)
    -- Si estás solo, basta con el jugador
    if not UnitHasAuraBySpellId("player", spellID) then
        return false
    end
    if not IsInGroup() then
        return true
    end

    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", GetNumGroupMembers()
    else
        prefix, count = "party", GetNumSubgroupMembers()
    end

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit)
            and not UnitIsDeadOrGhost(unit)
            and not UnitHasAuraBySpellId(unit, spellID)
        then
            return false
        end
    end

    return true
end

local function PlayerHasPoison(poisonSpellIDs)
    local i = 1

    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then
            break
        end

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

local function ShamanHasWeaponEnchants()
    local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
    -- Si no hay ninguno, no cumple
    if not hasMH and not hasOH then
        return false
    end

    -- Si hay main hand encantada, ya es suficiente para la alerta (tu lógica original devolvía true)
    -- Mantengo tu intención: si hay bastón o escudo también OK.
    local offHandLink = GetInventoryItemLink("player", 17)
    if not offHandLink then
        return true -- bastón / 2H
    end

    local _, _, _, _, _, _, _, _, offhandEquipLoc = GetItemInfo(offHandLink)
    if offhandEquipLoc == "INVTYPE_SHIELD" then
        return true
    end

    -- Dual-wield o cualquier offhand: si hay encantamientos detectados, OK
    return true
end

local function DKHasWeaponRune()
    local itemLink = GetInventoryItemLink("player", 16)
    if not itemLink then return false end
    local enchantID = itemLink:match("item:%d+:(%d+):")
    return enchantID and tonumber(enchantID) ~= 0
end

-- ==================================================
-- Anchor + Estilo
-- ==================================================
local anchor = CreateFrame("Frame", nil, UIParent)
anchor:SetPoint("TOP", UIParent, "TOP", 0, -80)
anchor:SetSize(1, 1)

local function StyleText(fs)
    fs:SetTextColor(0.7, 0.7, 0.7, 1)
    fs:SetShadowOffset(2, -2)
    fs:SetShadowColor(0, 0, 0, 1)
end

-- ==================================================
-- Textos (UI)
-- ==================================================
local stoneText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
stoneText:SetPoint("TOP", anchor, "TOP", 0, 0)
stoneText:SetText(L.NO_HEALTHSTONE)
StyleText(stoneText)
stoneText:Hide()

local fortitudeText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
fortitudeText:SetPoint("TOP", anchor, "TOP", 0, -60)
fortitudeText:SetText(L.NO_FORTITUDE)
StyleText(fortitudeText)
fortitudeText:Hide()

local wildMarkText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
wildMarkText:SetPoint("TOP", anchor, "TOP", 0, -60)
wildMarkText:SetText(L.NO_MARK_OF_THE_WILD)
StyleText(wildMarkText)
wildMarkText:Hide()

local bronzeBlessingText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
bronzeBlessingText:SetPoint("TOP", anchor, "TOP", 0, -60)
bronzeBlessingText:SetText(L.NO_BRONZE_BLESSING)
StyleText(bronzeBlessingText)
bronzeBlessingText:Hide()

local arcaneIntellectText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
arcaneIntellectText:SetPoint("TOP", anchor, "TOP", 0, -60)
arcaneIntellectText:SetText(L.NO_ARCANE_INTELLECT)
StyleText(arcaneIntellectText)
arcaneIntellectText:Hide()

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

local devotionText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
devotionText:SetPoint("TOP", anchor, "TOP", 0, -60)
devotionText:SetText(L.NO_DEVOTION)
StyleText(devotionText)
devotionText:Hide()

local petText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
petText:SetPoint("TOP", anchor, "TOP", 0, -120)
petText:SetText(L.NO_PET)
StyleText(petText)
petText:Hide()

local lethalPoisonText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
lethalPoisonText:SetPoint("TOP", anchor, "TOP", 0, -60)
lethalPoisonText:SetText(L.NO_LETHAL_POISON)
StyleText(lethalPoisonText)
lethalPoisonText:Hide()

local nonLethalPoisonText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
nonLethalPoisonText:SetPoint("TOP", anchor, "TOP", 0, -120)
nonLethalPoisonText:SetText(L.NO_NON_LETHAL_POISON)
StyleText(nonLethalPoisonText)
nonLethalPoisonText:Hide()

local dkRuneText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
dkRuneText:SetPoint("TOP", anchor, "TOP", 0, -60)
dkRuneText:SetText(L.NO_DK_RUNE)
StyleText(dkRuneText)
dkRuneText:Hide()

local ALL_TEXTS = {
    dkRuneText,
    stoneText,
    petText,
    fortitudeText,
    wildMarkText,
    bronzeBlessingText,
    devotionText,
    lethalPoisonText,
    nonLethalPoisonText,
    arcaneIntellectText,
    skyfuryText,
    shamanWeaponText,
}

local function HideAllTexts()
    for _, t in ipairs(ALL_TEXTS) do
        t:Hide()
    end
end

-- ==================================================
-- Talentos
-- ==================================================
local function UpdateTalentSummonElemental()
    TALENT_SUMMON_ELEMENTAL_LEARNED = false

    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return end

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

-- ==================================================
-- Lógica de alertas (optimizada)
-- ==================================================
local function UpdateAlerts()
    -- No funciona en combate por la purga de addons de blizzard
    if InCombatLockdown() then return end

    if not CanShow() then
        HideAllTexts()
        return
    end

    -- Healthstone (solo depende de warlock player o en grupo)
    stoneText:SetShown((PLAYER_CLASS == "WARLOCK" or GROUP_HAS_WARLOCK) and not PlayerHasHealthstone())

    -- Mascota
    petText:SetShown(PlayerShouldHavePet() and not PlayerHasPet())

    -- Buffos por clase
    if PLAYER_CLASS == "PRIEST" then
        fortitudeText:SetShown(not GroupAllHaveBlessing(FORTITUDE_SPELL_ID))
    else
        fortitudeText:Hide()
    end

    if PLAYER_CLASS == "DRUID" then
        wildMarkText:SetShown(not GroupAllHaveBlessing(WILD_MARK_SPELL_ID))
    else
        wildMarkText:Hide()
    end

    if PLAYER_CLASS == "EVOKER" then
        bronzeBlessingText:SetShown(not GroupAllHaveBlessing(BRONZE_BLESSING_ID))
    else
        bronzeBlessingText:Hide()
    end

    if PLAYER_CLASS == "MAGE" then
        arcaneIntellectText:SetShown(not GroupAllHaveBlessing(ARCANE_INTELLECT_SPELL_ID))
    else
        arcaneIntellectText:Hide()
    end

    if PLAYER_CLASS == "PALADIN" then
        devotionText:SetShown(not UnitHasAuraBySpellId("player", DEVOTION_AURA_SPELL_ID))
    else
        devotionText:Hide()
    end

    if PLAYER_CLASS == "SHAMAN" then
        skyfuryText:SetShown(not GroupAllHaveBlessing(SKYFURY_SPELL_ID))
        shamanWeaponText:SetShown(not ShamanHasWeaponEnchants())
    else
        skyfuryText:Hide()
        shamanWeaponText:Hide()
    end

    if PLAYER_CLASS == "ROGUE" then
        lethalPoisonText:SetShown(not PlayerHasLethalPoison())
        nonLethalPoisonText:SetShown(not PlayerHasNonLethalPoison())
    else
        lethalPoisonText:Hide()
        nonLethalPoisonText:Hide()
    end

    if PLAYER_CLASS == "DEATHKNIGHT" then
        dkRuneText:SetShown(not DKHasWeaponRune())
    else
        dkRuneText:Hide()
    end
end

-- ==================================================
-- Throttling (evita recalcular 20 veces seguidas)
-- ==================================================
local pendingUpdate = false
local function RequestUpdate()
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(0.10, function()
        pendingUpdate = false
        UpdateAlerts()
    end)
end

-- ==================================================
-- Eventos
-- ==================================================
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
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("TRAIT_TREE_CHANGED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

f:SetScript("OnEvent", function(_, event, unit, _, spellID)

    -- Entrar en combate
    if event == "PLAYER_REGEN_DISABLED" then
        IN_COMBAT = true
        HideAllTexts()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        IN_COMBAT = false
        RequestUpdate()
        return
    end

    -- Si estamos en combate, no hacer absolutamente nada
    if IN_COMBAT then
        return
    end

    -- Actualizar flags de grupo
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        UpdateGroupFlags()
    end

    -- Talentos
    if event == "TRAIT_CONFIG_UPDATED"
        or event == "TRAIT_TREE_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
    then
        UpdateTalentSummonElemental()
    end

    -- Rogue: aplicar venenos
    if event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and PLAYER_CLASS == "ROGUE" then
        if LETHAL_POISONS[spellID] or NON_LETHAL_POISONS[spellID] then
            RequestUpdate()
            return
        end
    end

    -- Filtrar UNIT_AURA
    if event == "UNIT_AURA" and unit ~= "player" then
        return
    end

    RequestUpdate()
end)

-- Inicial
UpdateGroupFlags()
UpdateTalentSummonElemental()
UpdateAlerts()
