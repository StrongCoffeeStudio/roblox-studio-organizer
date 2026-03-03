--[[
	UI/MainPanel.lua
	Main docking panel: search, tags, clear filter, object list.
]]

local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local Colors = require(script.Parent.Parent.Utils.Colors)
local Helpers = require(script.Parent.Parent.Utils.Helpers)
local createTagChip = require(script.Parent.Components.TagChip)
local ObjectList = require(script.Parent.Components.ObjectList)
local createTagEditorDialog = require(script.Parent.TagEditor)
local createSettingsDialog = require(script.Parent.SettingsDialog)
local SettingsKeys = require(script.Parent.Parent.Utils.SettingsKeys)
local FavoritesManager = require(script.Parent.Parent.Core.FavoritesManager)

local DROP_TARGET_HIGHLIGHT = Color3.fromRGB(0, 200, 100)

local DEFAULT_SEARCH_DELAY_MS = 300
local DEBOUNCE_HIERARCHY_MS = 200
local HIERARCHY_REFRESH_INTERVAL_SEC = 2
local MAX_OBJECTS_DISPLAY = 500
local OBJECT_LIST_BOTTOM_PADDING = 8
local ROOT_PADDING = 8

local MainPanel = {}
MainPanel.__index = MainPanel

function MainPanel.new(widget, tagManager, searchEngine)
	local self = setmetatable({}, MainPanel)
	self.widget = widget
	self.tagManager = tagManager
	self.searchEngine = searchEngine
	self.activeFilterTagId = nil
	self.searchQuery = ""
	self.searchDebounceGen = 0
	self.tagFilterQuery = ""
	self.hierarchyDebounceGen = 0
	-- Drag-drop: chip -> tag for hit-test; row -> object for drop target; current drag state
	self._chipToTag = {}
	self._rowToObject = {}
	self._draggingTag = nil
	self._dropTargetChip = nil
	self._dragEndConnection = nil
	-- Expanded state keyed by Instance (weak keys) so same-name instances don't share state
	self.expandedPaths = setmetatable({}, { __mode = "k" })
	self.favoritesManager = (tagManager and tagManager.plugin) and FavoritesManager.new(tagManager.plugin) or nil
	self._favoritesVersion = 0 -- bump when favorites change so object list re-renders (star state)
	return self
end

