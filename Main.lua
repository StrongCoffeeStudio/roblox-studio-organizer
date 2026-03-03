--[[
	Studio Organizer
	Entry point. Requires plugin global (Roblox injects for plugin scripts).
]]

local plugin = plugin
if not plugin then
	warn("[Studio Organizer] Not running as a plugin.")
	return
end

local DockWidgetPluginGuiInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false,
	false,
	320,
	400,
	320,
	400
)

local widget = plugin:CreateDockWidgetPluginGuiAsync("StudioOrganizer_Main", DockWidgetPluginGuiInfo)
widget.Name = "StudioOrganizer"
widget.Title = "Studio Organizer"

local Modules = script:WaitForChild("Modules")
local TagManager = require(Modules.Core.TagManager)
local LicenseManager = require(Modules.Core.LicenseManager)
local SearchEngine = require(Modules.Core.SearchEngine)
local MainPanel = require(Modules.UI.MainPanel)

local tagManager = TagManager.new(plugin)
local licenseManager = LicenseManager.new(plugin)
local searchEngine = SearchEngine.new(tagManager)

local mainPanel = MainPanel.new(widget, tagManager, searchEngine)
mainPanel:build()

widget.Enabled = true
