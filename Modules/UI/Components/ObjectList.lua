--[[
	UI/Components/ObjectList.lua
	Hierarchical tree list: expand/collapse, lazy children, click to select in Studio.
]]

local Selection = game:GetService("Selection")
local Colors = require(script.Parent.Parent.Parent.Utils.Colors)

local ROW_HEIGHT = 24
local INDENT_PX = 14
local BATCH_SIZE = 50
local MAX_VISIBLE_TREE_ROWS = 2000
local DOTS_AREA_WIDTH = 80
local DOT_SIZE = 12
local DOT_PADDING = 4
-- When more than MAX_VISIBLE_DOTS tags, show MAX_VISIBLE_DOTS - 1 colored dots + one "+N" overflow hint
local MAX_VISIBLE_DOTS = 5
local MAX_TAG_DOTS_BEFORE_OVERFLOW = MAX_VISIBLE_DOTS - 1  -- 4 colored circles, 5th slot = hint

-- Tag tooltip (hover over dots): chip list
local TOOLTIP_CHIP_HEIGHT = 20
local TOOLTIP_CHIP_PADDING_H = 8
local TOOLTIP_CHIP_GAP = 4
local TOOLTIP_PADDING = 6
local TOOLTIP_OFFSET_ABOVE = 4

-- Per-scrollFrame state for stable refresh (last signature + scroll position) and tag tooltip.
local stateByScroll = {}

-- Tree node: { object, depth, children = {}, expanded, childrenLoaded }
local function newNode(instance, depth)
	return {
		object = instance,
		depth = depth or 0,
		children = {},
		expanded = false,
		childrenLoaded = false,
	}
end

-- Build visible (node, depth) list in display order; respects expanded state.
local function buildVisibleList(roots, getChildren, maxRows)
	local out = {}
	local function add(node, depth)
		if #out >= maxRows then return end
		table.insert(out, { node = node, depth = depth })
		if node.expanded then
			for _, ch in ipairs(node.children) do
				add(ch, depth + 1)
			end
		end
	end
	for _, root in ipairs(roots) do
		add(root, root.depth or 0)
	end
	return out
end

local function getTagNames(obj, tagManager)
	if not tagManager then return nil end
	-- getTagsForObject returns tag names (strings) from CollectionService
	local tagNames = tagManager:getTagsForObject(obj)
	if not tagNames or #tagNames == 0 then return nil end
	return tagNames
end

-- Stable path for signature (nil if instance gone)
local function getInstancePath(inst)
	if not inst or not inst.Parent then return nil end
	local ok, path = pcall(function()
		return inst:GetFullName()
	end)
	return ok and path or nil
end

-- Signature includes instance identity so same-name instances are distinguished
local function buildSignature(visible)
	local sig = {}
	for _, entry in ipairs(visible) do
		local path = getInstancePath(entry.node.object)
		local key = (path or "") .. "\0" .. tostring(entry.node.object)
		table.insert(sig, { path = key, depth = entry.depth })
	end
	return sig
end

local function signaturesEqual(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i].path ~= b[i].path or a[i].depth ~= b[i].depth then return false end
	end
	return true
end

-- Fill a container with color dots (one per tag). Uses tagManager:getTag(tagName).color. Clears existing children first.
-- When colorCodingEnabled is false, all dots use TEXT_MUTED. When more than MAX_TAG_DOTS_BEFORE_OVERFLOW tags, shows 4 dots + "+N".
local function fillTagColorDots(container, tagNames, tagManager, colorCodingEnabled)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
	if not tagManager or not tagNames or #tagNames == 0 then return end
	local layout = container:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, DOT_PADDING)
		layout.Parent = container
	end
	local showOverflow = #tagNames > MAX_TAG_DOTS_BEFORE_OVERFLOW
	local numDots = showOverflow and MAX_TAG_DOTS_BEFORE_OVERFLOW or #tagNames
	for i = 1, numDots do
		local tagName = tagNames[i]
		local tag = tagManager:getTag(tagName)
		local color = (colorCodingEnabled ~= false and tag and tag.color) and tag.color or Colors.UI.TEXT_MUTED
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.Parent = container
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
	end
	if showOverflow then
		local hint = Instance.new("Frame")
		hint.Name = "OverflowHint"
		hint.Size = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
		hint.BackgroundColor3 = Colors.UI.BORDER
		hint.BorderSizePixel = 0
		hint.Parent = container
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = hint
		end
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = "+"
		label.TextColor3 = Colors.UI.TEXT_MUTED
		label.TextSize = 12
		label.Font = Enum.Font.GothamBold
		label.Parent = hint
	end
