--[[
	UI/TagEditor.lua
	Tag editor dialog: name input, color selector, active tags (with delete), presets (with + add / delete). Close only via Close or Esc.
]]

local Colors = require(script.Parent.Parent.Utils.Colors)
local QuickPresets = require(script.Parent.Parent.Utils.QuickPresets)
local TagIcons = require(script.Parent.Parent.Utils.TagIcons)

local PADDING = 12
local GAP = 8
local ROW_H = 28
local BTN_SZ = 28
local PRESET_SCROLL_HEIGHT = 160
local ROW1_HEIGHT = 32
local COLOR_SELECTORS_PER_ROW = 15
local COLOR_GAP = 2
local COLOR_CELL_HEIGHT = 18
local COLOR_ROW_HEIGHT = 2 * COLOR_CELL_HEIGHT + COLOR_GAP
local ICON_BTN_SIZE = 24
local ICON_GAP = 2
-- Icon area height for 2 rows (computed per dialog in createTagEditorDialog from leftBlockWidth)
local CREATE_BTN_WIDTH = 96
local CREATE_BTN_HEIGHT = nil -- set below after ICON_ROW_HEIGHT is computed
local COLOR_CORNER_RADIUS = 3
local MAX_DIALOG_WIDTH = 480
local MIN_DIALOG_WIDTH = 360
local MAX_SCROLL_HEIGHT = 240
local CHIP_GAP = 2
local MARGIN = 24
local SCROLLBAR_THICKNESS = 6

-- ZIndex hierarchy (bottom to top). Tweak these to compare layering.
-- ScrollingFrame draws its scrollbar at Z_SCROLL_FRAME; handle and track may share the same Z (engine limitation).
local Z_BACKDROP = 99
local Z_OVERLAY = 100
local Z_DIALOG = 101
local Z_SCROLL_FRAME = 102
local Z_INPUT = 103
local Z_TAG_LIST = 105       -- Tag chips, rows, ×/+ buttons; lower = behind scrollbar, higher = content visible
local Z_COLOR_WRAPPER = 104
local Z_COLOR_BUTTON = 105
local Z_MAIN_BUTTON = 106   -- Create, Close, color container

local CHIP_PADDING_H = 8
local CHIP_MIN_WIDTH = 56
local CHIP_CHAR_WIDTH = 7
local CHIP_MAX_EXPAND_RATIO = 0.50

local presetNameSet = {}
for _, name in ipairs(QuickPresets.NAMES) do presetNameSet[name] = true end

