--[[
	Utils/QuickPresets.lua
	Quick tag presets: name + default color index (1-8) + default icon.
]]

local TagIcons = require(script.Parent.TagIcons)

local QuickPresets = {}

-- Each entry: { name, colorIndex, icon }. colorIndex is 1-8 (Colors.TAG_PRESETS). icon from TagIcons.
QuickPresets.LIST = {
	{ "UI", 5, "🖥️" },
	{ "Gameplay", 2, "🎮" },
	{ "Audio", 6, "🎵" },
	{ "Visual", 4, "🎨" },
	{ "Animation", 7, "🎬" },
	{ "TODO", 3, "📋" },
	{ "InProgress", 2, "⏱️" },
	{ "Done", 4, "✅" },
	{ "NeedsReview", 3, "🔍" },
	{ "Important", 1, "📌" },
	{ "Bug", 1, "🐛" },
	{ "Optimize", 8, "🔧" },
}

-- Ordered list of names only (for dialog chips).
QuickPresets.NAMES = {}
for _, entry in ipairs(QuickPresets.LIST) do
	table.insert(QuickPresets.NAMES, entry[1])
end

-- Default icon for a preset by name (fallback to TagIcons.DEFAULT).
function QuickPresets.getDefaultIcon(presetName)
	for _, entry in ipairs(QuickPresets.LIST) do
		if entry[1] == presetName and entry[3] then
			return entry[3]
		end
	end
	return TagIcons.DEFAULT
end

return QuickPresets
