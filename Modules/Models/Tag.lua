--[[
	Models/Tag.lua
	Tag data model.
]]

local HttpService = game:GetService("HttpService")

local Tag = {}
Tag.__index = Tag

function Tag.new(id, name, color, description, icon)
	local self = setmetatable({}, Tag)
	self.name = name or "New Tag"
	-- Use name as id for CollectionService compatibility (tag name is the unique key)
	self.id = id or self.name
	self.color = color or Color3.fromRGB(100, 150, 200)
	self.description = description or ""
	self.icon = (icon and icon ~= "") and icon or "🏷️"
	self.createdAt = os.time()
	self.usageCount = 0
	return self
end

function Tag:toJSON()
	return {
		id = self.id,
		name = self.name,
		color = { self.color.R, self.color.G, self.color.B },
		description = self.description,
		icon = self.icon,
		createdAt = self.createdAt,
		usageCount = self.usageCount,
	}
end

function Tag.fromJSON(data)
	if not data then return nil end
	local tag = Tag.new(
		data.id,
		data.name,
		Color3.new(data.color[1], data.color[2], data.color[3]),
		data.description or "",
		data.icon
	)
	tag.createdAt = data.createdAt or os.time()
	tag.usageCount = data.usageCount or 0
	return tag
end

return Tag
