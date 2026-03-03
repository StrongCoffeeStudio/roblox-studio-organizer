--[[
	UI/Components/TagChip.lua
	Single tag pill: background uses tag color, click to filter. Drag-and-drop source; can be drop target.
	Returns wrapper Frame. Optional options: { onDragStart = function(tag) end } for tag→object drag.
]]

local Colors = require(script.Parent.Parent.Parent.Utils.Colors)
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local SELECTED_HIGHLIGHT = Color3.new(1, 1, 1)
local DRAG_THRESHOLD_PX = 5

local function createTagChip(tag, onActivated, isActive, options)
	options = options or {}
	local onDragStart = options.onDragStart
	local colorCodingEnabled = options.colorCodingEnabled ~= false

	local wrapper = Instance.new("Frame")
	wrapper.Size = UDim2.new(0, 0, 0, 28)
	wrapper.AutomaticSize = Enum.AutomaticSize.X
	wrapper.BackgroundTransparency = 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = wrapper

	local stroke = Instance.new("UIStroke")
	stroke.Color = SELECTED_HIGHLIGHT
	stroke.Thickness = isActive and 3 or 0
	stroke.Parent = wrapper

	local chipColor = colorCodingEnabled and tag.color or Colors.UI.BACKGROUND_LIGHT
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 0, 0, 28)
	btn.AutomaticSize = Enum.AutomaticSize.X
	btn.Position = UDim2.new(0, 0, 0, 0)
	btn.BackgroundColor3 = chipColor
	btn.BorderSizePixel = 0
	btn.Text = (tag.icon and (tag.icon .. " ") or "") .. tag.name .. " (" .. tostring(tag.usageCount) .. ")"
	btn.TextColor3 = (colorCodingEnabled and tag.color) and Color3.new(1, 1, 1) or Colors.UI.TEXT
	btn.TextSize = 12
	btn.Font = Enum.Font.Gotham
	btn.AutoButtonColor = true
	btn.ClipsDescendants = false
	btn.Parent = wrapper

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = btn

	local dragStartPos = nil
	local isDragging = false

	if onActivated then
		btn.Activated:Connect(function()
			if isDragging then return end
			onActivated()
		end)
	end

	-- Drag start: track movement; after threshold call onDragStart(tag, onDragEndCallback).
	-- Use plugin widget's GetRelativeMousePosition + Heartbeat so drag is detected when mouse is over plugin
	-- (UserInputService.InputChanged often doesn't fire when the cursor is over a PluginGui).
	if type(onDragStart) == "function" then
		local heartbeatConn = nil
		local function stopTracking()
			dragStartPos = nil
			if heartbeatConn then
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
		end
		btn.MouseButton1Down:Connect(function()
			local widget = options.widget
			if not widget or not widget.GetRelativeMousePosition then
				stopTracking()
				return
			end
			local pos = widget:GetRelativeMousePosition()
			dragStartPos = Vector2.new(pos.X, pos.Y)
			isDragging = false
			if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
			heartbeatConn = RunService.Heartbeat:Connect(function()
				if not dragStartPos or not btn.Parent then
					stopTracking()
					return
				end
				local pos = widget:GetRelativeMousePosition()
				local dx = pos.X - dragStartPos.X
				local dy = pos.Y - dragStartPos.Y
				if (dx * dx + dy * dy) > (DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX) and not isDragging then
					isDragging = true
					stopTracking()
					onDragStart(tag, function()
						isDragging = false
					end, btn)
				end
			end)
		end)
		btn.MouseButton1Up:Connect(stopTracking)
	end

	wrapper:SetAttribute("TagChip", true)
	wrapper:SetAttribute("IsActive", isActive)
	return wrapper
end

return createTagChip