local function estimateChipBaseWidth(displayText)
	local w = CHIP_PADDING_H * 2 + CHIP_CHAR_WIDTH * (displayText and #tostring(displayText) or 0)
	return math.max(CHIP_MIN_WIDTH, math.min(w, 220))
end

-- Pack items (by base width) into rows so no row exceeds maxWidth. Returns list of rows; each row is list of 1-based indices.
local function packIntoRows(baseWidths, maxWidth, gap)
	local rows = {}
	local currentRow = {}
	local currentSum = 0
	for i, base in ipairs(baseWidths) do
		local need = base + (currentSum > 0 and gap or 0)
		if currentSum + need > maxWidth and #currentRow > 0 then
			table.insert(rows, currentRow)
			currentRow = {}
			currentSum = 0
			need = base
		end
		table.insert(currentRow, i)
		currentSum = currentSum + need
	end
	if #currentRow > 0 then table.insert(rows, currentRow) end
	return rows
end

-- Distribute row width among chips: fill row, each chip can expand at most +30% of base.
local function distributeRowWidths(baseWidths, rowMaxWidth, gap)
	local n = #baseWidths
	if n == 0 then return {} end
	local totalGaps = (n - 1) * gap
	local available = rowMaxWidth - totalGaps
	local sumBase = 0
	for _, b in ipairs(baseWidths) do sumBase = sumBase + b end
	local remaining = available - sumBase
	if remaining <= 0 then
		return baseWidths
	end
	local totalMaxAdd = 0
	for _, b in ipairs(baseWidths) do
		totalMaxAdd = totalMaxAdd + CHIP_MAX_EXPAND_RATIO * b
	end
	local final = {}
	if remaining >= totalMaxAdd then
		for _, b in ipairs(baseWidths) do
			table.insert(final, math.floor(b + CHIP_MAX_EXPAND_RATIO * b + 0.5))
		end
	else
		for _, b in ipairs(baseWidths) do
			local add = remaining * (CHIP_MAX_EXPAND_RATIO * b) / totalMaxAdd
			table.insert(final, math.floor(b + add + 0.5))
		end
	end
	return final
end

local function getPresetColorIndex(name)
	for i, entry in ipairs(QuickPresets.LIST) do
		if entry[1] == name then return math.clamp(entry[2] or 1, 1, #Colors.TAG_PRESETS) end
	end
	return 1
end

-- Build 30 colors: 15 hues × 2 rows (top = bright, bottom = same hues darker). Full hue spectrum.
local function buildColorPalette()
	local out = {}
	for i = 0, COLOR_SELECTORS_PER_ROW - 1 do
		local hue = i / COLOR_SELECTORS_PER_ROW
		table.insert(out, Color3.fromHSV(hue, 0.75, 0.75))
	end
	for i = 0, COLOR_SELECTORS_PER_ROW - 1 do
		local hue = i / COLOR_SELECTORS_PER_ROW
		table.insert(out, Color3.fromHSV(hue, 0.75, 0.5))
	end
	return out
end

local COLOR_PALETTE = buildColorPalette()

local function createTagEditorDialog(parentFrame, onCreated, tagManager, onTagsChanged, anchorForPosition)
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.5
	overlay.BorderSizePixel = 0
	overlay.ZIndex = Z_OVERLAY
	overlay.Parent = parentFrame

	-- Block all interaction below: full-size button captures clicks (does not close dialog)
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.Position = UDim2.new(0, 0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.Text = ""
	backdrop.ZIndex = Z_BACKDROP
	backdrop.Parent = overlay
	-- Do not connect Activated so only Close or Esc close the dialog

	local function close()
		if escConn then escConn:Disconnect() end
		overlay:Destroy()
	end

	local UserInputService = game:GetService("UserInputService")
	local escConn
	escConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			escConn:Disconnect()
			close()
		end
	end)

	local parentSize = parentFrame.AbsoluteSize
	local availableW = (parentSize and parentSize.X or 400) - MARGIN
	local availableH = (parentSize and parentSize.Y or 400) - MARGIN
	if availableW < MIN_DIALOG_WIDTH then availableW = MIN_DIALOG_WIDTH end
	local dialogW = math.min(MAX_DIALOG_WIDTH, availableW)
	local closeBtnW, closeBtnH = 80, 32
	-- Compute left block width and icon row height so CREATE_BTN_HEIGHT is known before initialDialogH.
	local leftContentWidth = dialogW - PADDING * 2 - CREATE_BTN_WIDTH - GAP
	local colorCellW = math.floor((leftContentWidth - (COLOR_SELECTORS_PER_ROW - 1) * COLOR_GAP) / COLOR_SELECTORS_PER_ROW)
	local leftBlockWidth = COLOR_SELECTORS_PER_ROW * colorCellW + (COLOR_SELECTORS_PER_ROW - 1) * COLOR_GAP
	local iconsPerRow = math.max(1, math.floor((leftBlockWidth + ICON_GAP) / (ICON_BTN_SIZE + ICON_GAP)))
	local ICON_ROW_HEIGHT = 2 * (ICON_BTN_SIZE + ICON_GAP) + ICON_GAP
	local CREATE_BTN_HEIGHT = ROW1_HEIGHT + GAP + COLOR_ROW_HEIGHT + GAP + ICON_ROW_HEIGHT
	local initialDialogH = PADDING + CREATE_BTN_HEIGHT + GAP + PRESET_SCROLL_HEIGHT + GAP + closeBtnH + PADDING

	local dialog = Instance.new("Frame")
	dialog.Size = UDim2.new(0, dialogW, 0, initialDialogH)
	dialog.Position = UDim2.new(0.5, -dialogW / 2, 0.5, -initialDialogH / 2)
	dialog.BackgroundColor3 = Colors.UI.BACKGROUND
	dialog.BorderSizePixel = 0
	dialog.ZIndex = Z_DIALOG
	dialog.Parent = overlay
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = dialog
	end
	do
		local s = Instance.new("UIStroke")
		s.Color = Colors.UI.BORDER
		s.Parent = dialog
	end

	local nameBox = Instance.new("TextBox")
	nameBox.Size = UDim2.new(0, leftBlockWidth, 0, ROW1_HEIGHT)
	nameBox.Position = UDim2.new(0, PADDING, 0, PADDING)
	nameBox.BackgroundColor3 = Colors.UI.INPUT_FIELD
	nameBox.BorderSizePixel = 0
	nameBox.PlaceholderText = "Tag name"
	nameBox.Text = ""
	nameBox.TextColor3 = Colors.UI.TEXT
	nameBox.TextSize = 14
	nameBox.ClearTextOnFocus = false
	nameBox.ZIndex = Z_INPUT
	nameBox.Parent = dialog
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = nameBox
	end

	-- Scroll area: height set dynamically after refreshTagList; right inset keeps scrollbar visible (not clipped by dialog corner)
	local tagListScroll = Instance.new("ScrollingFrame")
	tagListScroll.Size = UDim2.new(1, -(PADDING * 2), 0, 120)
	tagListScroll.Position = UDim2.new(0, PADDING, 0, PADDING + CREATE_BTN_HEIGHT + GAP)
	tagListScroll.BackgroundTransparency = 1
	tagListScroll.BorderSizePixel = 0
	tagListScroll.ScrollBarThickness = SCROLLBAR_THICKNESS
	tagListScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	tagListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	tagListScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tagListScroll.ScrollBarImageColor3 = Colors.UI.SCROLLBAR
	tagListScroll.ScrollBarImageTransparency = 0
	-- Canvas is always inset by scrollbar thickness so content width is consistent and nothing is cropped when bar appears
	tagListScroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	tagListScroll.ZIndex = Z_SCROLL_FRAME
	tagListScroll.Parent = dialog

	local tagListContent = Instance.new("Frame")
	tagListContent.Size = UDim2.new(1, 0, 0, 0)
	tagListContent.AutomaticSize = Enum.AutomaticSize.Y
	tagListContent.BackgroundTransparency = 1
	tagListContent.ZIndex = Z_TAG_LIST
	tagListContent.Parent = tagListScroll

	local tagListLayout = Instance.new("UIListLayout")
	tagListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tagListLayout.Padding = UDim.new(0, 2)
	tagListLayout.Parent = tagListContent

	-- Active (non-preset) tags: one or more rows above presets; each chip has x overlay on top
	local activeTagsContainer = Instance.new("Frame")
	activeTagsContainer.Size = UDim2.new(1, 0, 0, 0)
	activeTagsContainer.AutomaticSize = Enum.AutomaticSize.Y
	activeTagsContainer.BackgroundTransparency = 1
	activeTagsContainer.LayoutOrder = 1
	activeTagsContainer.Parent = tagListContent

	local activeTagsList = Instance.new("UIListLayout")
	activeTagsList.SortOrder = Enum.SortOrder.LayoutOrder
	activeTagsList.Padding = UDim.new(0, CHIP_GAP)
	activeTagsList.FillDirection = Enum.FillDirection.Vertical
	activeTagsList.VerticalAlignment = Enum.VerticalAlignment.Top
	activeTagsList.Parent = activeTagsContainer

	local presetContainer = Instance.new("Frame")
	presetContainer.Size = UDim2.new(1, 0, 0, 0)
	presetContainer.AutomaticSize = Enum.AutomaticSize.Y
	presetContainer.BackgroundTransparency = 1
	presetContainer.LayoutOrder = 2
	presetContainer.Parent = tagListContent

	local presetListLayout = Instance.new("UIListLayout")
	presetListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	presetListLayout.Padding = UDim.new(0, 2)
	presetListLayout.Parent = presetContainer

	local function makeActionButton(text, bgColor, onActivate)
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, BTN_SZ, 0, BTN_SZ)
		btn.BackgroundColor3 = bgColor
		btn.BorderSizePixel = 0
		btn.Text = text
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.TextSize = 16
		btn.Font = Enum.Font.GothamBold
		btn.ZIndex = Z_TAG_LIST
		btn.Visible = false
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 6)
			c.Parent = btn
		end
		if onActivate then btn.Activated:Connect(onActivate) end
		return btn
	end

	-- Color + icon selection (before refreshTagList so chips can call setSelectedColor/setSelectedIcon)
	local SELECTED_HIGHLIGHT = Color3.new(1, 1, 1)
	local selectedColor = COLOR_PALETTE[1]
	local selectedIcon = TagIcons.LIST[1] or TagIcons.DEFAULT
	local colorContainer = Instance.new("Frame")
	colorContainer.Size = UDim2.new(0, leftBlockWidth, 0, COLOR_ROW_HEIGHT)
	colorContainer.Position = UDim2.new(0, PADDING, 0, PADDING + ROW1_HEIGHT + GAP)
	colorContainer.BackgroundTransparency = 1
	colorContainer.ZIndex = Z_MAIN_BUTTON
	colorContainer.Parent = dialog
	local colorGrid = Instance.new("UIGridLayout")
	colorGrid.CellSize = UDim2.new(0, colorCellW, 0, COLOR_CELL_HEIGHT)
	colorGrid.CellPadding = UDim2.new(0, COLOR_GAP, 0, COLOR_GAP)
	colorGrid.FillDirection = Enum.FillDirection.Horizontal
	colorGrid.SortOrder = Enum.SortOrder.LayoutOrder
	colorGrid.Parent = colorContainer
	local colorWrappers = {}
	for i, color in ipairs(COLOR_PALETTE) do
		local wrapper = Instance.new("Frame")
		wrapper.Size = UDim2.new(0, colorCellW, 0, COLOR_CELL_HEIGHT)
		wrapper.BackgroundTransparency = 1
		wrapper.LayoutOrder = i
		wrapper.ZIndex = Z_COLOR_WRAPPER
		wrapper.Parent = colorContainer
		do
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, COLOR_CORNER_RADIUS)
			corner.Parent = wrapper
		end
		local stroke = Instance.new("UIStroke")
		stroke.Color = SELECTED_HIGHLIGHT
		stroke.Thickness = (i == 1) and 3 or 0
		stroke.Parent = wrapper
		local cb = Instance.new("TextButton")
		cb.Size = UDim2.new(1, 0, 1, 0)
		cb.Position = UDim2.new(0, 0, 0, 0)
		cb.BackgroundColor3 = color
		cb.BorderSizePixel = 0
		cb.Text = ""
		cb.ZIndex = Z_COLOR_BUTTON
		cb.Parent = wrapper
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, COLOR_CORNER_RADIUS)
			c.Parent = cb
		end
		cb.Activated:Connect(function()
			selectedColor = color
			for j, w in ipairs(colorWrappers) do
				local s = w:FindFirstChildOfClass("UIStroke")
				if s then
					s.Thickness = (COLOR_PALETTE[j] == color) and 3 or 0
					s.Color = SELECTED_HIGHLIGHT
				end
			end
		end)
		table.insert(colorWrappers, wrapper)
	end
	-- Icon area: 2 rows, iconsPerRow per row so nothing overflows
	local iconContainer = Instance.new("Frame")
	iconContainer.Size = UDim2.new(0, leftBlockWidth, 0, ICON_ROW_HEIGHT)
	iconContainer.Position = UDim2.new(0, PADDING, 0, PADDING + ROW1_HEIGHT + GAP + COLOR_ROW_HEIGHT + GAP)
	iconContainer.BackgroundTransparency = 1
	iconContainer.ZIndex = Z_MAIN_BUTTON
	iconContainer.Parent = dialog
	local iconRowsLayout = Instance.new("UIListLayout")
	iconRowsLayout.FillDirection = Enum.FillDirection.Vertical
	iconRowsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	iconRowsLayout.Padding = UDim.new(0, ICON_GAP)
	iconRowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	iconRowsLayout.Parent = iconContainer
	local iconRow1 = Instance.new("Frame")
	iconRow1.Size = UDim2.new(1, 0, 0, ICON_BTN_SIZE)
	iconRow1.BackgroundTransparency = 1
	iconRow1.LayoutOrder = 1
	iconRow1.ZIndex = Z_COLOR_WRAPPER
	iconRow1.Parent = iconContainer
	local iconRow1List = Instance.new("UIListLayout")
	iconRow1List.FillDirection = Enum.FillDirection.Horizontal
	iconRow1List.VerticalAlignment = Enum.VerticalAlignment.Center
	iconRow1List.Padding = UDim.new(0, ICON_GAP)
	iconRow1List.Parent = iconRow1
	local iconRow2 = Instance.new("Frame")
	iconRow2.Size = UDim2.new(1, 0, 0, ICON_BTN_SIZE)
	iconRow2.BackgroundTransparency = 1
	iconRow2.LayoutOrder = 2
	iconRow2.ZIndex = Z_COLOR_WRAPPER
	iconRow2.Parent = iconContainer
	local iconRow2List = Instance.new("UIListLayout")
	iconRow2List.FillDirection = Enum.FillDirection.Horizontal
	iconRow2List.VerticalAlignment = Enum.VerticalAlignment.Center
	iconRow2List.Padding = UDim.new(0, ICON_GAP)
	iconRow2List.Parent = iconRow2
	local iconWrappers = {}
	for i, icon in ipairs(TagIcons.LIST) do
		local row = (i <= iconsPerRow) and iconRow1 or iconRow2
		local orderInRow = (i <= iconsPerRow) and i or (i - iconsPerRow)
		local wrapper = Instance.new("Frame")
		wrapper.Size = UDim2.new(0, ICON_BTN_SIZE, 0, ICON_BTN_SIZE)
		wrapper.BackgroundTransparency = 1
		wrapper.LayoutOrder = orderInRow
		wrapper.ZIndex = Z_COLOR_WRAPPER
		wrapper.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = SELECTED_HIGHLIGHT
		stroke.Thickness = (icon == selectedIcon) and 3 or 0
		stroke.Parent = wrapper
		local ib = Instance.new("TextButton")
		ib.Size = UDim2.new(1, 0, 1, 0)
		ib.Position = UDim2.new(0, 0, 0, 0)
		ib.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		ib.BorderSizePixel = 0
		ib.Text = icon
		ib.TextColor3 = Colors.UI.TEXT
		ib.TextSize = 14
		ib.ZIndex = Z_COLOR_BUTTON
		ib.Parent = wrapper
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = ib
		end
		ib.Activated:Connect(function()
			selectedIcon = icon
			for _, w in ipairs(iconWrappers) do
				local s = w:FindFirstChildOfClass("UIStroke")
				if s then
					s.Thickness = 0
				end
			end
			local sw = wrapper:FindFirstChildOfClass("UIStroke")
			if sw then sw.Thickness = 3 end
		end)
		table.insert(iconWrappers, wrapper)
	end
	local function updateColorSelectionUI()
		for j, w in ipairs(colorWrappers) do
			local s = w:FindFirstChildOfClass("UIStroke")
			if s then
				s.Thickness = (COLOR_PALETTE[j] == selectedColor) and 3 or 0
				s.Color = SELECTED_HIGHLIGHT
			end
		end
	end
	local function updateIconSelectionUI()
		for i, w in ipairs(iconWrappers) do
			local s = w:FindFirstChildOfClass("UIStroke")
			if s then
				s.Thickness = (TagIcons.LIST[i] == selectedIcon) and 3 or 0
			end
		end
	end
	local function setSelectedColor(c)
		selectedColor = c
		updateColorSelectionUI()
	end
	local function setSelectedIcon(iconVal)
		selectedIcon = (iconVal and iconVal ~= "") and iconVal or TagIcons.DEFAULT
		updateIconSelectionUI()
	end

	local function refreshTagList()
		for _, c in ipairs(activeTagsContainer:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
		for _, c in ipairs(presetContainer:GetChildren()) do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end

		if not tagManager then return end

		local allTags = tagManager:getAllTags()
		local activeNonPreset = {}
		for _, tag in ipairs(allTags) do
			if not presetNameSet[tag.name] then
				table.insert(activeNonPreset, tag)
			end
		end

		-- Active (non-preset) tags: pack into rows (no cropping), then fill row width (max +30% per chip)
		-- Reserve space for scrollbar so when it appears the viewport doesn't shrink and crop content
		local listWidth = dialogW - PADDING * 2 - SCROLLBAR_THICKNESS
		local activeBaseWidths = {}
		for _, tag in ipairs(activeNonPreset) do
			local displayText = (tag.icon and (tag.icon .. " ") or "") .. tag.name .. " (" .. tostring(tag.usageCount) .. ")"
			table.insert(activeBaseWidths, estimateChipBaseWidth(displayText))
		end
		local activeRows = packIntoRows(activeBaseWidths, listWidth, CHIP_GAP)
		for rowIdx, rowIndices in ipairs(activeRows) do
			local rowBases = {}
			for _, idx in ipairs(rowIndices) do
				table.insert(rowBases, activeBaseWidths[idx])
			end
			local rowWidths = distributeRowWidths(rowBases, listWidth, CHIP_GAP)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.BackgroundTransparency = 1
			row.LayoutOrder = rowIdx
			row.ZIndex = Z_TAG_LIST
			row.Parent = activeTagsContainer
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			rowLayout.Padding = UDim.new(0, CHIP_GAP)
			rowLayout.Parent = row
			for j, idx in ipairs(rowIndices) do
				local tag = activeNonPreset[idx]
				local width = rowWidths[j]
				local wrapper = Instance.new("Frame")
				wrapper.Size = UDim2.new(0, width, 0, ROW_H)
				wrapper.BackgroundTransparency = 1
				wrapper.LayoutOrder = j
				wrapper.ZIndex = Z_TAG_LIST
				wrapper.Parent = row

				local chip = Instance.new("TextButton")
				chip.Size = UDim2.new(1, 0, 1, 0)
				chip.Position = UDim2.new(0, 0, 0, 0)
				chip.BackgroundColor3 = tag.color
				chip.BorderSizePixel = 0
				chip.Text = (tag.icon and (tag.icon .. " ") or "") .. tag.name .. " (" .. tostring(tag.usageCount) .. ")"
				chip.TextColor3 = Color3.new(1, 1, 1)
				chip.TextSize = 12
				chip.Font = Enum.Font.Gotham
				chip.AutoButtonColor = true
				chip.ZIndex = Z_TAG_LIST
				chip.TextTruncate = Enum.TextTruncate.AtEnd
				chip.Parent = wrapper
				chip.Activated:Connect(function()
					nameBox.Text = tag.name
					setSelectedColor(tag.color)
					setSelectedIcon(tag.icon)
				end)
				do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = chip end
				do local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, CHIP_PADDING_H) p.PaddingRight = UDim.new(0, CHIP_PADDING_H) p.Parent = chip end

				local delBtn = makeActionButton("×", Colors.UI.ERROR, function()
					tagManager:deleteTag(tag.id)
					refreshTagList()
					if onTagsChanged then onTagsChanged() end
				end)
				delBtn.Position = UDim2.new(1, -BTN_SZ, 0, 0)
				delBtn.Parent = wrapper

				wrapper.MouseEnter:Connect(function() delBtn.Visible = true end)
				wrapper.MouseLeave:Connect(function() delBtn.Visible = false end)
			end
		end

		-- Preset tags: pack into rows (no cropping), fill row width (max +30% per chip)
		local presetItems = {}
		local presetBaseWidths = {}
		for _, presetName in ipairs(QuickPresets.NAMES) do
			local tag = tagManager:getTag(presetName)
			local displayText = tag and ((tag.icon and (tag.icon .. " ") or "") .. presetName .. " (" .. tostring(tag.usageCount) .. ")") or presetName
			table.insert(presetBaseWidths, estimateChipBaseWidth(displayText))
			table.insert(presetItems, { name = presetName, tag = tag })
		end
		local presetRows = packIntoRows(presetBaseWidths, listWidth, CHIP_GAP)
		for rowIdx, rowIndices in ipairs(presetRows) do
			local rowBases = {}
			for _, idx in ipairs(rowIndices) do
				table.insert(rowBases, presetBaseWidths[idx])
			end
			local rowWidths = distributeRowWidths(rowBases, listWidth, CHIP_GAP)
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, ROW_H)
			row.BackgroundTransparency = 1
			row.LayoutOrder = rowIdx
			row.ZIndex = Z_TAG_LIST
			row.Parent = presetContainer
			local rowLayout = Instance.new("UIListLayout")
			rowLayout.FillDirection = Enum.FillDirection.Horizontal
			rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
			rowLayout.Padding = UDim.new(0, CHIP_GAP)
			rowLayout.Parent = row
			for j, idx in ipairs(rowIndices) do
				local item = presetItems[idx]
				local presetName = item.name
				local tag = item.tag
				local width = rowWidths[j]
				local wrapper = Instance.new("Frame")
				wrapper.Size = UDim2.new(0, width, 0, ROW_H)
				wrapper.BackgroundTransparency = 1
				wrapper.LayoutOrder = j
				wrapper.ZIndex = Z_TAG_LIST
				wrapper.Parent = row

				if tag then
					local chip = Instance.new("TextButton")
					chip.Size = UDim2.new(1, 0, 1, 0)
					chip.Position = UDim2.new(0, 0, 0, 0)
					chip.BackgroundColor3 = tag.color
					chip.BorderSizePixel = 0
					chip.Text = (tag.icon and (tag.icon .. " ") or "") .. presetName .. " (" .. tostring(tag.usageCount) .. ")"
					chip.TextColor3 = Color3.new(1, 1, 1)
					chip.TextSize = 12
					chip.Font = Enum.Font.Gotham
					chip.AutoButtonColor = true
					chip.ZIndex = Z_TAG_LIST
					chip.TextTruncate = Enum.TextTruncate.AtEnd
					chip.Parent = wrapper
					chip.Activated:Connect(function()
						nameBox.Text = presetName
						setSelectedColor(tag.color)
						setSelectedIcon(tag.icon)
					end)
					do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = chip end
					do local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, CHIP_PADDING_H) p.PaddingRight = UDim.new(0, CHIP_PADDING_H) p.Parent = chip end

					local delBtn = makeActionButton("×", Colors.UI.ERROR, function()
						tagManager:deleteTag(tag.id)
						refreshTagList()
						if onTagsChanged then onTagsChanged() end
					end)
					delBtn.Position = UDim2.new(1, -BTN_SZ, 0, 0)
					delBtn.Parent = wrapper

					wrapper.MouseEnter:Connect(function() delBtn.Visible = true end)
					wrapper.MouseLeave:Connect(function() delBtn.Visible = false end)
				else
					local label = Instance.new("TextButton")
					label.Size = UDim2.new(1, 0, 1, 0)
					label.Position = UDim2.new(0, 0, 0, 0)
					label.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
					label.BorderSizePixel = 0
					label.Text = presetName
					label.TextColor3 = Colors.UI.TEXT
					label.TextSize = 12
					label.Font = Enum.Font.Gotham
					label.AutoButtonColor = true
					label.ZIndex = Z_TAG_LIST
					label.TextTruncate = Enum.TextTruncate.AtEnd
					label.Parent = wrapper
					label.Activated:Connect(function()
						nameBox.Text = presetName
						setSelectedColor(Colors.TAG_PRESETS[getPresetColorIndex(presetName)])
						setSelectedIcon(QuickPresets.getDefaultIcon(presetName))
					end)
					do local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, 6) c.Parent = label end
					do local p = Instance.new("UIPadding") p.PaddingLeft = UDim.new(0, CHIP_PADDING_H) p.PaddingRight = UDim.new(0, CHIP_PADDING_H) p.Parent = label end

					local addBtn = makeActionButton("+", Colors.UI.SUCCESS, function()
						local colorIndex = getPresetColorIndex(presetName)
						local color = Colors.TAG_PRESETS[colorIndex]
						local icon = QuickPresets.getDefaultIcon(presetName)
						tagManager:createTag(presetName, color, "", icon)
						refreshTagList()
						if onTagsChanged then onTagsChanged() end
					end)
					addBtn.Position = UDim2.new(0, 0, 0, 0)
					addBtn.Parent = wrapper

					wrapper.MouseEnter:Connect(function() addBtn.Visible = true end)
					wrapper.MouseLeave:Connect(function() addBtn.Visible = false end)
				end
			end
		end

		-- Dynamic height: measure content and resize; clamp to widget so color/create/close stay visible
		task.defer(function()
			local contentH = tagListContent.AbsoluteSize.Y
			local fixedH = PADDING + CREATE_BTN_HEIGHT + GAP + GAP + closeBtnH + PADDING
			local maxScrollH = math.max(24, availableH - fixedH)
			local scrollH = math.min(math.max(contentH, 24), MAX_SCROLL_HEIGHT, maxScrollH)
			tagListScroll.Size = UDim2.new(1, -(PADDING * 2), 0, scrollH)
			local totalH = PADDING + CREATE_BTN_HEIGHT + GAP + scrollH + GAP + closeBtnH + PADDING
			totalH = math.min(totalH, availableH)
			dialog.Size = UDim2.new(0, dialogW, 0, totalH)
			local pSize = parentFrame.AbsoluteSize
			local relX = (pSize.X - dialogW) / 2
			local relY = math.max(0, (pSize.Y - totalH) / 2)
			dialog.Position = UDim2.new(0, relX, 0, relY)
		end)
	end

	refreshTagList()

	local createBtn = Instance.new("TextButton")
	local createBtnWidth = dialogW - PADDING * 2 - leftBlockWidth - GAP
	createBtn.Size = UDim2.new(0, createBtnWidth, 0, CREATE_BTN_HEIGHT)
	createBtn.Position = UDim2.new(0, PADDING + leftBlockWidth + GAP, 0, PADDING)
	createBtn.BackgroundColor3 = Colors.UI.ACCENT
	createBtn.BorderSizePixel = 0
	createBtn.Text = "Create"
	createBtn.TextColor3 = Colors.UI.TEXT
	createBtn.TextSize = 14
	createBtn.ZIndex = Z_MAIN_BUTTON
	createBtn.Parent = dialog
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = createBtn
	end

	local function updateCreateButtonState()
		local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		local isUpdate = name ~= "" and tagManager and tagManager:getTag(name)
		createBtn.Text = isUpdate and "Update" or "Create"
		createBtn.BackgroundColor3 = isUpdate and Colors.UI.WARNING or Colors.UI.ACCENT
	end
	nameBox:GetPropertyChangedSignal("Text"):Connect(updateCreateButtonState)
	updateCreateButtonState()

	createBtn.Activated:Connect(function()
		local name = nameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then return end
		if tagManager and tagManager:getTag(name) then
			tagManager:updateTagColor(name, selectedColor)
			tagManager:updateTagIcon(name, selectedIcon)
		elseif onCreated then
			onCreated(name, selectedColor, selectedIcon)
		end
		refreshTagList()
		if onTagsChanged then onTagsChanged() end
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, closeBtnW, 0, closeBtnH)
	closeBtn.Position = UDim2.new(0.5, -closeBtnW / 2, 1, -closeBtnH - PADDING)
	closeBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "Close"
	closeBtn.TextColor3 = Colors.UI.TEXT_MUTED
	closeBtn.TextSize = 14
	closeBtn.ZIndex = Z_MAIN_BUTTON
	closeBtn.Parent = dialog
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = closeBtn
	end
	closeBtn.Activated:Connect(close)

	return dialog
end

return createTagEditorDialog
