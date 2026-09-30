local addonName, addon = ...
addon.L = addon.L or {}
local L = addon.L

SimpleClassRemindersDB = type(SimpleClassRemindersDB) == "table" and SimpleClassRemindersDB or {}
local DB = SimpleClassRemindersDB
DB.greatVault = type(DB.greatVault) == "table" and DB.greatVault or {}

-- ==================================================
-- Cache / Constantes
-- ==================================================
local _, PLAYER_CLASS = UnitClass("player")

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

local PALADIN_RITE_SPELL_NAMES = {
    ["Rite of Sanctification"] = true,
    ["Rite of Adjuration"] = true,
    ["Rito de santificación"] = true,
    ["Rito de adjuración"] = true,
    ["Rito de ruego"] = true,
}

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

local function GetLocalizedSpellName(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name and spellInfo.name ~= "" then
            return spellInfo.name
        end
    end

    local spellName = GetSpellInfo(spellID)
    if type(spellName) == "string" and spellName ~= "" then
        return spellName
    end

    return nil
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
local function UnitHasAuraBySpellNames(unit, spellNames)
    if not spellNames then return false end

    if AuraUtil and AuraUtil.FindAuraByName then
        for spellName in pairs(spellNames) do
            if AuraUtil.FindAuraByName(spellName, unit, "HELPFUL") then
                return true
            end
        end
    end

    return false
end

local function UnitHasAuraBySpellId(unit, spellID)
    local spellName = GetLocalizedSpellName(spellID)

    -- API directa actual (Retail 12.x); evita depender de wrappers antiguos de AuraUtil.
    if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
        if C_UnitAuras.GetUnitAuraBySpellID(unit, spellID) ~= nil then
            return true
        end
    end

    -- Via rapida para player
    if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        if C_UnitAuras.GetPlayerAuraBySpellID(spellID) ~= nil then
            return true
        end
    end

    -- API segura (no leer campos de aura en tablas potencialmente "secret")
    if AuraUtil and AuraUtil.FindAuraBySpellId then
        if AuraUtil.FindAuraBySpellId(spellID, unit, "HELPFUL") ~= nil then
            return true
        end
    end

    if spellName and AuraUtil and AuraUtil.FindAuraByName then
        if AuraUtil.FindAuraByName(spellName, unit, "HELPFUL") ~= nil then
            return true
        end
    end

    return false
end

local function GroupHasAura(spellID)
    if UnitHasAuraBySpellId("player", spellID) then
        return true
    end
    if not IsInGroup() then
        return false
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
            and UnitHasAuraBySpellId(unit, spellID)
        then
            return true
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
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for poisonSpellID in pairs(poisonSpellIDs) do
            if C_UnitAuras.GetPlayerAuraBySpellID(poisonSpellID) ~= nil then
                return true
            end
        end
        return false
    end

    return false
end


local function PlayerHasLethalPoison()
    return PlayerHasPoison(LETHAL_POISONS)
end

local function PlayerHasNonLethalPoison()
    return PlayerHasPoison(NON_LETHAL_POISONS)
end

local function PlayerHasActiveTalentSpellNames(spellNames)
    if not spellNames then return false end

    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID) then
        return false
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        return false
    end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then
        return false
    end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            if nodeInfo and nodeInfo.activeEntry then
                local entryInfo = C_Traits.GetEntryInfo(configID, nodeInfo.activeEntry.entryID)
                if entryInfo and entryInfo.definitionID then
                    local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    local spellName = defInfo and defInfo.spellID and GetLocalizedSpellName(defInfo.spellID)
                    if spellName and spellNames[spellName] then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function PaladinHasRiteImbue()
    if PLAYER_CLASS ~= "PALADIN" then
        return true
    end

    if not PlayerHasActiveTalentSpellNames(PALADIN_RITE_SPELL_NAMES) then
        return true
    end

    if UnitHasAuraBySpellNames("player", PALADIN_RITE_SPELL_NAMES) then
        return true
    end

    local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
    return hasMH or hasOH