function MainPanel:build()
	local plugin = self.tagManager and self.tagManager.plugin
	if plugin then
		local theme = plugin:GetSetting(SettingsKeys.THEME) or SettingsKeys.DEFAULT_THEME
		Colors.applyTheme(theme)
		if self.tagManager.setAutoSave then
			local autoSave = (plugin:GetSetting(SettingsKeys.AUTO_SAVE) ~= "false")
			self.tagManager:setAutoSave(autoSave)
		end
	end

	local root = Instance.new("Frame")
	root.Name = "MainPanel"
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundColor3 = Colors.UI.BACKGROUND
	root.BorderSizePixel = 0
	root.Parent = self.widget
	self.root = root

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = root

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = root

	-- Search row
	local searchRow = Instance.new("Frame")
	searchRow.Size = UDim2.new(1, 0, 0, 32)
	searchRow.BackgroundTransparency = 1
	searchRow.LayoutOrder = 1
	searchRow.Parent = root

	local searchLayout = Instance.new("UIListLayout")
	searchLayout.FillDirection = Enum.FillDirection.Horizontal
	searchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	searchLayout.Padding = UDim.new(0, 6)
	searchLayout.Parent = searchRow

	self.searchBox = Instance.new("TextBox")
	self.searchBox.Size = UDim2.new(1, -62, 1, 0)
	self.searchBox.BackgroundColor3 = Colors.UI.INPUT_FIELD
	self.searchBox.BorderSizePixel = 0
	self.searchBox.PlaceholderText = "Search by name..."
	self.searchBox.Text = ""
	self.searchBox.TextColor3 = Colors.UI.TEXT
	self.searchBox.TextSize = 14
	self.searchBox.ClearTextOnFocus = false
	self.searchBox.LayoutOrder = 1
	self.searchBox.Parent = searchRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.searchBox
	end
	self.searchClearBtn = Instance.new("TextButton")
	self.searchClearBtn.Size = UDim2.new(0, 24, 0, 24)
	self.searchClearBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.searchClearBtn.BorderSizePixel = 0
	self.searchClearBtn.Text = "×"
	self.searchClearBtn.TextColor3 = Colors.UI.TEXT_MUTED
	self.searchClearBtn.TextSize = 16
	self.searchClearBtn.LayoutOrder = 2
	self.searchClearBtn.Visible = false
	self.searchClearBtn.Parent = searchRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = self.searchClearBtn
	end

	self.settingsBtn = Instance.new("TextButton")
	self.settingsBtn.Size = UDim2.new(0, 32, 0, 32)
	self.settingsBtn.LayoutOrder = 3
	self.settingsBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.settingsBtn.BorderSizePixel = 0
	self.settingsBtn.Text = "⚙"
	self.settingsBtn.TextColor3 = Colors.UI.TEXT
	self.settingsBtn.TextSize = 16
	self.settingsBtn.Parent = searchRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.settingsBtn
	end

	-- Tags section: horizontal scroll when many tags
	self.tagsScroll = Instance.new("ScrollingFrame")
	self.tagsScroll.Size = UDim2.new(1, 0, 0, 40)
	self.tagsScroll.BackgroundTransparency = 1
	self.tagsScroll.BorderSizePixel = 0
	self.tagsScroll.LayoutOrder = 2
	self.tagsScroll.ScrollingDirection = Enum.ScrollingDirection.X
	self.tagsScroll.ScrollBarThickness = 6
	self.tagsScroll.ScrollBarImageColor3 = Colors.UI.SCROLLBAR or Colors.UI.BORDER
	self.tagsScroll.ScrollBarImageTransparency = 0
	self.tagsScroll.CanvasSize = UDim2.new(0, 0, 0, 40)
	self.tagsScroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	self.tagsScroll.Parent = root

	self.tagsContainer = Instance.new("Frame")
	self.tagsContainer.Size = UDim2.new(0, 0, 1, 0)
	self.tagsContainer.AutomaticSize = Enum.AutomaticSize.X
	self.tagsContainer.BackgroundTransparency = 1
	self.tagsContainer.Parent = self.tagsScroll
	local tagsListLayout = Instance.new("UIListLayout")
	tagsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tagsListLayout.FillDirection = Enum.FillDirection.Horizontal
	tagsListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tagsListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tagsListLayout.Padding = UDim.new(0, 2)
	tagsListLayout.Parent = self.tagsContainer
	tagsListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local cs = tagsListLayout.AbsoluteContentSize
		self.tagsScroll.CanvasSize = UDim2.new(0, cs.X + 4, 0, math.max(cs.Y, 40))
	end)

	-- Search/filter tags by name (shows only matching tag chips)
	self.tagFilterRow = Instance.new("Frame")
	self.tagFilterRow.Name = "TagFilterRow"
	self.tagFilterRow.Size = UDim2.new(0, 0, 0, 28)
	self.tagFilterRow.AutomaticSize = Enum.AutomaticSize.X
	self.tagFilterRow.BackgroundTransparency = 1
	self.tagFilterRow.LayoutOrder = 0
	self.tagFilterRow.Parent = self.tagsContainer
	local tagFilterRow = self.tagFilterRow
	local tagFilterLayout = Instance.new("UIListLayout")
	tagFilterLayout.FillDirection = Enum.FillDirection.Horizontal
	tagFilterLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tagFilterLayout.Padding = UDim.new(0, 4)
	tagFilterLayout.Parent = tagFilterRow
	self.tagFilterBox = Instance.new("TextBox")
	self.tagFilterBox.Size = UDim2.new(0, 120, 0, 26)
	self.tagFilterBox.BackgroundColor3 = Colors.UI.INPUT_FIELD
	self.tagFilterBox.BorderSizePixel = 0
	self.tagFilterBox.PlaceholderText = "Search tags…"
	self.tagFilterBox.Text = ""
	self.tagFilterBox.TextColor3 = Colors.UI.TEXT
	self.tagFilterBox.TextSize = 12
	self.tagFilterBox.ClearTextOnFocus = false
	self.tagFilterBox.LayoutOrder = 1
	self.tagFilterBox.Parent = tagFilterRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = self.tagFilterBox
	end
	self.tagFilterClearBtn = Instance.new("TextButton")
	self.tagFilterClearBtn.Size = UDim2.new(0, 24, 0, 24)
	self.tagFilterClearBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.tagFilterClearBtn.BorderSizePixel = 0
	self.tagFilterClearBtn.Text = "×"
	self.tagFilterClearBtn.TextColor3 = Colors.UI.TEXT_MUTED
	self.tagFilterClearBtn.TextSize = 16
	self.tagFilterClearBtn.LayoutOrder = 2
	self.tagFilterClearBtn.Visible = false
	self.tagFilterClearBtn.Parent = self.tagFilterRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 4)
		c.Parent = self.tagFilterClearBtn
	end

	-- "Tags" button: first item on the tag row (left of all tags)
	self.addTagBtn = Instance.new("TextButton")
	self.addTagBtn.Size = UDim2.new(0, 64, 0, 28)
	self.addTagBtn.LayoutOrder = 1
	self.addTagBtn.BackgroundColor3 = Colors.UI.ACCENT
	self.addTagBtn.BorderSizePixel = 0
	self.addTagBtn.Text = "Tags ⁞"
	self.addTagBtn.TextColor3 = Colors.UI.TEXT
	self.addTagBtn.TextSize = 14
	self.addTagBtn.ZIndex = 10
	self.addTagBtn.Parent = self.tagsContainer
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.addTagBtn
	end

	-- Filter actions row: Clear / Apply / Remove side by side
	self.filterActionsRow = Instance.new("Frame")
	self.filterActionsRow.Size = UDim2.new(1, 0, 0, 28)
	self.filterActionsRow.BackgroundTransparency = 1
	self.filterActionsRow.LayoutOrder = 4
	self.filterActionsRow.Visible = false
	self.filterActionsRow.ZIndex = 10
	self.filterActionsRow.Parent = root
	local filterActionsLayout = Instance.new("UIListLayout")
	filterActionsLayout.FillDirection = Enum.FillDirection.Horizontal
	filterActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	filterActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	filterActionsLayout.Padding = UDim.new(0, 4)
	filterActionsLayout.Parent = self.filterActionsRow

	self.clearFilterBtn = Instance.new("TextButton")
	self.clearFilterBtn.Size = UDim2.new(0, 0, 1, 0)
	self.clearFilterBtn.AutomaticSize = Enum.AutomaticSize.X
	self.clearFilterBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.clearFilterBtn.BorderSizePixel = 0
	self.clearFilterBtn.Text = "Clear filter"
	self.clearFilterBtn.TextColor3 = Colors.UI.TEXT_MUTED
	self.clearFilterBtn.TextSize = 12
	self.clearFilterBtn.LayoutOrder = 1
	self.clearFilterBtn.ZIndex = 10
	self.clearFilterBtn.Parent = self.filterActionsRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.clearFilterBtn
	end
	do
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 10)
		p.PaddingRight = UDim.new(0, 10)
		p.Parent = self.clearFilterBtn
	end

	-- Favorites section: header (label + star drop target) + list; list height by content, max 4 rows then scroll
	local FAV_HEADER_H = 28
	local FAV_ROW_H = 22
	local FAV_ROW_GAP = 2
	local FAV_MAX_VISIBLE_ROWS = 4
	local FAV_LIST_MAX_H = FAV_MAX_VISIBLE_ROWS * FAV_ROW_H + (FAV_MAX_VISIBLE_ROWS - 1) * FAV_ROW_GAP
	self._FAV_ROW_H = FAV_ROW_H
	self._FAV_ROW_GAP = FAV_ROW_GAP
	self._FAV_LIST_MAX_H = FAV_LIST_MAX_H
	self.favoritesSection = Instance.new("Frame")
	self.favoritesSection.Size = UDim2.new(1, 0, 0, 0)
	self.favoritesSection.AutomaticSize = Enum.AutomaticSize.Y
	self.favoritesSection.BackgroundTransparency = 1
	self.favoritesSection.LayoutOrder = 5
	self.favoritesSection.Visible = true
	self.favoritesSection.Parent = root
	local favSectionList = Instance.new("UIListLayout")
	favSectionList.SortOrder = Enum.SortOrder.LayoutOrder
	favSectionList.Padding = UDim.new(0, 4)
	favSectionList.Parent = self.favoritesSection
	local favHeader = Instance.new("Frame")
	favHeader.Size = UDim2.new(1, 0, 0, FAV_HEADER_H)
	favHeader.BackgroundTransparency = 1
	favHeader.LayoutOrder = 1
	favHeader.Parent = self.favoritesSection
	local favHeaderLayout = Instance.new("UIListLayout")
	favHeaderLayout.FillDirection = Enum.FillDirection.Horizontal
	favHeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	favHeaderLayout.Padding = UDim.new(0, 6)
	favHeaderLayout.Parent = favHeader
	self.favLabel = Instance.new("TextLabel")
	self.favLabel.Size = UDim2.new(0, 0, 1, 0)
	self.favLabel.AutomaticSize = Enum.AutomaticSize.X
	self.favLabel.BackgroundTransparency = 1
	self.favLabel.Text = "Favorites"
	self.favLabel.TextColor3 = Colors.UI.TEXT
	self.favLabel.TextSize = 12
	self.favLabel.LayoutOrder = 1
	self.favLabel.Parent = favHeader
	self.starDropTarget = Instance.new("TextButton")
	self.starDropTarget.Size = UDim2.new(0, 28, 0, 28)
	self.starDropTarget.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.starDropTarget.BorderSizePixel = 0
	self.starDropTarget.Text = "⭐"
	self.starDropTarget.TextSize = 16
	self.starDropTarget.LayoutOrder = 2
	self.starDropTarget.Parent = favHeader
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.starDropTarget
	end
	self.favoritesListScroll = Instance.new("ScrollingFrame")
	self.favoritesListScroll.Size = UDim2.new(1, 0, 0, 0)
	self.favoritesListScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	self.favoritesListScroll.ScrollBarThickness = 4
	self.favoritesListScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	self.favoritesListScroll.BackgroundTransparency = 1
	self.favoritesListScroll.BorderSizePixel = 0
	self.favoritesListScroll.LayoutOrder = 2
	self.favoritesListScroll.Parent = self.favoritesSection
	self.favoritesListScroll.ScrollBarImageColor3 = Colors.UI.SCROLLBAR or Colors.UI.BORDER
	local favListContent = Instance.new("Frame")
	favListContent.Size = UDim2.new(1, 0, 0, 0)
	favListContent.AutomaticSize = Enum.AutomaticSize.Y
	favListContent.BackgroundTransparency = 1
	favListContent.Parent = self.favoritesListScroll
	local favListLayout = Instance.new("UIListLayout")
	favListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	favListLayout.Padding = UDim.new(0, 2)
	favListLayout.Parent = favListContent
	favListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local cs = favListLayout.AbsoluteContentSize
		self.favoritesListScroll.CanvasSize = UDim2.new(0, cs.X, 0, cs.Y + 4)
	end)
	self.favoritesListContent = favListContent

	-- Objects section (height set by updateObjectsScrollSize to fill to bottom with padding)
	self.objectsScroll = Instance.new("ScrollingFrame")
	self.objectsScroll.Size = UDim2.new(1, 0, 0, 200)
	self.objectsScroll.Position = UDim2.new(0, 0, 0, 0)
	self.objectsScroll.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.objectsScroll.BorderSizePixel = 0
	self.objectsScroll.ScrollBarThickness = 6
	self.objectsScroll.ScrollBarImageColor3 = Colors.UI.SCROLLBAR or Colors.UI.BORDER
	self.objectsScroll.ScrollBarImageTransparency = 0
	self.objectsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	self.objectsScroll.AutomaticCanvasSize = Enum.AutomaticSize.XY
	self.objectsScroll.ScrollingDirection = Enum.ScrollingDirection.XY
	self.objectsScroll.LayoutOrder = 6
	self.objectsScroll.Parent = root
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.objectsScroll
	end
	local objListLayout = Instance.new("UIListLayout")
	objListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	objListLayout.Padding = UDim.new(0, 2)
	objListLayout.Parent = self.objectsScroll
	objListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		local cs = objListLayout.AbsoluteContentSize
		self.objectsScroll.CanvasSize = UDim2.new(0, cs.X, 0, cs.Y + 4)
	end)

	-- Apply tag to selection
	self.applyToSelectionBtn = Instance.new("TextButton")
	self.applyToSelectionBtn.Size = UDim2.new(0, 0, 1, 0)
	self.applyToSelectionBtn.AutomaticSize = Enum.AutomaticSize.X
	self.applyToSelectionBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.applyToSelectionBtn.BorderSizePixel = 0
	self.applyToSelectionBtn.Text = "Apply tag to selection"
	self.applyToSelectionBtn.TextColor3 = Colors.UI.TEXT_MUTED
	self.applyToSelectionBtn.TextSize = 12
	self.applyToSelectionBtn.LayoutOrder = 2
	self.applyToSelectionBtn.ZIndex = 10
	self.applyToSelectionBtn.Parent = self.filterActionsRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.applyToSelectionBtn
	end
	do
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 10)
		p.PaddingRight = UDim.new(0, 10)
		p.Parent = self.applyToSelectionBtn
	end

	-- Remove tag from selection
	self.removeFromSelectionBtn = Instance.new("TextButton")
	self.removeFromSelectionBtn.Size = UDim2.new(0, 0, 1, 0)
	self.removeFromSelectionBtn.AutomaticSize = Enum.AutomaticSize.X
	self.removeFromSelectionBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	self.removeFromSelectionBtn.BorderSizePixel = 0
	self.removeFromSelectionBtn.Text = "Remove tag from selection"
	self.removeFromSelectionBtn.TextColor3 = Colors.UI.TEXT_MUTED
	self.removeFromSelectionBtn.TextSize = 12
	self.removeFromSelectionBtn.LayoutOrder = 3
	self.removeFromSelectionBtn.ZIndex = 10
	self.removeFromSelectionBtn.Parent = self.filterActionsRow
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = self.removeFromSelectionBtn
	end
	do
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 10)
		p.PaddingRight = UDim.new(0, 10)
		p.Parent = self.removeFromSelectionBtn
	end

	self.objectsScroll.LayoutOrder = 6

	self:updateObjectsScrollSize()
	self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:updateObjectsScrollSize()
	end)
	self.filterActionsRow:GetPropertyChangedSignal("Visible"):Connect(function()
		self:updateObjectsScrollSize()
	end)

	self:refreshTags()
	self:refreshFavorites()
	self:refreshObjects()
	self:connectSignals()
	self:setupDragDrop()
	return root
