--[[
	Core/TagManager.lua
	Tag CRUD and object-tag relationships.
	Storage: CollectionService for object-tag links; plugin settings for tag metadata.
]]

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Tag = require(script.Parent.Parent.Models.Tag)
local Storage = require(script.Parent.Parent.Utils.Storage)
local Colors = require(script.Parent.Parent.Utils.Colors)
local QuickPresets = require(script.Parent.Parent.Utils.QuickPresets)

-- In-memory: tags keyed by tag name (string). tag.id = tag.name for CollectionService compatibility.
local tags = {}

local TagManager = {}
TagManager.__index = TagManager

function TagManager.new(plugin)
	local self = setmetatable({}, TagManager)
	self.plugin = plugin
	self._autoSave = true
	self:loadFromStorage()
	-- First run: create quick preset tags (one-time)
	local flagKey = Storage.getStorageKey("QuickPresetsInitialized")
	if not self.plugin:GetSetting(flagKey) then
		for _, entry in ipairs(QuickPresets.LIST) do
			local name = entry[1]
			local colorIndex = math.clamp(entry[2] or 1, 1, #Colors.TAG_PRESETS)
			local color = Colors.TAG_PRESETS[colorIndex]
			local icon = entry[3]
			self:createTag(name, color, "", icon)
		end
		self.plugin:SetSetting(flagKey, "true")
	end
	return self
end

function TagManager:createTag(name, color, description, icon)
	local trimmed = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if trimmed == "" then return nil end
	if tags[trimmed] then return nil end -- duplicate name
	local tag = Tag.new(trimmed, trimmed, color, description, icon)
	tags[tag.name] = tag
	self:saveToStorage()
	return tag
end

function TagManager:getTag(tagId)
	return tags[tagId]
end

function TagManager:getAllTags()
	local list = {}
	for _, tag in pairs(tags) do
		table.insert(list, tag)
	end
	table.sort(list, function(a, b) return a.name < b.name end)
	return list
end

function TagManager:updateTagColor(tagId, color)
	local tag = tags[tagId]
	if not tag then return nil end
	tag.color = color
	self:saveToStorage()
	return tag
end

function TagManager:updateTagIcon(tagId, icon)
	local tag = tags[tagId]
	if not tag then return nil end
	tag.icon = (icon and icon ~= "") and icon or "🏷️" -- default to tag icon if no icon is provided
	self:saveToStorage()
	return tag
end

function TagManager:deleteTag(tagId)
	local tag = tags[tagId]
	if not tag then return end
	local ok, tagged = pcall(function()
		return CollectionService:GetTagged(tagId)
	end)
	if ok and tagged then
		for _, obj in ipairs(tagged) do
			pcall(function()
				CollectionService:RemoveTag(obj, tagId)
			end)
		end
	end
	tags[tagId] = nil
	self.plugin:SetSetting(Storage.getStorageKey("TagMetadata_" .. tagId), nil)
	self:saveToStorage()
end

function TagManager:renameTag(tagId, newName)
	local tag = tags[tagId]
	if not tag then return end
	local trimmed = newName and newName:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if trimmed == "" or trimmed == tagId then return end
	if tags[trimmed] then return end -- duplicate
	local ok, tagged = pcall(function()
		return CollectionService:GetTagged(tagId)
	end)
	if ok and tagged then
		for _, obj in ipairs(tagged) do
			pcall(function()
				CollectionService:RemoveTag(obj, tagId)
				CollectionService:AddTag(obj, trimmed)
			end)
		end
	end
	tag.name = trimmed
	tag.id = trimmed
	tags[trimmed] = tag
	tags[tagId] = nil
	self.plugin:SetSetting(Storage.getStorageKey("TagMetadata_" .. tagId), nil)
	self:saveToStorage()
end

function TagManager:addTagToObject(object, tagId)
	if not object or not object.Parent then return false end
	if not tags[tagId] then return false end
	-- Avoid incrementing count when object already has this tag (e.g. re-dropping same file on chip)
	local existing = self:getTagsForObject(object)
	for _, name in ipairs(existing) do
		if name == tagId then
			return true
		end
	end
	local ok = pcall(function()
		CollectionService:AddTag(object, tagId)
	end)
	if not ok then return false end
	tags[tagId].usageCount = tags[tagId].usageCount + 1
	self:saveToStorage()
	return true
end

function TagManager:removeTagFromObject(object, tagId)
	if not object or not object.Parent then return false end
	local ok = pcall(function()
		CollectionService:RemoveTag(object, tagId)
	end)
	if not ok then return false end
	if tags[tagId] then
		tags[tagId].usageCount = math.max(0, tags[tagId].usageCount - 1)
		self:saveToStorage()
	end
	return true
end

function TagManager:getTagsForObject(object)
	if not object or not object.Parent then return {} end
	local ok, list = pcall(function()
		return CollectionService:GetTags(object)
	end)
	if ok and list then return list end
	return {}
end

function TagManager:getObjectsWithTag(tagId)
	local ok, list = pcall(function()
		return CollectionService:GetTagged(tagId)
	end)
	if ok and list then return list end
	return {}
end

-- Discover: collect all tag names that appear on any object in the place (single pass).
function TagManager:getAllTagNamesInUse()
	local seen = {}
	local ok = pcall(function()
		for _, obj in ipairs(game:GetDescendants()) do
			if obj and obj.Parent then
				local list = CollectionService:GetTags(obj)
				if list then
					for _, tagName in ipairs(list) do
						if type(tagName) == "string" and tagName ~= "" then
							seen[tagName] = true
						end
					end
				end
			end
		end
	end)
	if not ok then return {} end
	local out = {}
	for name, _ in pairs(seen) do
		table.insert(out, name)
	end
	return out
end

-- Ensure we have metadata for this tag name (e.g. tag came from asset/script). Creates with default color if missing.
function TagManager:ensureTagMetadata(tagName)
	if not tagName or type(tagName) ~= "string" or tagName == "" then return nil end
	if tags[tagName] then return tags[tagName] end
	local defaultColor = Colors.TAG_PRESETS[8] or Colors.UI.TEXT_MUTED -- gray
	local tag = Tag.new(tagName, tagName, defaultColor, "")
	local countOk, objs = pcall(function()
		return CollectionService:GetTagged(tagName)
	end)
	tag.usageCount = (countOk and objs) and #objs or 0
	tags[tagName] = tag
	self:saveToStorage()
	return tag
end

-- Discover tags from the place and adopt them into our tag list (so assets/scripts tags appear and are filterable).
function TagManager:discoverTagsFromPlace()
	local names = self:getAllTagNamesInUse()
	for _, name in ipairs(names) do
		self:ensureTagMetadata(name)
	end
end

function TagManager:setAutoSave(enabled)
	self._autoSave = enabled
end

-- Save only tag metadata (TagList + per-tag TagMetadata). No object-tag data.
function TagManager:saveToStorage()
	if self._autoSave == false then return end
	local tagList = {}
	for name, _ in pairs(tags) do
		table.insert(tagList, name)
	end
	table.sort(tagList)
	local listOk, listJson = pcall(HttpService.JSONEncode, HttpService, tagList)
	if listOk and listJson then
		self.plugin:SetSetting(Storage.getStorageKey("TagList"), listJson)
	end
	for name, tag in pairs(tags) do
		local data = tag:toJSON()
		local metaOk, metaJson = pcall(HttpService.JSONEncode, HttpService, data)
		if metaOk and metaJson then
			self.plugin:SetSetting(Storage.getStorageKey("TagMetadata_" .. name), metaJson)
		end
	end
end

-- Load tag list and per-tag metadata. Recompute usageCount from CollectionService.
function TagManager:loadFromStorage()
	tags = {}
	local listKey = Storage.getStorageKey("TagList")
	local listJson = self.plugin:GetSetting(listKey)
	if not listJson then return end
	local ok, tagList = pcall(HttpService.JSONDecode, HttpService, listJson)
	if not ok or not tagList or type(tagList) ~= "table" then return end
	for _, name in ipairs(tagList) do
		if type(name) == "string" and name ~= "" then
			local metaKey = Storage.getStorageKey("TagMetadata_" .. name)
			local metaJson = self.plugin:GetSetting(metaKey)
			if metaJson then
				local metaOk, data = pcall(HttpService.JSONDecode, HttpService, metaJson)
				if metaOk and data then
					local tag = Tag.fromJSON(data)
					if tag then
						tag.id = name
						tag.name = name
						local countOk, objs = pcall(function()
							return CollectionService:GetTagged(name)
						end)
						tag.usageCount = (countOk and objs) and #objs or 0
						tags[name] = tag
					end
				end
			end
		end
	end
end

function TagManager:getTagCount()
	local n = 0
	for _ in pairs(tags) do n = n + 1 end
	return n
end

function TagManager:getTaggedObjectCount()
	local seen = {}
	local n = 0
	for name, _ in pairs(tags) do
		local ok, list = pcall(function()
			return CollectionService:GetTagged(name)
		end)
		if ok and list then
			for _, obj in ipairs(list) do
				if obj and not seen[obj] then
					seen[obj] = true
					n = n + 1
				end
			end
		end
	end
	return n
end

return TagManager
