std = "lua51"
max_line_length = false
exclude_files = { "dev/**", "tools/**" }

ignore = {
    "211/ADDON_NAME",  -- every file opens with the client's "local ADDON_NAME, ns = ..."
    "212",  -- unused argument (event handlers and callbacks take the client's arguments)
    "432",  -- shadowing upvalue argument
}

globals = {
    "BoundToLearn",
    "BoundToLearnDB",
    "BoundToLearn_OnAddonCompartmentClick",
    "SlashCmdList",
    "SLASH_BOUNDTOLEARN1",
    "SLASH_KBTRACK1",
}

read_globals = {
    -- Our own named frames.
    "BoundToLearnOptionsFrame",

    -- Lua as the client ships it.
    "date", "time", "strsplit", "strtrim", "tinsert", "tremove", "wipe",

    -- Client API, constants and frames.
    "C_AddOns", "C_ChatInfo", "C_CreatureInfo", "C_Item", "C_MountJournal", "C_Spell", "C_SpellBook",
    "C_Texture", "C_Timer", "C_ToyBox",
    "ClearOverrideBindings", "CLOSE", "CreateColor", "CreateFrame", "DEFAULT_CHAT_FRAME",
    "EJ_GetCurrentTier", "EJ_GetInstanceByIndex", "EJ_GetNumTiers", "EJ_SelectTier", "Enum",
    "FindBaseSpellByID", "FreeTimerTrackerTimer", "GameTooltip",
    "GetActionBarToggles", "GetActionInfo", "GetActionText", "GetActionTexture", "GetAddOnInfo",
    "GetAddOnMetadata", "GetBindingAction", "GetBindingKey", "GetBonusBarOffset", "GetBuildInfo",
    "GetChannelName", "GetCurrentBindingSet", "GetCursorPosition", "GetCVar", "GetLocale", "GetMacroBody",
    "GetMacroInfo", "GetNormalizedRealmName", "GetNumAddOns", "GetNumGroupMembers", "GetPhysicalScreenSize",
    "GetProfessionInfo", "GetProfessions", "GetRealmName", "GetTime", "GetUnitName",
    "HasAction", "HasOverrideActionBar", "hooksecurefunc", "InCombatLockdown", "InterfaceOptions_AddCategory",
    "IsAddOnLoaded", "IsAltKeyDown", "IsControlKeyDown", "IsInGroup", "IsInGuild", "IsInRaid", "IsMounted",
    "IsMouseButtonDown", "IsShiftKeyDown", "LE_PARTY_CATEGORY_INSTANCE", "Minimap", "NineSliceUtil",
    "PlayMusic", "PlaySound", "PlaySoundFile", "SaveBindings", "SendChatMessage", "SetBinding", "SetCVar",
    "SetOverrideBinding", "Settings", "SOUNDKIT", "StopMusic", "StopSound", "TimerTracker_OnEvent",
    "UIParent", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitIsPlayer", "UnitLevel", "UnitName",
}