end

function MainPanel:rebuild()
	if self.root and self.root.Parent then
		self.root:Destroy()
		self.root = nil
	end
	self:build()
end

function MainPanel:updateObjectsScrollSize()
	local root = self.root
	local ay = root.AbsoluteSize.Y
	if ay <= 0 then return end
	local topPx = 32 + 8 + 40 + 8 -- searchRow + padding + tagsScroll + padding
	if self.filterActionsRow.Visible then
		topPx = topPx + 28 + 8 -- filterActionsRow + padding
	else
		topPx = topPx + 8 -- padding only
	end
	if self.favoritesSection and self.favoritesSection.Visible then
		local favH = self.favoritesSection.AbsoluteSize.Y
		if favH > 0 then
			topPx = topPx + favH + 8
		end
	end
	local scrollHeight = ay - ROOT_PADDING * 2 - topPx - OBJECT_LIST_BOTTOM_PADDING
	self.objectsScroll.Size = UDim2.new(1, 0, 0, math.max(0, scrollHeight))
end

function MainPanel:connectSignals()
	-- Hierarchy changes: refresh list when instances are added/removed (debounced)
	local function scheduleHierarchyRefresh()
		self.hierarchyDebounceGen = (self.hierarchyDebounceGen or 0) + 1
		local gen = self.hierarchyDebounceGen
		task.delay(DEBOUNCE_HIERARCHY_MS / 1000, function()
			if self.hierarchyDebounceGen == gen then
				self:refreshObjects()
			end
		end)
	end
	game.DescendantAdded:Connect(scheduleHierarchyRefresh)
	game.DescendantRemoving:Connect(scheduleHierarchyRefresh)

	-- Periodic refresh: catch renames, reparents, and any other Explorer changes
	task.spawn(function()
		while true do
			task.wait(HIERARCHY_REFRESH_INTERVAL_SEC)
			self:refreshObjects()
		end
	end)

	-- Debounced search: use search delay from settings
	local function getSearchDelayMs()
		local plugin = self.tagManager and self.tagManager.plugin
		if not plugin then return DEFAULT_SEARCH_DELAY_MS end
		local v = plugin:GetSetting(SettingsKeys.SEARCH_DELAY_MS)
		local n = tonumber(v)
		if n and n >= SettingsKeys.SEARCH_DELAY_MIN and n <= SettingsKeys.SEARCH_DELAY_MAX then
			return n
		end
		return DEFAULT_SEARCH_DELAY_MS
	end
	self.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		self.searchQuery = self.searchBox.Text
		self.searchClearBtn.Visible = (self.searchBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "") ~= ""
		self.searchDebounceGen = (self.searchDebounceGen or 0) + 1
		local gen = self.searchDebounceGen
		task.delay(getSearchDelayMs() / 1000, function()
			if self.searchDebounceGen == gen then
				self:refreshObjects()
			end
		end)
	end)
	self.searchClearBtn.Activated:Connect(function()
		self.searchBox.Text = ""
		self.searchQuery = ""
		self.searchClearBtn.Visible = false
		self:refreshObjects()
	end)
	-- Enter key: refresh immediately
	self.searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			self.searchQuery = self.searchBox.Text
			self:refreshObjects()
		end
	end)

	self.addTagBtn.Activated:Connect(function()
		task.defer(function()
			createTagEditorDialog(self.widget, function(name, color, icon)
				self.tagManager:createTag(name, color, "", icon)
			end, self.tagManager, function()
				self:refreshTags()
				self:refreshObjects()
			end, self.tagsContainer)
		end)
	end)

	if self.settingsBtn then
		self.settingsBtn.Activated:Connect(function()
			local plugin = self.tagManager and self.tagManager.plugin
			if plugin then
				createSettingsDialog(self.widget, plugin, function()
					self:rebuild()
				end, function(key)
					if key == "ColorCoding" then
						self:refreshTags()
						self:refreshObjects()
					end
				end)
			end
		end)
	end

	-- Search tags by name: filter tag chips as user types
	self.tagFilterBox:GetPropertyChangedSignal("Text"):Connect(function()
		self.tagFilterQuery = self.tagFilterBox.Text
		self.tagFilterClearBtn.Visible = (self.tagFilterBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "") ~= ""
		self:refreshTags()
	end)
	self.tagFilterClearBtn.Activated:Connect(function()
		self.tagFilterBox.Text = ""
		self.tagFilterQuery = ""
		self.tagFilterClearBtn.Visible = false
		self:refreshTags()
	end)

	self.clearFilterBtn.Activated:Connect(function()
		self.activeFilterTagId = nil
		self.filterActionsRow.Visible = false
		self.clearFilterBtn.Visible = false
		self.applyToSelectionBtn.Visible = false
		if self.removeFromSelectionBtn then
			self.removeFromSelectionBtn.Visible = false
		end
		self:refreshTags()
		self:refreshObjects()
	end)

	self.applyToSelectionBtn.Activated:Connect(function()
		if not self.activeFilterTagId then return end
		local selection = Selection:Get()
		for _, obj in ipairs(selection) do
			self.tagManager:addTagToObject(obj, self.activeFilterTagId)
		end
		self:refreshTags()
		self:refreshObjects()
	end)

	self.removeFromSelectionBtn.Activated:Connect(function()
		if not self.activeFilterTagId then return end
		local selection = Selection:Get()
		for _, obj in ipairs(selection) do
			self.tagManager:removeTagFromObject(obj, self.activeFilterTagId)
		end
		self:refreshTags()
		self:refreshObjects()
	end)
