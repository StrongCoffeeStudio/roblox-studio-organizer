--[[
	Utils/SettingsKeys.lua
	Plugin setting keys and defaults for Studio Organizer (global user preferences).
]]

local SettingsKeys = {}

local PREFIX = "StudioOrganizer_Settings_"

SettingsKeys.THEME = PREFIX .. "Theme"
SettingsKeys.AUTO_SAVE = PREFIX .. "AutoSave"
SettingsKeys.SEARCH_DELAY_MS = PREFIX .. "SearchDelayMs"
SettingsKeys.COLOR_CODING = PREFIX .. "ColorCoding"
SettingsKeys.DRAG_DROP = PREFIX .. "DragDrop"

SettingsKeys.DEFAULT_THEME = "Dark"
SettingsKeys.DEFAULT_AUTO_SAVE = true
SettingsKeys.DEFAULT_SEARCH_DELAY_MS = 300
SettingsKeys.DEFAULT_COLOR_CODING = true
SettingsKeys.DEFAULT_DRAG_DROP = true

SettingsKeys.SEARCH_DELAY_MIN = 100
SettingsKeys.SEARCH_DELAY_MAX = 500

return SettingsKeys