end

local function ShamanHasWeaponEnchants()
    local hasMH, _, _, hasOH = GetWeaponEnchantInfo()
    -- Si no hay ninguno, no cumple
    if not hasMH and not hasOH then
        return false
    end

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
    if not itemLink then return true end
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

local paladinRiteText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
paladinRiteText:SetPoint("TOP", anchor, "TOP", 0, -120)
paladinRiteText:SetText(L.NO_PALADIN_RITE)
StyleText(paladinRiteText)
paladinRiteText:Hide()

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
    paladinRiteText,
    lethalPoisonText,
    nonLethalPoisonText,
    arcaneIntellectText,
    skyfuryText,
    shamanWeaponText,
}

local TALENT_SUMMARY_DURATION = 3
local WEEK_SECONDS = 7 * 24 * 60 * 60
local talentSummaryHideTimer = nil
local greatVaultLoginNoticePending = false
local greatVaultLoginNoticeShown = false
local greatVaultInitialized = false
local greatVaultCheckGeneration = 0

local talentSummaryText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
talentSummaryText:SetPoint("TOP", anchor, "TOP", 0, -210)
talentSummaryText:SetWidth(900)
talentSummaryText:SetJustifyH("CENTER")
talentSummaryText:SetJustifyV("TOP")
StyleText(talentSummaryText)
talentSummaryText:Hide()

local greatVaultLoginText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
greatVaultLoginText:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
greatVaultLoginText:SetWidth(1000)
greatVaultLoginText:SetJustifyH("CENTER")
greatVaultLoginText:SetJustifyV("MIDDLE")
StyleText(greatVaultLoginText)
greatVaultLoginText:Hide()

local function HideAllTexts()
    for _, t in ipairs(ALL_TEXTS) do
        t:Hide()
    end
end

local function CancelTalentSummaryTimer()
    if talentSummaryHideTimer then
        talentSummaryHideTimer:Cancel()
        talentSummaryHideTimer = nil
    end
end

local function GetSelectedSavedLoadoutName()
    local selectionID

    if PlayerSpellsFrame
        and PlayerSpellsFrame.TalentsFrame
        and PlayerSpellsFrame.TalentsFrame.LoadoutDropDown
        and PlayerSpellsFrame.TalentsFrame.LoadoutDropDown.GetSelectionID
    then
        selectionID = PlayerSpellsFrame.TalentsFrame.LoadoutDropDown:GetSelectionID()
    end

    if selectionID then
        local configInfo = C_Traits.GetConfigInfo(selectionID)
        if configInfo and configInfo.name and configInfo.name ~= "" then
            return configInfo.name
        end
    end

    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)

    if C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID and specID then
        local savedConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specID)
        if savedConfigID then
            local configInfo = C_Traits.GetConfigInfo(savedConfigID)
            if configInfo and configInfo.name and configInfo.name ~= "" then
                return configInfo.name
            end
        end
    end

    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local activeConfigID = C_ClassTalents.GetActiveConfigID()
        if activeConfigID then
            local configInfo = C_Traits.GetConfigInfo(activeConfigID)
            if configInfo and configInfo.name and configInfo.name ~= "" then
                return configInfo.name
            end
        end
    end

    return nil
end