end

function MainPanel:refreshTags()
	self.tagManager:discoverTagsFromPlace()
	self._chipToTag = {}
	for _, child in ipairs(self.tagsContainer:GetChildren()) do
		if child:IsA("Frame") and child ~= self.tagFilterRow then
			child:Destroy()
		end
	end
	local allTags = self.tagManager:getAllTags()
	local query = (self.tagFilterQuery or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
	local tags
	if query == "" then
		tags = allTags
	else
		tags = {}
		for _, tag in ipairs(allTags) do
			if (tag.name or ""):lower():find(query, 1, true) then
				table.insert(tags, tag)
			end
		end
	end
	local colorCodingEnabled = true
	local dragDropEnabled = true
	local plugin = self.tagManager and self.tagManager.plugin
	if plugin then
		if plugin:GetSetting(SettingsKeys.COLOR_CODING) == "false" then colorCodingEnabled = false end
		if plugin:GetSetting(SettingsKeys.DRAG_DROP) == "false" then dragDropEnabled = false end
	end
	for i, tag in ipairs(tags) do
		local isActive = (self.activeFilterTagId == tag.id)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(0, 0, 0, 28)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.LayoutOrder = i + 1
		row.Parent = self.tagsContainer
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding = UDim.new(0, 2)
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Parent = row
		local chipOptions = {
			widget = self.widget,
			colorCodingEnabled = colorCodingEnabled,
		}
		if dragDropEnabled then
			chipOptions.onDragStart = function(tagData, onDragEndCallback, sourceButton)
				self:_onTagDragStart(tagData, onDragEndCallback, sourceButton)
			end
		end
		local chip = createTagChip(tag, function()
			self.activeFilterTagId = tag.id
			self.filterActionsRow.Visible = true
			self.clearFilterBtn.Visible = true
			self.applyToSelectionBtn.Visible = true
			self.removeFromSelectionBtn.Visible = true
			self:refreshTags()
			self:refreshObjects()
		end, isActive, chipOptions)
		chip.Size = UDim2.new(0, 0, 0, 28)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.Parent = row
		self._chipToTag[chip] = tag
	end
	-- Keep filter/selection buttons visible when a tag is selected (e.g. after rebuild)
	if self.activeFilterTagId then
		self.filterActionsRow.Visible = true
		self.clearFilterBtn.Visible = true
		self.applyToSelectionBtn.Visible = true
		self.removeFromSelectionBtn.Visible = true
	end
end

function MainPanel:refreshFavorites()
	if not self.favoritesManager or not self.favoritesListContent then return end
	for _, child in ipairs(self.favoritesListContent:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	local list = self.favoritesManager:getFavorites()
	if self.favLabel then
		self.favLabel.Text = #list > 0 and ("Favorites (" .. #list .. ")") or "Favorites"
	end
	-- Size the scroll frame by content: 0–4 rows = exact height, 5+ = max height with scroll
	local n = 0
	for _, obj in ipairs(list) do
		if obj.Parent then n = n + 1 end
	end
	local rowH, gap, maxH = self._FAV_ROW_H or 22, self._FAV_ROW_GAP or 2, self._FAV_LIST_MAX_H or 94
	local listHeight = (n == 0) and 0 or math.min(n * rowH + (n - 1) * gap, maxH)
	if self.favoritesListScroll then
		self.favoritesListScroll.Size = UDim2.new(1, 0, 0, listHeight)
	end
	local order = 0
	for _, obj in ipairs(list) do
		if not obj.Parent then continue end -- skip destroyed (Lua 5.4+ has continue; for 5.1 use next)
		order = order + 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Parent = self.favoritesListContent
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.Padding = UDim.new(0, 4)
		rowLayout.Parent = row
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -30, 1, 0)
		btn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		btn.BorderSizePixel = 0
		btn.Text = obj.Name
		btn.TextColor3 = Colors.UI.TEXT
		btn.TextSize = 12
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.TextTruncate = Enum.TextTruncate.AtEnd
		btn.LayoutOrder = 1
		btn.Parent = row
		do
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, 6)
			p.PaddingRight = UDim.new(0, 6)
			p.Parent = btn
		end
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = btn
		end
		btn.Activated:Connect(function()
			Selection:Set({ obj })
		end)
		local removeBtn = Instance.new("TextButton")
		removeBtn.Size = UDim2.new(0, 22, 0, 22)
		removeBtn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
		removeBtn.BorderSizePixel = 0
		removeBtn.Text = "×"
		removeBtn.TextColor3 = Colors.UI.ERROR
		removeBtn.TextSize = 16
		removeBtn.Font = Enum.Font.GothamBold
		removeBtn.LayoutOrder = 2
		removeBtn.Parent = row
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = removeBtn
		end
		removeBtn.Activated:Connect(function()
			self.favoritesManager:removeFavorite(obj)
			self._favoritesVersion = (self._favoritesVersion or 0) + 1
			self:refreshFavorites()
			self:refreshObjects()
			task.defer(function() self:updateObjectsScrollSize() end)
		end)
	end
	task.defer(function() self:updateObjectsScrollSize() end)