end

-- Get or create the shared tag tooltip for a scroll frame. Parented to a zero-size overlay so it doesn't affect root layout.
local function getOrCreateTagTooltip(scrollFrame)
	local state = stateByScroll[scrollFrame]
	if not state then
		state = {}
		stateByScroll[scrollFrame] = state
	end
	if state.tagTooltip then return state.tagTooltip end
	local root = scrollFrame.Parent
	if not root then return nil end
	-- Overlay: zero size, high LayoutOrder so it doesn't push content; tooltip is positioned inside it.
	local overlay = Instance.new("Frame")
	overlay.Name = "ObjectListTagTooltipOverlay"
	overlay.Size = UDim2.new(0, 0, 0, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ClipsDescendants = false
	overlay.LayoutOrder = 99999
	overlay.ZIndex = 99
	overlay.Parent = root
	state.tagTooltipOverlay = overlay
	local tooltip = Instance.new("Frame")
	tooltip.Name = "ObjectListTagTooltip"
	tooltip.BackgroundTransparency = 1
	tooltip.BorderSizePixel = 0
	tooltip.Size = UDim2.new(0, 0, 0, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.XY
	tooltip.Visible = false
	tooltip.ZIndex = 100
	tooltip.ClipsDescendants = false
	tooltip.Parent = overlay
	do
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, TOOLTIP_PADDING)
		p.PaddingRight = UDim.new(0, TOOLTIP_PADDING)
		p.PaddingTop = UDim.new(0, TOOLTIP_PADDING)
		p.PaddingBottom = UDim.new(0, TOOLTIP_PADDING)
		p.Parent = tooltip
	end
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Padding = UDim.new(0, TOOLTIP_CHIP_GAP)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = tooltip
	state.tagTooltip = tooltip
	return tooltip
end

-- Fill tooltip with tag chips (colored + name), then position above the anchor and show.
-- tagNames can be an array or a function that returns the current array (so tooltip stays up to date after tag changes).
local function showTagTooltip(tooltip, tagNamesOrGetter, tagManager, anchor)
	if not tooltip or not anchor then return end
	local tagNames = type(tagNamesOrGetter) == "function" and tagNamesOrGetter() or tagNamesOrGetter
	if not tagNames or #tagNames == 0 then return end
	for _, c in ipairs(tooltip:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	for i, tagName in ipairs(tagNames) do
		local tag = tagManager and tagManager:getTag(tagName)
		local color = tag and tag.color or Colors.UI.TEXT_MUTED
		local chip = Instance.new("Frame")
		chip.Size = UDim2.new(0, 0, 0, TOOLTIP_CHIP_HEIGHT)
		chip.AutomaticSize = Enum.AutomaticSize.X
		chip.BackgroundColor3 = color
		chip.BorderSizePixel = 0
		chip.LayoutOrder = i
		chip.ZIndex = 101
		chip.Parent = tooltip
		do
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 4)
			c.Parent = chip
		end
		do
			local p = Instance.new("UIPadding")
			p.PaddingLeft = UDim.new(0, TOOLTIP_CHIP_PADDING_H)
			p.PaddingRight = UDim.new(0, TOOLTIP_CHIP_PADDING_H)
			p.Parent = chip
		end
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, 0, 1, 0)
		label.AutomaticSize = Enum.AutomaticSize.X
		label.BackgroundTransparency = 1
		label.Text = tagName
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = 12
		label.Font = Enum.Font.Gotham
		label.ZIndex = 101
		label.Parent = chip
	end
	tooltip.Visible = true
	task.defer(function()
		if not tooltip.Parent or not anchor.Parent then return end
		local overlay = tooltip.Parent
		local root = overlay.Parent
		if not root then return end
		local ax, ay = anchor.AbsolutePosition.X, anchor.AbsolutePosition.Y
		local ah = anchor.AbsoluteSize.Y
		local ox, oy = overlay.AbsolutePosition.X, overlay.AbsolutePosition.Y
		local tw, th = tooltip.AbsoluteSize.X, tooltip.AbsoluteSize.Y
		local rootMidY = root.AbsolutePosition.Y + root.AbsoluteSize.Y * 0.5
		local anchorCenterY = ay + ah * 0.5
		-- Above middle of addon → show below anchor, stack downward; else show above, stack upward
		local showBelow = anchorCenterY < rootMidY
		local listLayout = tooltip:FindFirstChildOfClass("UIListLayout")
		if listLayout then
			listLayout.VerticalAlignment = showBelow and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
		end
		local px = ax - ox + anchor.AbsoluteSize.X - tw
		local py
		if showBelow then
			py = ay - oy + ah + TOOLTIP_OFFSET_ABOVE
		else
			py = ay - oy - th - TOOLTIP_OFFSET_ABOVE
		end
		tooltip.Position = UDim2.new(0, px, 0, py)
	end)