local function GetTalentSummaryLines()
    local lines = {}
    local loadoutName = GetSelectedSavedLoadoutName()

    if not loadoutName and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local configID = C_ClassTalents.GetActiveConfigID()
        if configID then
            local configInfo = C_Traits.GetConfigInfo(configID)
            loadoutName = configInfo and configInfo.name
        end
    end

    if loadoutName and loadoutName ~= "" then
        lines[#lines + 1] = L.TALENT_SUMMARY_LOADOUT:format(loadoutName)
    else
        lines[#lines + 1] = L.TALENT_SUMMARY_LOADOUT:format("Unknown")
    end

    local specIndex = GetSpecialization()
    if specIndex then
        local _, specName = GetSpecializationInfo(specIndex)
        if specName and specName ~= "" then
            lines[#lines + 1] = L.TALENT_SUMMARY_SPEC:format(specName)
        else
            lines[#lines + 1] = L.TALENT_SUMMARY_SPEC:format("Unknown")
        end
    else
        lines[#lines + 1] = L.TALENT_SUMMARY_SPEC:format("Unknown")
    end

    return table.concat(lines, "\n")
end

local function ShowTalentSummary(title)
    local summaryLines = GetTalentSummaryLines()
    CancelTalentSummaryTimer()
    if summaryLines and summaryLines ~= "" then
        if title and title ~= "" then
            talentSummaryText:SetText(title .. "\n" .. summaryLines)
        else
            talentSummaryText:SetText(summaryLines)
        end
    else
        talentSummaryText:SetText(title or "")
    end
    talentSummaryText:Show()
    talentSummaryHideTimer = C_Timer.NewTimer(TALENT_SUMMARY_DURATION, function()
        talentSummaryText:Hide()
        talentSummaryHideTimer = nil
    end)
end

local function GetServerTimestamp()
    if type(GetServerTime) == "function" then
        local ok, timestamp = pcall(GetServerTime)
        if ok and type(timestamp) == "number" and timestamp > 0 then
            return timestamp
        end
    end

    return time()
end

local function GetWeeklyResetStartTimestamp()
    if C_DateAndTime and type(C_DateAndTime.GetWeeklyResetStartTime) == "function" then
        local ok, timestamp = pcall(C_DateAndTime.GetWeeklyResetStartTime)
        if ok and type(timestamp) == "number" and timestamp > 0 then
            return math.floor(timestamp)
        end
    end

    return nil
end

local function GetNextWeeklyResetTimestamp()
    if not (C_DateAndTime and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function") then
        return nil
    end

    local ok, seconds = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
    if not ok or type(seconds) ~= "number" or seconds < 0 or seconds > WEEK_SECONDS + 3600 then
        return nil
    end

    return GetServerTimestamp() + math.floor(seconds)
end

local function ResetGreatVaultWeeklyState(state, weekStart, resetAt)
    state.initialized = true
    state.checked = false
    state.hasRewards = false
    state.weekStart = weekStart
    state.resetAt = resetAt
    greatVaultLoginNoticePending = true
    greatVaultLoginNoticeShown = false
    greatVaultLoginText:Hide()
end

local function RefreshGreatVaultWeeklyState()
    local state = DB.greatVault
    local weekStart = GetWeeklyResetStartTimestamp()
    local nextResetAt = GetNextWeeklyResetTimestamp()
    local now = GetServerTimestamp()

    if weekStart then
        if state.weekStart ~= weekStart then
            ResetGreatVaultWeeklyState(state, weekStart, nextResetAt)
        else
            state.initialized = true
            state.resetAt = nextResetAt or state.resetAt
        end
    elseif type(nextResetAt) == "number" then
        if state.initialized ~= true or (type(state.resetAt) == "number" and now >= state.resetAt) then
            ResetGreatVaultWeeklyState(state, nil, nextResetAt)
        else
            state.resetAt = nextResetAt
        end
    elseif state.initialized ~= true then
        ResetGreatVaultWeeklyState(state, nil, nil)
    elseif type(state.resetAt) == "number" and now >= state.resetAt then
        ResetGreatVaultWeeklyState(state, nil, nil)
    end

    return state
end

local function ShowGreatVaultLoginNotice()
    greatVaultLoginText:SetAlpha(1)
    greatVaultLoginText:SetText(L.GREAT_VAULT_AVAILABLE or WEEKLY_REWARDS_UNCLAIMED_TITLE or "You have unclaimed Great Vault rewards!")
    greatVaultLoginText:Show()
end

local function ApplyCachedGreatVaultState()
    local state = RefreshGreatVaultWeeklyState()
    if state.checked ~= true then
        return false
    end

    greatVaultLoginNoticePending = false

    if state.hasRewards == true and not InCombatLockdown() then
        ShowGreatVaultLoginNotice()
        greatVaultLoginNoticeShown = true
    else
        greatVaultLoginText:Hide()
        greatVaultLoginNoticeShown = false
    end

    return true
end

local function CheckGreatVaultRewards(finalizeFalseResult)
    if ApplyCachedGreatVaultState() then
        return
    end

    if not greatVaultLoginNoticePending or InCombatLockdown() then
        return
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.HasAvailableRewards) == "function") then
        return
    end

    local ok, hasRewards = pcall(C_WeeklyRewards.HasAvailableRewards)
    if not ok or type(hasRewards) ~= "boolean" then
        return
    end

    if hasRewards or finalizeFalseResult then
        local state = RefreshGreatVaultWeeklyState()
        state.checked = true
        state.hasRewards = hasRewards
        ApplyCachedGreatVaultState()
    end
end

local function ScheduleGreatVaultChecks()
    greatVaultCheckGeneration = greatVaultCheckGeneration + 1
    local generation = greatVaultCheckGeneration

    for index, delay in ipairs({ 2, 5, 10 }) do
        local finalizeFalseResult = index == 3
        C_Timer.After(delay, function()
            if generation == greatVaultCheckGeneration then
                CheckGreatVaultRewards(finalizeFalseResult)
            end
        end)
    end
end

local function InitializeGreatVaultLoginNotice()
    if greatVaultInitialized then
        return
    end
    greatVaultInitialized = true

    local state = RefreshGreatVaultWeeklyState()
    if state.checked == true then
        ApplyCachedGreatVaultState()
    else
        greatVaultLoginNoticePending = true
        ScheduleGreatVaultChecks()
    end

    if type(state.resetAt) == "number" then
        local secondsUntilReset = state.resetAt - GetServerTimestamp()
        if secondsUntilReset > 0 and secondsUntilReset <= WEEK_SECONDS + 3600 then
            C_Timer.After(secondsUntilReset + 5, function()
                local refreshedState = RefreshGreatVaultWeeklyState()
                if refreshedState.checked ~= true then
                    greatVaultLoginNoticePending = true
                    ScheduleGreatVaultChecks()
                end
            end)
        end
    end
end

local function UpdateGreatVaultLoginNotice()
    if InCombatLockdown() then
        greatVaultLoginText:Hide()
        return
    end

    local state = RefreshGreatVaultWeeklyState()
    if state.checked == true then
        ApplyCachedGreatVaultState()
    elseif greatVaultLoginNoticePending then
        CheckGreatVaultRewards(true)
    end
end

-- Ocultar el aviso en el mismo momento en que se reclama una recompensa.
if C_WeeklyRewards and C_WeeklyRewards.ClaimReward then
    hooksecurefunc(C_WeeklyRewards, "ClaimReward", function()
        local state = RefreshGreatVaultWeeklyState()
        state.checked = true
        state.hasRewards = false
        greatVaultLoginText:Hide()
        greatVaultLoginNoticeShown = false
        greatVaultLoginNoticePending = false
    end)
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
        devotionText:SetShown(not GroupHasAura(DEVOTION_AURA_SPELL_ID))
        paladinRiteText:SetShown(not PaladinHasRiteImbue())
    else
        devotionText:Hide()
        paladinRiteText:Hide()
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
-- Group Finder: anuncio al unirse
-- ==================================================
local lfgListingCache = {}
local pendingLFGJoinSearchResultID = nil
local lfgJoinAlreadyAnnounced = false

local LFG_TERMINAL_STATUS = {
    cancelled = true,
    declined = true,
    declined_full = true,
    declined_delisted = true,
    timedout = true,
    invitedeclined = true,
}

local function IsSecretLFGValue(value)
    if type(issecretvalue) ~= "function" then
        return false
    end
    local ok, isSecret = pcall(issecretvalue, value)
    return not ok or isSecret == true
end

local function SafeLFGValue(value, expectedType)
    if IsSecretLFGValue(value) or type(value) ~= expectedType then
        return nil
    end
    if expectedType == "string" and value == "" then
        return nil
    end
    return value
end

local function SafeLFGField(container, key, expectedType)
    if not SafeLFGValue(container, "table") then
        return nil
    end
    local ok, value = pcall(function()
        return container[key]
    end)
    return ok and SafeLFGValue(value, expectedType) or nil
end

local function GetLFGDifficulty(activityInfo)
    local difficultyID = SafeLFGField(activityInfo, "difficultyID", "number")
    if difficultyID and type(GetDifficultyInfo) == "function" then
        local ok, difficultyName = pcall(GetDifficultyInfo, difficultyID)
        difficultyName = ok and SafeLFGValue(difficultyName, "string") or nil
        if difficultyName then
            return difficultyName
        end
    end

    if SafeLFGField(activityInfo, "isMythicPlusActivity", "boolean") == true then
        return SafeLFGValue(_G.CHALLENGE_MODE, "string") or "Mythic+"
    elseif SafeLFGField(activityInfo, "isMythicActivity", "boolean") == true then
        return SafeLFGValue(_G.PLAYER_DIFFICULTY6, "string") or "Mythic"
    elseif SafeLFGField(activityInfo, "isHeroicActivity", "boolean") == true then
        return SafeLFGValue(_G.PLAYER_DIFFICULTY2, "string") or "Heroic"
    elseif SafeLFGField(activityInfo, "isNormalActivity", "boolean") == true then
        return SafeLFGValue(_G.PLAYER_DIFFICULTY1, "string") or "Normal"
    end

    return nil
end

local function BuildLFGJoinAnnouncement(searchResultID, fallbackGroupName)
    searchResultID = SafeLFGValue(searchResultID, "number")
    if not searchResultID or type(C_LFGList) ~= "table" then
        return nil
    end

    local info
    if type(C_LFGList.GetSearchResultInfo) == "function" then
        local ok, value = pcall(C_LFGList.GetSearchResultInfo, searchResultID)
        info = ok and SafeLFGValue(value, "table") or nil
    end
    if not info then
        return nil
    end

    local data = {
        listingName = SafeLFGField(info, "name", "string")
            or SafeLFGValue(fallbackGroupName, "string"),
    }
    local activityIDs = SafeLFGField(info, "activityIDs", "table")
    data.activityID = activityIDs and SafeLFGField(activityIDs, 1, "number")
        or SafeLFGField(info, "activityID", "number")
    if not data.activityID then
        return data
    end

    local questID = SafeLFGField(info, "questID", "number")
    local isWarMode = SafeLFGField(info, "isWarMode", "boolean")
    local activityInfo
    if type(C_LFGList.GetActivityInfoTable) == "function" then
        local ok, value = pcall(C_LFGList.GetActivityInfoTable, data.activityID, questID, isWarMode)
        activityInfo = ok and SafeLFGValue(value, "table") or nil
    end

    if type(C_LFGList.GetActivityFullName) == "function" then
        local ok, fullName = pcall(C_LFGList.GetActivityFullName, data.activityID, questID, isWarMode)
        data.activityName = ok and SafeLFGValue(fullName, "string") or nil
    end
    if activityInfo then
        data.activityName = data.activityName
            or SafeLFGField(activityInfo, "fullName", "string")
            or SafeLFGField(activityInfo, "shortName", "string")
        data.difficultyName = GetLFGDifficulty(activityInfo)
        data.isMythicPlus = SafeLFGField(activityInfo, "isMythicPlusActivity", "boolean") == true
    end

    if data.isMythicPlus and type(C_LFGList.GetKeystoneForActivity) == "function" then
        local ok, level = pcall(C_LFGList.GetKeystoneForActivity, data.activityID)
        level = ok and SafeLFGValue(level, "number") or nil
        if level and level > 0 then
            data.keystoneLevel = math.floor(level)
        end
    end
    if data.isMythicPlus and not data.keystoneLevel and data.listingName then
        local parsedLevel = data.listingName:match("%+(%d+)%f[%D]")
        parsedLevel = parsedLevel and tonumber(parsedLevel) or nil
        if parsedLevel and parsedLevel > 0 then
            data.keystoneLevel = math.floor(parsedLevel)
        end
    end

    return data
end

local function CacheLFGListing(searchResultID, fallbackGroupName)
    searchResultID = SafeLFGValue(searchResultID, "number")
    if not searchResultID then return nil end

    local cached = lfgListingCache[searchResultID] or {}
    local fresh = BuildLFGJoinAnnouncement(searchResultID, fallbackGroupName)
    if fresh then
        for key, value in pairs(fresh) do
            cached[key] = value
        end
        lfgListingCache[searchResultID] = cached
    end
    return lfgListingCache[searchResultID]
end

local function AnnounceLFGJoin(data)
    if type(data) ~= "table" then return false end

    local activityName = SafeLFGValue(data.activityName, "string")
    if not activityName then return false end

    local difficultyName = SafeLFGValue(data.difficultyName, "string")
    if difficultyName then
        local escapedDifficulty = difficultyName:gsub("(%W)", "%%%1")
        activityName = activityName:gsub("%s*%(" .. escapedDifficulty .. "%)%s*$", "")
    end

    local keystoneLevel = SafeLFGValue(data.keystoneLevel, "number")
    if keystoneLevel and keystoneLevel > 0 then
        local keyText = "+" .. tostring(math.floor(keystoneLevel))
        difficultyName = difficultyName and (difficultyName .. " " .. keyText) or keyText
    end

    if difficultyName then
        print(string.format(L.GF_ACTIVITY_DIFFICULTY
            or "[SimpleClassReminders] %s | %s", activityName, difficultyName))
    else
        print(string.format(L.GF_ACTIVITY_ONLY
            or "[SimpleClassReminders] %s", activityName))
    end
    return true
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
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("UNIT_FLAGS")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("TRAIT_TREE_CHANGED")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterEvent("READY_CHECK")
f:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
f:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
f:RegisterEvent("LFG_LIST_JOINED_GROUP")
f:RegisterEvent("WEEKLY_REWARDS_UPDATE")

f:SetScript("OnEvent", function(_, event, ...)
    local arg1, _, arg3 = ...

    if event == "READY_CHECK" then
        if IsInRaid() then
            ShowTalentSummary(L.TALENT_SUMMARY_READY)
        end
        RequestUpdate()
        return
    end

    if event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        local searchResultID, newStatus, oldStatus, groupName = ...
        searchResultID = SafeLFGValue(searchResultID, "number")
        newStatus = SafeLFGValue(newStatus, "string")

        if searchResultID and (newStatus == "applied" or newStatus == "invited" or newStatus == "inviteaccepted") then
            CacheLFGListing(searchResultID, groupName)
        end
        if searchResultID and newStatus == "invited" then
            lfgJoinAlreadyAnnounced = false
        elseif searchResultID and newStatus == "inviteaccepted" then
            pendingLFGJoinSearchResultID = searchResultID
            lfgJoinAlreadyAnnounced = false
        elseif searchResultID and (LFG_TERMINAL_STATUS[newStatus]
            or (newStatus == "none" and pendingLFGJoinSearchResultID ~= searchResultID)) then
            lfgListingCache[searchResultID] = nil
            if pendingLFGJoinSearchResultID == searchResultID then
                pendingLFGJoinSearchResultID = nil
                lfgJoinAlreadyAnnounced = false
            end
        end
        return
    end

    if event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        local searchResultID = ...
        searchResultID = SafeLFGValue(searchResultID, "number")
        if searchResultID and lfgListingCache[searchResultID] then
            CacheLFGListing(searchResultID)
        end
        return
    end

    if event == "LFG_LIST_JOINED_GROUP" then
        local searchResultID, groupName = ...
        searchResultID = SafeLFGValue(searchResultID, "number")
        if searchResultID then
            local data = CacheLFGListing(searchResultID, groupName)
                or lfgListingCache[searchResultID]
            if not lfgJoinAlreadyAnnounced and AnnounceLFGJoin(data) then
                lfgJoinAlreadyAnnounced = true
            end
            lfgListingCache[searchResultID] = nil
            if pendingLFGJoinSearchResultID == searchResultID then
                pendingLFGJoinSearchResultID = nil
            end
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" and IsInGroup()
        and pendingLFGJoinSearchResultID and not lfgJoinAlreadyAnnounced then
        local data = lfgListingCache[pendingLFGJoinSearchResultID]
        if AnnounceLFGJoin(data) then
            lfgJoinAlreadyAnnounced = true
            lfgListingCache[pendingLFGJoinSearchResultID] = nil
            pendingLFGJoinSearchResultID = nil
        end
    end

    if event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUI = ...
        InitializeGreatVaultLoginNotice()

        if not isInitialLogin and not isReloadingUI then
            local inInstance, instanceType = IsInInstance()
            if inInstance and (instanceType == "party" or instanceType == "raid") then
                ShowTalentSummary()
            end
        end
    end

    if event == "WEEKLY_REWARDS_UPDATE" then
        UpdateGreatVaultLoginNotice()
    end

	if event == "PLAYER_REGEN_ENABLED" then
	    UpdateGreatVaultLoginNotice()
	    RequestUpdate()
	    return
	end

	if event == "PLAYER_REGEN_DISABLED" then
	    greatVaultLoginText:Hide()
	    HideAllTexts()
	    return
	end

	if InCombatLockdown() then
	    HideAllTexts()
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

	-- Rogue: aplicar venenos manualmente
	if event == "UNIT_SPELLCAST_SUCCEEDED"
	    and arg1 == "player"
	    and PLAYER_CLASS == "ROGUE"
	    and (LETHAL_POISONS[arg3] or NON_LETHAL_POISONS[arg3])
	then
	    RequestUpdate()
	    return
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED"
	    and arg1 == "player"
	    and PLAYER_CLASS == "PALADIN"
	then
	    local spellName = GetLocalizedSpellName(arg3)
	    if spellName and PALADIN_RITE_SPELL_NAMES[spellName] then
	        RequestUpdate()
	        return
	    end
	end

	-- Rogue: cambio de arma / inventory
	if (event == "UNIT_INVENTORY_CHANGED" and arg1 == "player")
	   or event == "PLAYER_EQUIPMENT_CHANGED"
	then
	    if PLAYER_CLASS == "ROGUE" then
	        RequestUpdate()
	        return
	    end
	end


    -- Filtrar UNIT_AURA: solo player o miembros de grupo cuando aplica
    if event == "UNIT_AURA" then
        local tracksGroupBuffs = (PLAYER_CLASS == "PRIEST"
            or PLAYER_CLASS == "DRUID"
            or PLAYER_CLASS == "EVOKER"
            or PLAYER_CLASS == "MAGE"
            or PLAYER_CLASS == "PALADIN"
            or PLAYER_CLASS == "SHAMAN")

        if arg1 ~= "player" then
            local isGroupUnit = arg1 and (arg1:match("^party") or arg1:match("^raid"))
            if not tracksGroupBuffs or not isGroupUnit then
                return
            end
        end
    end

    RequestUpdate()
end)

-- Inicial
UpdateGroupFlags()
UpdateTalentSummonElemental()
UpdateAlerts()








