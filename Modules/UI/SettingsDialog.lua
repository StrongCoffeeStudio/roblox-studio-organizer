--[[
	UI/SettingsDialog.lua
	Settings dialog: Theme, Auto-save, Search delay, Color-coding, Drag-drop, About/version.
	Close via Close button or Esc. Saves to plugin settings on change.
]]

local Colors = require(script.Parent.Parent.Utils.Colors)
local SettingsKeys = require(script.Parent.Parent.Utils.SettingsKeys)

local PADDING = 16
local ROW_H = 28
local GAP = 8
local DIALOG_W = 320
local Z_OVERLAY = 99
local Z_BACKDROP = 100
local Z_DIALOG = 101
local Z_CONTENT = 102  -- Explicit ZIndex for dialog content so it draws on top in PluginGui
local TOOLTIP_DELAY_SEC = 1.5

local VERSION_STRING = "Studio Organizer 1.0"

local function getBool(plugin, key, default)
	local v = plugin:GetSetting(key)
	if v == nil then return default end
	return v == "true" or v == true
end

local function setBool(plugin, key, value)
	plugin:SetSetting(key, value and "true" or "false")
end

local function getNumber(plugin, key, default, minVal, maxVal)
	local v = plugin:GetSetting(key)
	if v == nil then return default end
	local n = tonumber(v)
	if n == nil then return default end
	if minVal and n < minVal then return minVal end
	if maxVal and n > maxVal then return maxVal end
	return n
end

-- Tooltip text for each setting (shown on hover)
local SETTING_TOOLTIPS = {
	Theme = "Switch between dark and light appearance.",
	AutoSave = "When on, tag changes are saved automatically.",
	SearchDelay = "Delay in ms before search runs after you type (100–500).",
	ColorCoding = "Show tag colors on chips and in the object list.",
	DragDrop = "Allow dragging tags to objects and objects to tags.",
	About = VERSION_STRING,
}

