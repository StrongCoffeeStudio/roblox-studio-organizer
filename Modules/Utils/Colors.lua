--[[
	Utils/Colors.lua
	Tag color palette. UI palettes for Dark/Light theme.
]]

local Colors = {}

Colors.TAG_PRESETS = {
	Color3.fromRGB(239, 68, 68),   -- Red
	Color3.fromRGB(249, 115, 22),  -- Orange
	Color3.fromRGB(234, 179, 8),   -- Yellow
	Color3.fromRGB(34, 197, 94),   -- Green
	Color3.fromRGB(59, 130, 246),  -- Blue
	Color3.fromRGB(168, 85, 247),  -- Purple
	Color3.fromRGB(236, 72, 153),  -- Pink
	Color3.fromRGB(148, 163, 184), -- Gray
}

Colors.UI_DARK = {
	BACKGROUND = Color3.fromRGB(30, 30, 30),
	BACKGROUND_LIGHT = Color3.fromRGB(40, 40, 40),
	INPUT_FIELD = Color3.fromRGB(40, 40, 40), -- same as BACKGROUND_LIGHT for dark theme
	BORDER = Color3.fromRGB(60, 60, 60),
	SCROLLBAR = Color3.fromRGB(80, 80, 80),
	TEXT = Color3.fromRGB(230, 230, 230),
	TEXT_MUTED = Color3.fromRGB(150, 150, 150),
	ACCENT = Color3.fromRGB(59, 130, 246),
	SUCCESS = Color3.fromRGB(34, 197, 94),
	WARNING = Color3.fromRGB(234, 179, 8),
	ERROR = Color3.fromRGB(239, 68, 68),
}

Colors.UI_LIGHT = {
	BACKGROUND = Color3.fromRGB(250, 250, 250),
	BACKGROUND_LIGHT = Color3.fromRGB(240, 240, 240),
	INPUT_FIELD = Color3.fromRGB(218, 218, 218), -- darker than list so search/tag name fields pop out
	BORDER = Color3.fromRGB(200, 200, 200),
	SCROLLBAR = Color3.fromRGB(180, 180, 180),
	TEXT = Color3.fromRGB(30, 30, 30),
	TEXT_MUTED = Color3.fromRGB(100, 100, 100),
	ACCENT = Color3.fromRGB(59, 130, 246),
	SUCCESS = Color3.fromRGB(34, 197, 94),
	WARNING = Color3.fromRGB(234, 179, 8),
	ERROR = Color3.fromRGB(239, 68, 68),
}

-- Active UI palette (set by applyTheme). Default dark.
Colors.UI = Colors.UI_DARK

function Colors.applyTheme(themeName)
	Colors.UI = (themeName == "Light") and Colors.UI_LIGHT or Colors.UI_DARK
end

return Colors