end

-- Build tree from flat list of Instances: parent in set or game. All nodes expanded, childrenLoaded.
local function buildFilteredTree(objects)
	local set = {}
	for _, obj in ipairs(objects) do set[obj] = true end
	local nodes = {}
	for _, obj in ipairs(objects) do
		nodes[obj] = {
			object = obj,
			depth = 0,
			children = {},
			expanded = true,
			childrenLoaded = true,
		}
	end
	local roots = {}
	for _, obj in ipairs(objects) do
		local node = nodes[obj]
		local p = obj.Parent
		while p and p ~= game do
			if set[p] then
				table.insert(nodes[p].children, node)
				node.depth = nodes[p].depth + 1
				break
			end
			p = p.Parent
		end
		if not p or p == game then
			table.insert(roots, node)
		end
	end
	table.sort(roots, function(a, b) return a.object.Name < b.object.Name end)
	for _, obj in ipairs(objects) do
		table.sort(nodes[obj].children, function(a, b) return a.object.Name < b.object.Name end)
	end
	return roots
end

-- Wrap Instance in tree node: { object, depth, children, expanded, childrenLoaded }
local function newNode(inst, depth)
	return {
		object = inst,
		depth = depth or 0,
		children = {},
		expanded = false,
		childrenLoaded = false,
	}
end

-- Build one tree node and restore expanded state: pre-load children if instance is in expandedPaths.
local function buildNodeWithExpanded(inst, depth, expandedPaths, getChildren)
	local node = newNode(inst, depth)
	if expandedPaths[inst] then
		node.expanded = true
		node.childrenLoaded = true
		local rawChildren = getChildren({ object = inst })
		for _, ch in ipairs(rawChildren) do
			if ch and ch.Parent then
				table.insert(node.children, buildNodeWithExpanded(ch, depth + 1, expandedPaths, getChildren))
			end
		end
	end
	return node
end