local function createSettingsDialog(parentFrame, plugin, onClose, onSettingChanged)
	if not plugin then return end
	onSettingChanged = onSettingChanged or function() end

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = Z_OVERLAY
	overlay.Parent = parentFrame

	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Position = UDim2.new(0, 0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.ZIndex = Z_BACKDROP
	backdrop.Parent = overlay

	local UserInputService = game:GetService("UserInputService")
	local escConn

	local function saveAndClose()
		if escConn then escConn:Disconnect() end
		overlay:Destroy()
		if onClose then onClose() end
	end

	backdrop.Activated:Connect(saveAndClose)

	escConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			escConn:Disconnect()
			saveAndClose()
		end
	end)

	local contentH = PADDING * 2 + ROW_H * 7 + GAP * 6 + 36
	local dialog = Instance.new("Frame")
	dialog.Size = UDim2.new(0, DIALOG_W, 0, contentH)
	dialog.Position = UDim2.new(0.5, -DIALOG_W / 2, 0.5, -contentH / 2)
	dialog.BackgroundColor3 = Colors.UI.BACKGROUND
	dialog.BorderSizePixel = 0
	dialog.ZIndex = Z_DIALOG
	dialog.Parent = overlay
	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Color = Colors.UI.BORDER
	dialogStroke.Parent = dialog
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = dialog
	end

	-- Centered content container (AutomaticSize XY so it centers in the dialog)
	local contentContainer = Instance.new("Frame")
	contentContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	contentContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
	contentContainer.Size = UDim2.new(0, 0, 0, 0)
	contentContainer.AutomaticSize = Enum.AutomaticSize.XY
	contentContainer.BackgroundTransparency = 1
	contentContainer.ZIndex = Z_CONTENT
	contentContainer.Parent = dialog

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, GAP)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = contentContainer

	-- Tooltip: single Frame with TextLabel, shown after delay so it doesn't block the view
	local tooltip = Instance.new("Frame")
	tooltip.Size = UDim2.new(0, 200, 0, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.Y
	tooltip.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = Z_CONTENT + 10
	tooltip.ClipsDescendants = false
	tooltip.Parent = overlay
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = tooltip end
	do
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 6)
		p.PaddingRight = UDim.new(0, 6)
		p.PaddingTop = UDim.new(0, 4)
		p.PaddingBottom = UDim.new(0, 4)
		p.Parent = tooltip
	end
	local tooltipLabel = Instance.new("TextLabel")
	tooltipLabel.Size = UDim2.new(1, 0, 0, 0)
	tooltipLabel.AutomaticSize = Enum.AutomaticSize.Y
	tooltipLabel.Position = UDim2.new(0, 0, 0, 0)
	tooltipLabel.BackgroundTransparency = 1
	tooltipLabel.TextColor3 = Color3.new(1, 1, 1)
	tooltipLabel.TextSize = 11
	tooltipLabel.TextWrapped = true
	tooltipLabel.TextXAlignment = Enum.TextXAlignment.Left
	tooltipLabel.ZIndex = Z_CONTENT + 11
	tooltipLabel.Parent = tooltip
	local tooltipHoverId = 0
	local function showTooltip(anchor, text)
		tooltipLabel.Text = text or ""
		tooltip.Visible = #(text or "") > 0
		if tooltip.Visible and anchor and overlay.AbsolutePosition and anchor.AbsolutePosition then
			local ox, oy = overlay.AbsolutePosition.X, overlay.AbsolutePosition.Y
			local ax, ay = anchor.AbsolutePosition.X, anchor.AbsolutePosition.Y
			tooltip.Position = UDim2.new(0, ax - ox, 0, ay - oy - 28)
		end
	end
	local function hideTooltip()
		tooltip.Visible = false
	end
	local function bindTooltip(row, key)
		local text = SETTING_TOOLTIPS[key]
		if not text then return end
		row.MouseEnter:Connect(function()
			tooltipHoverId = tooltipHoverId + 1
			local myId = tooltipHoverId
			task.delay(TOOLTIP_DELAY_SEC, function()
				if myId == tooltipHoverId then
					showTooltip(row, text)
				end
			end)
		end)
		row.MouseLeave:Connect(function()
			tooltipHoverId = tooltipHoverId + 1
			hideTooltip()
		end)
	end

	local y = PADDING

	-- Theme
	local themeRow = Instance.new("Frame")
	themeRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	themeRow.BackgroundTransparency = 1
	themeRow.LayoutOrder = 1
	themeRow.ZIndex = Z_CONTENT
	themeRow.Parent = contentContainer
	bindTooltip(themeRow, "Theme")
	y = y + ROW_H + GAP
	local themeLabel = Instance.new("TextLabel")
	themeLabel.Size = UDim2.new(0, 100, 1, 0)
	themeLabel.BackgroundTransparency = 1
	themeLabel.Text = "Theme"
	themeLabel.TextColor3 = Colors.UI.TEXT
	themeLabel.TextSize = 12
	themeLabel.TextXAlignment = Enum.TextXAlignment.Left
	themeLabel.ZIndex = Z_CONTENT
	themeLabel.Parent = themeRow
	local currentTheme = plugin:GetSetting(SettingsKeys.THEME) or SettingsKeys.DEFAULT_THEME
	local themeDarkBtn = Instance.new("TextButton")
	themeDarkBtn.Size = UDim2.new(0, 60, 0, 24)
	themeDarkBtn.Position = UDim2.new(0, 110, 0, 2)
	themeDarkBtn.BackgroundColor3 = currentTheme == "Dark" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
	themeDarkBtn.BorderSizePixel = 0
	themeDarkBtn.Text = "Dark"
	themeDarkBtn.TextColor3 = Colors.UI.TEXT
	themeDarkBtn.TextSize = 12
	themeDarkBtn.ZIndex = Z_CONTENT
	themeDarkBtn.Parent = themeRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = themeDarkBtn end
	local themeLightBtn = Instance.new("TextButton")
	themeLightBtn.Size = UDim2.new(0, 60, 0, 24)
	themeLightBtn.Position = UDim2.new(0, 176, 0, 2)
	themeLightBtn.BackgroundColor3 = currentTheme == "Light" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
	themeLightBtn.BorderSizePixel = 0
	themeLightBtn.Text = "Light"
	themeLightBtn.TextColor3 = Colors.UI.TEXT
	themeLightBtn.TextSize = 12
	themeLightBtn.ZIndex = Z_CONTENT
	themeLightBtn.Parent = themeRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = themeLightBtn end
	local function updateThemeButtons()
		local t = plugin:GetSetting(SettingsKeys.THEME) or SettingsKeys.DEFAULT_THEME
		themeDarkBtn.BackgroundColor3 = t == "Dark" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
		themeLightBtn.BackgroundColor3 = t == "Light" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
	end

	-- Auto-save
	local autoSaveRow = Instance.new("Frame")
	autoSaveRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	autoSaveRow.BackgroundTransparency = 1
	autoSaveRow.LayoutOrder = 2
	autoSaveRow.ZIndex = Z_CONTENT
	autoSaveRow.Parent = contentContainer
	bindTooltip(autoSaveRow, "AutoSave")
	y = y + ROW_H + GAP
	local autoSaveLabel = Instance.new("TextLabel")
	autoSaveLabel.Size = UDim2.new(0, 140, 1, 0)
	autoSaveLabel.BackgroundTransparency = 1
	autoSaveLabel.Text = "Auto-save"
	autoSaveLabel.TextColor3 = Colors.UI.TEXT
	autoSaveLabel.TextSize = 12
	autoSaveLabel.TextXAlignment = Enum.TextXAlignment.Left
	autoSaveLabel.ZIndex = Z_CONTENT
	autoSaveLabel.Parent = autoSaveRow
	local autoSaveOn = getBool(plugin, SettingsKeys.AUTO_SAVE, SettingsKeys.DEFAULT_AUTO_SAVE)
	local autoSaveCheck = Instance.new("TextButton")
	autoSaveCheck.Size = UDim2.new(0, 24, 0, 24)
	autoSaveCheck.Position = UDim2.new(0, 150, 0, 2)
	autoSaveCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	autoSaveCheck.BorderSizePixel = 0
	autoSaveCheck.Text = autoSaveOn and "✓" or ""
	autoSaveCheck.TextColor3 = Colors.UI.TEXT
	autoSaveCheck.TextSize = 14
	autoSaveCheck.ZIndex = Z_CONTENT
	autoSaveCheck.Parent = autoSaveRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = autoSaveCheck end
	autoSaveCheck.Activated:Connect(function()
		local nextVal = not getBool(plugin, SettingsKeys.AUTO_SAVE, true)
		setBool(plugin, SettingsKeys.AUTO_SAVE, nextVal)
		autoSaveCheck.Text = nextVal and "✓" or ""
	end)

	-- Search delay
	local delayRow = Instance.new("Frame")
	delayRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	delayRow.BackgroundTransparency = 1
	delayRow.LayoutOrder = 3
	delayRow.ZIndex = Z_CONTENT
	delayRow.Parent = contentContainer
	bindTooltip(delayRow, "SearchDelay")
	y = y + ROW_H + GAP
	local delayLabel = Instance.new("TextLabel")
	delayLabel.Size = UDim2.new(0, 140, 1, 0)
	delayLabel.BackgroundTransparency = 1
	delayLabel.Text = "Search delay (ms)"
	delayLabel.TextColor3 = Colors.UI.TEXT
	delayLabel.TextSize = 12
	delayLabel.TextXAlignment = Enum.TextXAlignment.Left
	delayLabel.ZIndex = Z_CONTENT
	delayLabel.Parent = delayRow
	local delayBox = Instance.new("TextBox")
	delayBox.Size = UDim2.new(0, 80, 0, 24)
	delayBox.Position = UDim2.new(0, 150, 0, 2)
	delayBox.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	delayBox.BorderSizePixel = 0
	delayBox.Text = tostring(getNumber(plugin, SettingsKeys.SEARCH_DELAY_MS, SettingsKeys.DEFAULT_SEARCH_DELAY_MS, SettingsKeys.SEARCH_DELAY_MIN, SettingsKeys.SEARCH_DELAY_MAX))
	delayBox.TextColor3 = Colors.UI.TEXT
	delayBox.TextSize = 12
	delayBox.ClearTextOnFocus = false
	delayBox.ZIndex = Z_CONTENT
	delayBox.Parent = delayRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = delayBox end
	delayBox.FocusLost:Connect(function()
		local n = tonumber(delayBox.Text)
		n = n and math.clamp(math.floor(n), SettingsKeys.SEARCH_DELAY_MIN, SettingsKeys.SEARCH_DELAY_MAX) or SettingsKeys.DEFAULT_SEARCH_DELAY_MS
		plugin:SetSetting(SettingsKeys.SEARCH_DELAY_MS, tostring(n))
		delayBox.Text = tostring(n)
	end)

	-- Color-coding
	local colorRow = Instance.new("Frame")
	colorRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	colorRow.BackgroundTransparency = 1
	colorRow.LayoutOrder = 4
	colorRow.ZIndex = Z_CONTENT
	colorRow.Parent = contentContainer
	bindTooltip(colorRow, "ColorCoding")
	y = y + ROW_H + GAP
	local colorLabel = Instance.new("TextLabel")
	colorLabel.Size = UDim2.new(0, 140, 1, 0)
	colorLabel.BackgroundTransparency = 1
	colorLabel.Text = "Color-coding"
	colorLabel.TextColor3 = Colors.UI.TEXT
	colorLabel.TextSize = 12
	colorLabel.TextXAlignment = Enum.TextXAlignment.Left
	colorLabel.ZIndex = Z_CONTENT
	colorLabel.Parent = colorRow
	local colorOn = getBool(plugin, SettingsKeys.COLOR_CODING, SettingsKeys.DEFAULT_COLOR_CODING)
	local colorCheck = Instance.new("TextButton")
	colorCheck.Size = UDim2.new(0, 24, 0, 24)
	colorCheck.Position = UDim2.new(0, 150, 0, 2)
	colorCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	colorCheck.BorderSizePixel = 0
	colorCheck.Text = colorOn and "✓" or ""
	colorCheck.TextColor3 = Colors.UI.TEXT
	colorCheck.TextSize = 14
	colorCheck.ZIndex = Z_CONTENT
	colorCheck.Parent = colorRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = colorCheck end
	colorCheck.Activated:Connect(function()
		local nextVal = not getBool(plugin, SettingsKeys.COLOR_CODING, true)
		setBool(plugin, SettingsKeys.COLOR_CODING, nextVal)
		colorCheck.Text = nextVal and "✓" or ""
		onSettingChanged("ColorCoding")
	end)

	-- Drag-drop
	local dragRow = Instance.new("Frame")
	dragRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	dragRow.BackgroundTransparency = 1
	dragRow.LayoutOrder = 5
	dragRow.ZIndex = Z_CONTENT
	dragRow.Parent = contentContainer
	bindTooltip(dragRow, "DragDrop")
	y = y + ROW_H + GAP
	local dragLabel = Instance.new("TextLabel")
	dragLabel.Size = UDim2.new(0, 140, 1, 0)
	dragLabel.BackgroundTransparency = 1
	dragLabel.Text = "Drag-drop"
	dragLabel.TextColor3 = Colors.UI.TEXT
	dragLabel.TextSize = 12
	dragLabel.TextXAlignment = Enum.TextXAlignment.Left
	dragLabel.ZIndex = Z_CONTENT
	dragLabel.Parent = dragRow
	local dragOn = getBool(plugin, SettingsKeys.DRAG_DROP, SettingsKeys.DEFAULT_DRAG_DROP)
	local dragCheck = Instance.new("TextButton")
	dragCheck.Size = UDim2.new(0, 24, 0, 24)
	dragCheck.Position = UDim2.new(0, 150, 0, 2)
	dragCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	dragCheck.BorderSizePixel = 0
	dragCheck.Text = dragOn and "✓" or ""
	dragCheck.TextColor3 = Colors.UI.TEXT
	dragCheck.TextSize = 14
	dragCheck.ZIndex = Z_CONTENT
	dragCheck.Parent = dragRow
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 4) c.Parent = dragCheck end
	dragCheck.Activated:Connect(function()
		local nextVal = not getBool(plugin, SettingsKeys.DRAG_DROP, true)
		setBool(plugin, SettingsKeys.DRAG_DROP, nextVal)
		dragCheck.Text = nextVal and "✓" or ""
	end)

	-- About
	local aboutRow = Instance.new("Frame")
	aboutRow.Size = UDim2.new(0, DIALOG_W - PADDING * 2, 0, ROW_H)
	aboutRow.BackgroundTransparency = 1
	aboutRow.LayoutOrder = 6
	aboutRow.ZIndex = Z_CONTENT
	aboutRow.Parent = contentContainer
	bindTooltip(aboutRow, "About")
	y = y + ROW_H + GAP
	local aboutLabel = Instance.new("TextLabel")
	aboutLabel.Size = UDim2.new(1, 0, 1, 0)
	aboutLabel.BackgroundTransparency = 1
	aboutLabel.Text = VERSION_STRING
	aboutLabel.TextColor3 = Colors.UI.TEXT_MUTED
	aboutLabel.TextSize = 11
	aboutLabel.TextXAlignment = Enum.TextXAlignment.Left
	aboutLabel.ZIndex = Z_CONTENT
	aboutLabel.Parent = aboutRow

	-- Close
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 80, 0, 32)
	closeBtn.BackgroundColor3 = Colors.UI.ACCENT
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "Close"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.TextSize = 12
	closeBtn.LayoutOrder = 7
	closeBtn.ZIndex = Z_CONTENT
	closeBtn.Parent = contentContainer
	do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = closeBtn end
	closeBtn.Activated:Connect(saveAndClose)

	local function applyDialogColors()
		dialog.BackgroundColor3 = Colors.UI.BACKGROUND
		dialogStroke.Color = Colors.UI.BORDER
		themeLabel.TextColor3 = Colors.UI.TEXT
		local t = plugin:GetSetting(SettingsKeys.THEME) or SettingsKeys.DEFAULT_THEME
		themeDarkBtn.BackgroundColor3 = t == "Dark" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
		themeDarkBtn.TextColor3 = Colors.UI.TEXT
		themeLightBtn.BackgroundColor3 = t == "Light" and Colors.UI.ACCENT or Colors.UI.BACKGROUND_LIGHT
		themeLightBtn.TextColor3 = Colors.UI.TEXT
		autoSaveLabel.TextColor3 = Colors.UI.TEXT
		autoSaveCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		autoSaveCheck.TextColor3 = Colors.UI.TEXT
		delayLabel.TextColor3 = Colors.UI.TEXT
		delayBox.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		delayBox.TextColor3 = Colors.UI.TEXT
		colorLabel.TextColor3 = Colors.UI.TEXT
		colorCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		colorCheck.TextColor3 = Colors.UI.TEXT
		dragLabel.TextColor3 = Colors.UI.TEXT
		dragCheck.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		dragCheck.TextColor3 = Colors.UI.TEXT
		aboutLabel.TextColor3 = Colors.UI.TEXT_MUTED
		closeBtn.BackgroundColor3 = Colors.UI.ACCENT
		closeBtn.TextColor3 = Color3.new(1, 1, 1)
	end
	-- Reconnect Theme buttons to use applyDialogColors (defined after all UI exists)
	themeDarkBtn.Activated:Connect(function()
		plugin:SetSetting(SettingsKeys.THEME, "Dark")
		Colors.applyTheme("Dark")
		updateThemeButtons()
		applyDialogColors()
	end)
	themeLightBtn.Activated:Connect(function()
		plugin:SetSetting(SettingsKeys.THEME, "Light")
		Colors.applyTheme("Light")
		updateThemeButtons()
		applyDialogColors()
	end)
end

return createSettingsDialog