end

-- Row with indent, expand/collapse, name, tags. contentWidth = min width for horizontal scroll (nil = fill parent). options may include showTagTooltip, hideTagTooltip.
local function createTreeNodeRow(entry, tagManager, onSelect, onExpandCollapse, getChildren, onExpandChanged, contentWidth, options)
	local node = entry.node
	local depth = entry.depth
	local obj = node.object
	local tagNames = getTagNames(obj, tagManager)

	local btn = Instance.new("TextButton")
	btn.Size = contentWidth and UDim2.new(0, contentWidth, 0, ROW_HEIGHT) or UDim2.new(1, -4, 0, ROW_HEIGHT)
	btn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.ClipsDescendants = false

	local starWidth = (options and options.favoritesManager) and 20 or 0
	local left = 6 + starWidth + depth * INDENT_PX
	-- Show expand icon only when the instance actually has (or might have) children
	local hasChildren
	if node.childrenLoaded then
		hasChildren = #node.children > 0
	else
		hasChildren = #node.object:GetChildren() > 0
	end
	local canExpand = hasChildren

	-- Star (favorite) button when favoritesManager is provided
	if options and options.favoritesManager then
		local favMgr = options.favoritesManager
		local onFavoritesChanged = options.onFavoritesChanged
		local starBtn = Instance.new("TextButton")
		starBtn.Size = UDim2.new(0, starWidth, 0, ROW_HEIGHT)
		starBtn.Position = UDim2.new(0, 2, 0, 0)
		starBtn.BackgroundTransparency = 1
		starBtn.Text = favMgr:isFavorite(obj) and "⭐" or "☆"
		starBtn.TextColor3 = Colors.UI.TEXT_MUTED
		starBtn.TextSize = 12
		starBtn.Font = Enum.Font.Gotham
		starBtn.Parent = btn
		starBtn.Activated:Connect(function()
			if favMgr:isFavorite(obj) then
				favMgr:removeFavorite(obj)
			else
				favMgr:addFavorite(obj)
			end
			starBtn.Text = favMgr:isFavorite(obj) and "⭐" or "☆"
			if onFavoritesChanged then onFavoritesChanged() end
		end)
	end

	-- Expand/collapse button (arrow)
	local expandBtn = Instance.new("TextButton")
	expandBtn.Size = UDim2.new(0, 18, 0, ROW_HEIGHT)
	expandBtn.Position = UDim2.new(0, left - 2, 0, 0)
	expandBtn.BackgroundTransparency = 1
	expandBtn.Text = canExpand and (node.expanded and "▼" or "▶") or "  "
	expandBtn.TextColor3 = Colors.UI.TEXT_MUTED
	expandBtn.TextSize = 10
	expandBtn.Font = Enum.Font.Gotham
	expandBtn.Parent = btn

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -left - 16 - DOTS_AREA_WIDTH, 1, 0)
	nameLabel.Position = UDim2.new(0, left + 16, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = obj.Name
	nameLabel.TextColor3 = Colors.UI.TEXT
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	-- Color-coded tag dots (right side of row)
	local dotsContainer = Instance.new("Frame")
	dotsContainer.Name = "TagDots"
	dotsContainer.Size = UDim2.new(0, DOTS_AREA_WIDTH, 1, 0)
	dotsContainer.Position = UDim2.new(1, -DOTS_AREA_WIDTH, 0, 0)
	dotsContainer.BackgroundTransparency = 1
	dotsContainer.ClipsDescendants = true
	dotsContainer.Parent = btn
	fillTagColorDots(dotsContainer, tagNames or {}, tagManager, options and options.colorCodingEnabled)

	-- Hover over tag dots: show tooltip with tag chips (color + name). Pass getter so tooltip shows current tags after add/remove.
	if tagManager and options and options.showTagTooltip and options.hideTagTooltip then
		local getTagNamesForTooltip = function()
			return getTagNames(obj, tagManager)
		end
		dotsContainer.MouseEnter:Connect(function()
			local current = getTagNamesForTooltip()
			if current and #current > 0 then
				options.showTagTooltip(dotsContainer, getTagNamesForTooltip)
			end
		end)
		dotsContainer.MouseLeave:Connect(function()
			options.hideTagTooltip()
		end)
	end

	-- Click name/row: select in Studio
	btn.Activated:Connect(function()
		Selection:Set({ obj })
		if onSelect then onSelect(obj) end
	end)

	-- Click expand: load children if needed, toggle expanded, re-render
	if canExpand then
		expandBtn.Activated:Connect(function()
			if not node.childrenLoaded then
				local rawChildren = getChildren(node)
				for _, inst in ipairs(rawChildren) do
					if inst and inst.Parent then
						table.insert(node.children, newNode(inst, depth + 1))
					end
				end
				node.childrenLoaded = true
			end
			node.expanded = not node.expanded
			if node.expanded and #node.children == 0 then
				node.expanded = false
			end
			if onExpandChanged then onExpandChanged(node, node.expanded) end
			if onExpandCollapse then onExpandCollapse() end
		end)
	end

	if options and options.onRowCreated then
		options.onRowCreated(btn, obj)
	end

	return btn
end

local function renderTree(scrollFrame, roots, getChildren, options)
	options = options or {}
	local tagManager = options.tagManager
	local onSelect = options.onSelect
	local onExpandChanged = options.onExpandChanged
	local totalCount = options.totalCount or 0
	local maxShown = options.maxShown or MAX_VISIBLE_TREE_ROWS

	local listLayout = scrollFrame:FindFirstChildOfClass("UIListLayout")
	local footerLabel = scrollFrame:FindFirstChild("ObjectListFooter")
	local maxRows = math.min(MAX_VISIBLE_TREE_ROWS, maxShown)
	local visible = buildVisibleList(roots, getChildren, maxRows)
	local numRows = #visible
	local newSignature = buildSignature(visible)
	if options.favoritesVersion ~= nil then
		table.insert(newSignature, { path = "\0fav", depth = options.favoritesVersion })
	end

	local state = stateByScroll[scrollFrame]
	if not state then
		state = {}
		stateByScroll[scrollFrame] = state
	end

	-- (1) Same structure: update labels in place only (no flicker)
	if state.lastSignature and signaturesEqual(state.lastSignature, newSignature) then
		local rows = {}
		for _, child in ipairs(scrollFrame:GetChildren()) do
			if child ~= listLayout and child ~= footerLabel and child:IsA("TextButton") then
				table.insert(rows, child)
			end
		end
		table.sort(rows, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, numRows do
			local row = rows[i]
			local entry = visible[i]
			if row and entry then
				local obj = entry.node.object
				if obj and obj.Parent then
					local tagNames = getTagNames(obj, tagManager)
					local nameLabel = row:FindFirstChildOfClass("TextLabel")
					if nameLabel then
						nameLabel.Text = obj.Name
					end
					local dotsContainer = row:FindFirstChild("TagDots")
					if dotsContainer then
						fillTagColorDots(dotsContainer, tagNames or {}, tagManager, options.colorCodingEnabled)
					end
				end
				-- Repopulate row->object map so hit-test (e.g. tag drop) works after in-place update
				if options.onRowCreated then
					options.onRowCreated(row, entry.node.object)
				end
			end
		end
		state.lastSignature = newSignature
		return
	end

	-- (2) Full re-render: save scroll position, then restore after
	local savedScrollY = scrollFrame.CanvasPosition.Y

	for _, child in ipairs(scrollFrame:GetChildren()) do
		if child ~= listLayout and child ~= footerLabel then
			child:Destroy()
		end
	end
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 2)
		listLayout.Parent = scrollFrame
	end

	local function refresh()
		renderTree(scrollFrame, roots, getChildren, options)
	end

	-- Shared tag tooltip for this scroll frame; show/hide callbacks for row hover
	local tagTooltip = getOrCreateTagTooltip(scrollFrame)
	local tooltipOptions = {}
	for k, v in pairs(options) do tooltipOptions[k] = v end
	tooltipOptions.showTagTooltip = function(anchor, tagNames)
		if tagTooltip then
			showTagTooltip(tagTooltip, tagNames, tagManager, anchor)
		end
	end
	tooltipOptions.hideTagTooltip = function()
		if tagTooltip then tagTooltip.Visible = false end
	end

	-- Min content width so deep hierarchies can scroll horizontally.
	-- Reserve vertical scrollbar width so tag dots on the right are not cropped when the scrollbar appears.
	local scrollBarThickness = scrollFrame.ScrollBarThickness or 0
	local viewportW = scrollFrame.AbsoluteWindowSize.X - scrollBarThickness
	if viewportW <= 0 then viewportW = 300 end
	local maxDepth = 0
	for _, entry in ipairs(visible) do
		maxDepth = math.max(maxDepth, entry.depth)
	end
	local contentWidth = math.max(viewportW, 6 + maxDepth * INDENT_PX + 18 + 250)

	for batchStart = 1, numRows, BATCH_SIZE do
		local batchEnd = math.min(batchStart + BATCH_SIZE - 1, numRows)
		for i = batchStart, batchEnd do
			local entry = visible[i]
			local row = createTreeNodeRow(entry, tagManager, onSelect, refresh, getChildren, onExpandChanged, contentWidth, tooltipOptions)
			row.LayoutOrder = i
			row.Parent = scrollFrame
		end
		if batchEnd < numRows then
			task.wait()
		end
	end

	if footerLabel then
		footerLabel.Visible = false
	end
	if totalCount > 0 and (numRows >= maxRows or (totalCount > numRows and numRows > 0)) then
		if not footerLabel then
			footerLabel = Instance.new("TextLabel")
			footerLabel.Name = "ObjectListFooter"
			footerLabel.Size = UDim2.new(0, contentWidth, 0, 20)
			footerLabel.BackgroundTransparency = 1
			footerLabel.TextColor3 = Colors.UI.TEXT_MUTED
			footerLabel.TextSize = 11
			footerLabel.Font = Enum.Font.Gotham
			footerLabel.TextXAlignment = Enum.TextXAlignment.Left
			footerLabel.Parent = scrollFrame
		else
			footerLabel.Size = UDim2.new(0, contentWidth, 0, 20)
		end
		footerLabel.Text = string.format("Showing %d of %d", numRows, totalCount)
		footerLabel.LayoutOrder = numRows + 1
		footerLabel.Visible = true
	end

	state.lastSignature = newSignature
	-- Restore scroll position (clamp to valid range)
	local canvasH = scrollFrame.CanvasSize.Y.Offset
	local viewH = scrollFrame.AbsoluteWindowSize.Y
	local maxScroll = math.max(0, canvasH - viewH)
	scrollFrame.CanvasPosition = Vector2.new(0, math.clamp(savedScrollY, 0, maxScroll))
end

function updateTreeList(scrollFrame, roots, getChildren, options)
	renderTree(scrollFrame, roots, getChildren, options)
end

-- Legacy flat list (e.g. single virtual root whose children are the flat list). Optional tagManager: when provided, shows color dots instead of tag names in text.
local function createObjectRow(object, tagNames, onSelect, tagManager)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -4, 0, ROW_HEIGHT)
	btn.BackgroundColor3 = Colors.UI.BACKGROUND_LIGHT
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = true
	btn.ClipsDescendants = false

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, tagManager and (-6 - DOTS_AREA_WIDTH) or -6, 1, 0)
	nameLabel.Position = UDim2.new(0, 6, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = object.Name
	nameLabel.TextColor3 = Colors.UI.TEXT
	nameLabel.TextSize = 12
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = btn

	if tagManager then
		local dotsContainer = Instance.new("Frame")
		dotsContainer.Name = "TagDots"
		dotsContainer.Size = UDim2.new(0, DOTS_AREA_WIDTH, 1, 0)
		dotsContainer.Position = UDim2.new(1, -DOTS_AREA_WIDTH, 0, 0)
		dotsContainer.BackgroundTransparency = 1
		dotsContainer.ClipsDescendants = true
		dotsContainer.Parent = btn
		fillTagColorDots(dotsContainer, tagNames or {}, tagManager)
	elseif tagNames and #tagNames > 0 then
		nameLabel.Text = object.Name .. " [" .. table.concat(tagNames, ", ") .. "]"
	end

	btn.Activated:Connect(function()
		Selection:Set({ object })
		if onSelect then onSelect(object) end
	end)
	return btn
end

-- Legacy flat list: treat each object as a root (no hierarchy).
local function updateObjectList(scrollFrame, objects, tagManager, onSelect, totalCount, maxShown)
	totalCount = totalCount or #objects
	maxShown = maxShown or #objects
	local roots = {}
	for _, entry in ipairs(objects) do
		local obj = type(entry) == "table" and entry.object or entry
		table.insert(roots, newNode(obj, 0))
	end
	local getChildren = function(node)
		return node.object:GetChildren()
	end
	updateTreeList(scrollFrame, roots, getChildren, {
		tagManager = tagManager,
		onSelect = onSelect,
		totalCount = totalCount,
		maxShown = maxShown,
	})
end

return {
	createObjectRow = createObjectRow,
	updateObjectList = updateObjectList,
	updateTreeList = updateTreeList,
}