function MainPanel:refreshObjects()
	local objects = {}
	local searchTrimmed = self.searchQuery and self.searchQuery:gsub("%s", "") or ""

	if self.activeFilterTagId then
		objects = self.tagManager:getObjectsWithTag(self.activeFilterTagId)
		if searchTrimmed ~= "" then
			local filtered = {}
			local q = self.searchQuery:lower()
			for _, obj in ipairs(objects) do
				if obj.Name:lower():find(q, 1, true) then
					table.insert(filtered, obj)
				end
			end
			objects = filtered
		end
	elseif searchTrimmed ~= "" then
		local results = self.searchEngine:search(self.searchQuery)
		for _, r in ipairs(results) do
			table.insert(objects, r.object)
		end
	else
		-- Unfiltered: only roots (game's children); all collapsed, lazy children
		objects = nil
	end

	local roots
	local getChildren
	local totalCount
	local maxShown = MAX_OBJECTS_DISPLAY

	if not objects then
		-- Unfiltered: roots = game:GetChildren(), restore expanded state from expandedPaths
		local topLevel = game:GetChildren()
		getChildren = function(node)
			return node.object:GetChildren()
		end
		roots = {}
		for _, inst in ipairs(topLevel) do
			table.insert(roots, buildNodeWithExpanded(inst, 0, self.expandedPaths, getChildren))
		end
		totalCount = 0
	else
		-- Filtered (tag or search): full tree of matches, all expanded
		roots = buildFilteredTree(objects)
		getChildren = function(node)
			local out = {}
			for _, ch in ipairs(node.children) do
				table.insert(out, ch.object)
			end
			return out
		end
		totalCount = #objects
	end

	local colorCodingEnabled = true
	local plugin = self.tagManager and self.tagManager.plugin
	if plugin and plugin:GetSetting(SettingsKeys.COLOR_CODING) == "false" then
		colorCodingEnabled = false
	end
	self._rowToObject = {}
	ObjectList.updateTreeList(self.objectsScroll, roots, getChildren, {
		tagManager = self.tagManager,
		colorCodingEnabled = colorCodingEnabled,
		favoritesManager = self.favoritesManager,
		favoritesVersion = self._favoritesVersion or 0,
		onFavoritesChanged = function()
			self._favoritesVersion = (self._favoritesVersion or 0) + 1
			self:refreshFavorites()
			self:refreshObjects()
			task.defer(function() self:updateObjectsScrollSize() end)
		end,
		onSelect = nil,
		totalCount = totalCount,
		maxShown = maxShown,
		onExpandChanged = function(node, isExpanded)
			if node and node.object then
				if isExpanded then
					self.expandedPaths[node.object] = true
				else
					self.expandedPaths[node.object] = nil
				end
			end
		end,
		onRowCreated = function(rowGui, obj)
			self._rowToObject[rowGui] = obj
			-- Detect "release over this row" when dragging a tag (InputEnded fires on the row under cursor)
			rowGui.InputEnded:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				if self._draggingTag then
					self:_finishTagDrag(obj)
				end
			end)
		end,
	})
end

-- Hit-test: (x, y) are widget-relative (e.g. from GetRelativeMousePosition). Convert element AbsolutePosition to widget-relative.
function MainPanel:_getTagChipAtPosition(x, y)
	local wx, wy = self.widget.AbsolutePosition.X, self.widget.AbsolutePosition.Y
	for chip, tag in pairs(self._chipToTag) do
		if chip.Parent and chip:IsDescendantOf(self.widget) then
			local ax, ay = chip.AbsolutePosition.X - wx, chip.AbsolutePosition.Y - wy
			local aw, ah = chip.AbsoluteSize.X, chip.AbsoluteSize.Y
			if x >= ax and x <= ax + aw and y >= ay and y <= ay + ah then
				return tag
			end
		end
	end
	return nil
end

-- Hit-test: (x, y) widget-relative. True if over the star (favorites) drop target.
function MainPanel:_isPointOverStarDropTarget(x, y)
	if not self.starDropTarget or not self.starDropTarget.Parent then return false end
	local wx, wy = self.widget.AbsolutePosition.X, self.widget.AbsolutePosition.Y
	local ax, ay = self.starDropTarget.AbsolutePosition.X - wx, self.starDropTarget.AbsolutePosition.Y - wy
	local aw, ah = self.starDropTarget.AbsoluteSize.X, self.starDropTarget.AbsoluteSize.Y
	return x >= ax and x <= ax + aw and y >= ay and y <= ay + ah
end

-- Hit-test: (x, y) widget-relative. Return the Instance for the object list row at that position, or nil.
function MainPanel:_getObjectAtPosition(x, y)
	local wx, wy = self.widget.AbsolutePosition.X, self.widget.AbsolutePosition.Y
	for row, obj in pairs(self._rowToObject) do
		if row.Parent and row:IsDescendantOf(self.widget) then
			local ax, ay = row.AbsolutePosition.X - wx, row.AbsolutePosition.Y - wy
			local aw, ah = row.AbsoluteSize.X, row.AbsoluteSize.Y
			if x >= ax and x <= ax + aw and y >= ay and y <= ay + ah then
				return obj
			end
		end
	end
	return nil
end

-- True if (x, y) in widget-relative coords is inside the object list ScrollingFrame.
function MainPanel:_isPointInObjectList(x, y)
	if not self.objectsScroll then return false end
	local wx, wy = self.widget.AbsolutePosition.X, self.widget.AbsolutePosition.Y
	local sx, sy = self.objectsScroll.AbsolutePosition.X - wx, self.objectsScroll.AbsolutePosition.Y - wy
	local sw, sh = self.objectsScroll.AbsoluteSize.X, self.objectsScroll.AbsoluteSize.Y
	return x >= sx and x <= sx + sw and y >= sy and y <= sy + sh
end

-- Set star drop target highlighted (true) or normal (false)
function MainPanel:_setStarDropHighlight(highlighted)
	if not self.starDropTarget then return end
	self.starDropTarget.BackgroundColor3 = highlighted and DROP_TARGET_HIGHLIGHT or Colors.UI.BACKGROUND_LIGHT
end

-- Set which tag chip is the drop target (highlight); pass nil to clear
function MainPanel:_setDropTargetChip(chip)
	if self._dropTargetChip == chip then return end
	if self._dropTargetChip then
		local s = self._dropTargetChip:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Color3.new(1, 1, 1)
			s.Thickness = (self._dropTargetChip:GetAttribute("IsActive") and 3 or 0)
		end
	end
	self:_setStarDropHighlight(false)
	self._dropTargetChip = chip
	if chip then
		local s = chip:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = DROP_TARGET_HIGHLIGHT
			s.Thickness = 2
		end
	end
end

-- Extract Instance array from PluginGui dragData (Explorer drag).
-- Studio passes keys like Data, DragIcon, HotSpot, MimeType, MouseIcon, Sender; instances are in Data.
local function extractInstancesFromDragData(dragData)
	if type(dragData) ~= "table" then return {} end
	local function collectFromList(list)
		if type(list) ~= "table" then return {} end
		local out = {}
		for _, v in ipairs(list) do
			if typeof(v) == "Instance" and v.Parent then
				table.insert(out, v)
			end
		end
		return out
	end
	-- Try top-level keys
	local list = dragData.Instances or dragData.instances or dragData.Payload or dragData.Items or dragData.objects
	local out = collectFromList(list)
	if #out > 0 then return out end
	-- Studio Explorer drag: payload is in dragData.Data (may be array of Instances or table with Instances)
	local data = dragData.Data
	if type(data) == "table" then
		out = collectFromList(data.Instances or data.instances or data)
		if #out > 0 then return out end
		-- Data might be the array itself
		for _, item in ipairs(data) do
			if typeof(item) == "Instance" and item.Parent then
				table.insert(out, item)
			end
		end
		if #out > 0 then return out end
	elseif typeof(data) == "Instance" and data.Parent then
		return { data }
	end
	-- Fallback: any table value that is an array of Instances
	for _, v in pairs(dragData) do
		if type(v) == "table" and v ~= data then
			out = collectFromList(v)
			if #out > 0 then return out end
		end
	end
	return {}
end

-- Called when tag drag ends (release or timeout). overrideObj = optional Instance to tag (e.g. row under cursor); otherwise use position + selection.
function MainPanel:_finishTagDrag(overrideObj)
	if not self._draggingTag then return end
	local tagToApply = self._draggingTag
	self._draggingTag = nil
	if self._dragPreview and self._dragPreview.Parent then self._dragPreview:Destroy() end
	self._dragPreview = nil
	if self._dragEndConnection then self._dragEndConnection:Disconnect() self._dragEndConnection = nil end
	if self._dragInputEndConnection then self._dragInputEndConnection:Disconnect() self._dragInputEndConnection = nil end
	if self._dragWidgetMouseUpConnection then self._dragWidgetMouseUpConnection:Disconnect() self._dragWidgetMouseUpConnection = nil end
	if self._dragScrollMouseUpConnection then self._dragScrollMouseUpConnection:Disconnect() self._dragScrollMouseUpConnection = nil end
	if self._dragSourceButtonConnection then self._dragSourceButtonConnection:Disconnect() self._dragSourceButtonConnection = nil end
	if type(self._draggingTagEndCallback) == "function" then self._draggingTagEndCallback() self._draggingTagEndCallback = nil end
	local scroll, oldBg = self._dragScroll, self._dragOldBg
	if scroll and oldBg then scroll.BackgroundColor3 = oldBg end
	local toTag = {}
	if overrideObj and typeof(overrideObj) == "Instance" and overrideObj.Parent then
		toTag = { overrideObj }
	else
		-- Use last position from drag (Heartbeat) so we hit-test where the cursor was when user released, not chip/release-event position
		local pos = self._lastDragMousePos or self.widget:GetRelativeMousePosition()
		self._lastDragMousePos = nil
		local obj = self:_getObjectAtPosition(pos.X, pos.Y)
		local inList = self:_isPointInObjectList(pos.X, pos.Y)
		if obj then
			toTag = { obj }
		elseif inList then
			-- Only use Selection when drop was inside the object list (not when releasing over tags area or elsewhere)
			for _, o in ipairs(Selection:Get()) do
				if typeof(o) == "Instance" and o.Parent then table.insert(toTag, o) end
			end
		end
		-- If release was outside object list, toTag stays empty (no tag applied)
	end
	for _, o in ipairs(toTag) do
		self.tagManager:addTagToObject(o, tagToApply.id)
	end
	if #toTag > 0 then
		self:refreshTags()
		self:refreshObjects()
	end
end

function MainPanel:_cancelTagDrag()
	if not self._draggingTag then return end
	self._draggingTag = nil
	self._lastDragMousePos = nil
	if self._dragPreview and self._dragPreview.Parent then self._dragPreview:Destroy() end
	self._dragPreview = nil
	if self._dragEndConnection then self._dragEndConnection:Disconnect() self._dragEndConnection = nil end
	if self._dragInputEndConnection then self._dragInputEndConnection:Disconnect() self._dragInputEndConnection = nil end
	if self._dragWidgetMouseUpConnection then self._dragWidgetMouseUpConnection:Disconnect() self._dragWidgetMouseUpConnection = nil end
	if self._dragScrollMouseUpConnection then self._dragScrollMouseUpConnection:Disconnect() self._dragScrollMouseUpConnection = nil end
	if self._dragSourceButtonConnection then self._dragSourceButtonConnection:Disconnect() self._dragSourceButtonConnection = nil end
	if type(self._draggingTagEndCallback) == "function" then self._draggingTagEndCallback() self._draggingTagEndCallback = nil end
	local scroll, oldBg = self._dragScroll, self._dragOldBg
	if scroll and oldBg then scroll.BackgroundColor3 = oldBg end
end

function MainPanel:_onTagDragStart(tag, onDragEndCallback, sourceButton)
	self._draggingTag = tag
	self._draggingTagEndCallback = onDragEndCallback
	local scroll = self.objectsScroll
	local oldBg = scroll and scroll.BackgroundColor3
	self._dragScroll = scroll
	self._dragOldBg = oldBg
	if scroll then
		scroll.BackgroundColor3 = Colors.UI.BORDER
	end
	-- Drag preview: colored circle that follows the mouse; track last position for hit-test on release
	local pos0 = self.widget:GetRelativeMousePosition()
	self._lastDragMousePos = pos0
	local preview = Instance.new("Frame")
	preview.Size = UDim2.new(0, 28, 0, 28)
	preview.Position = UDim2.new(0, pos0.X, 0, pos0.Y)
	preview.AnchorPoint = Vector2.new(0.5, 0.5)
	preview.BackgroundColor3 = tag.color or Color3.new(0.5, 0.5, 0.5)
	preview.BorderSizePixel = 0
	preview.ZIndex = 1000
	preview.Parent = self.widget
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = preview
	self._dragPreview = preview
	-- Release on the preview (it follows the cursor; may not receive event if press started elsewhere)
	preview.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if self._draggingTag then
			self:_finishTagDrag()
		end
	end)
	-- Primary: the chip button that was pressed receives InputEnded when user releases (anywhere).
	-- Defer so cursor position is the release position when we hit-test (otherwise we may get chip position and miss the row).
	if sourceButton and sourceButton.InputEnded then
		if self._dragSourceButtonConnection then self._dragSourceButtonConnection:Disconnect() end
		self._dragSourceButtonConnection = sourceButton.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if self._draggingTag then
				task.defer(function()
					if self._draggingTag then
						self:_finishTagDrag()
					end
				end)
			end
		end)
	end
	local DRAG_RELEASE_GRACE_SEC = 0.15
	local DRAG_CANCEL_TIMEOUT_SEC = 12
	self._dragMousePressed = true
	self._dragStartTime = tick()
	self._dragSawPressedAfterGrace = false
	-- Primary: GuiObject.InputEnded on the root Frame (Frame has InputEnded, not MouseButton1Up)
	if self._dragWidgetMouseUpConnection then self._dragWidgetMouseUpConnection:Disconnect() end
	self._dragWidgetMouseUpConnection = self.root.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if self._draggingTag then
			self:_finishTagDrag()
		end
	end)
	-- Release over object list (background or non-row area)
	if self.objectsScroll then
		self._dragScrollMouseUpConnection = self.objectsScroll.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if self._draggingTag then
				self:_finishTagDrag()
			end
		end)
	end
	-- Fallback: InputEnded
	if self._dragInputEndConnection then self._dragInputEndConnection:Disconnect() end
	self._dragInputEndConnection = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if self._draggingTag then
			self:_finishTagDrag()
		end
	end)
	-- Fallback: Heartbeat only treats "not pressed" as release if we've seen "pressed" at least once after grace (avoids false drop when IsMouseButtonPressed never returns true over PluginGui)
	if self._dragEndConnection then self._dragEndConnection:Disconnect() end
	self._dragEndConnection = RunService.Heartbeat:Connect(function()
		if not self._draggingTag then
			if self._dragPreview and self._dragPreview.Parent then self._dragPreview:Destroy() end
			self._dragPreview = nil
			if self._dragEndConnection then self._dragEndConnection:Disconnect() self._dragEndConnection = nil end
			if self._dragInputEndConnection then self._dragInputEndConnection:Disconnect() self._dragInputEndConnection = nil end
			if self._dragWidgetMouseUpConnection then self._dragWidgetMouseUpConnection:Disconnect() self._dragWidgetMouseUpConnection = nil end
			if self._dragScrollMouseUpConnection then self._dragScrollMouseUpConnection:Disconnect() self._dragScrollMouseUpConnection = nil end
			if self._dragSourceButtonConnection then self._dragSourceButtonConnection:Disconnect() self._dragSourceButtonConnection = nil end
			return
		end
		if self._dragPreview and self._dragPreview.Parent then
			local pos = self.widget:GetRelativeMousePosition()
			self._lastDragMousePos = pos
			self._dragPreview.Position = UDim2.new(0, pos.X, 0, pos.Y)
		end
		local elapsed = tick() - self._dragStartTime
		local pressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		if pressed and elapsed >= DRAG_RELEASE_GRACE_SEC then
			self._dragSawPressedAfterGrace = true
		end
		if pressed then
			self._dragMousePressed = true
			return
		end
		if not self._dragMousePressed then return end
		-- Only treat as release in Heartbeat if we've seen "pressed" after grace (so we know the API is reporting state)
		if not self._dragSawPressedAfterGrace then
			if elapsed >= DRAG_CANCEL_TIMEOUT_SEC then
				self:_cancelTagDrag()
			end
			return
		end
		if elapsed < DRAG_RELEASE_GRACE_SEC then return end
		self._dragMousePressed = false
		self:_finishTagDrag()
	end)
end

function MainPanel:setupDragDrop()
	local widget = self.widget
	if not widget then return end
	-- Disconnect any existing plugin drag connections (e.g. from previous build or when setting was on)
	if self._pluginDragConnections then
		for _, conn in ipairs(self._pluginDragConnections) do
			if conn and conn.Connected then conn:Disconnect() end
		end
		self._pluginDragConnections = {}
	end
	local plugin = self.tagManager and self.tagManager.plugin
	if plugin and plugin:GetSetting(SettingsKeys.DRAG_DROP) == "false" then
		return
	end

	self._pluginDragConnections = self._pluginDragConnections or {}
	-- Explorer -> tag: drop on tag chip
	if widget.PluginDragEntered then
		table.insert(self._pluginDragConnections, widget.PluginDragEntered:Connect(function() end))
	end
	if widget.PluginDragMoved then
		table.insert(self._pluginDragConnections, widget.PluginDragMoved:Connect(function(dragData)
			local pos = self.widget:GetRelativeMousePosition()
			if self:_isPointOverStarDropTarget(pos.X, pos.Y) then
				self:_setDropTargetChip(nil)
				self:_setStarDropHighlight(true)
			else
				self:_setStarDropHighlight(false)
				local tag = self:_getTagChipAtPosition(pos.X, pos.Y)
				local chip = nil
				if tag then
					for c, t in pairs(self._chipToTag) do
						if t.id == tag.id then chip = c break end
					end
				end
				self:_setDropTargetChip(chip)
			end
		end))
	end
	if widget.PluginDragLeft then
		table.insert(self._pluginDragConnections, widget.PluginDragLeft:Connect(function()
			self:_setDropTargetChip(nil)
			self:_setStarDropHighlight(false)
		end))
	end
	if widget.PluginDragDropped then
		table.insert(self._pluginDragConnections, widget.PluginDragDropped:Connect(function(dragData)
			self:_setDropTargetChip(nil)
			self:_setStarDropHighlight(false)
			local pos = self.widget:GetRelativeMousePosition()
			local instances = extractInstancesFromDragData(dragData)
			-- Drop on star = add to favorites
			if self:_isPointOverStarDropTarget(pos.X, pos.Y) then
				if self.favoritesManager and #instances > 0 then
					self.favoritesManager:addFavorites(instances)
					self._favoritesVersion = (self._favoritesVersion or 0) + 1
					self:refreshFavorites()
					self:refreshObjects()
					task.defer(function() self:updateObjectsScrollSize() end)
				elseif self.favoritesManager and #instances == 0 then
					for _, obj in ipairs(Selection:Get()) do
						if typeof(obj) == "Instance" and obj.Parent then
							self.favoritesManager:addFavorite(obj)
						end
					end
					self._favoritesVersion = (self._favoritesVersion or 0) + 1
					self:refreshFavorites()
					self:refreshObjects()
					task.defer(function() self:updateObjectsScrollSize() end)
				end
				return
			end
			if #instances == 0 then
				local tag = self:_getTagChipAtPosition(pos.X, pos.Y)
				if not tag then return end
				for _, obj in ipairs(Selection:Get()) do
					if typeof(obj) == "Instance" and obj.Parent then
						self.tagManager:addTagToObject(obj, tag.id)
					end
				end
				self:refreshTags()
				self:refreshObjects()
				return
			end
			local tag = self:_getTagChipAtPosition(pos.X, pos.Y)
			if not tag then return end
			for _, obj in ipairs(instances) do
				self.tagManager:addTagToObject(obj, tag.id)
			end
			self:refreshTags()
			self:refreshObjects()
		end))
	end
end

return MainPanel
