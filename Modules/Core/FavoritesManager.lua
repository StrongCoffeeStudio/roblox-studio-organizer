--[[
	Core/FavoritesManager.lua
	Quick Favorites: store and resolve Instance paths.
]]

local HttpService = game:GetService("HttpService")
local Storage = require(script.Parent.Parent.Utils.Storage)

local FavoritesManager = {}
FavoritesManager.__index = FavoritesManager

-- Resolve full path (e.g. "Workspace.Model.Part") to Instance, or nil if not found/deleted.
local function resolvePathToInstance(path)
	if not path or path == "" or type(path) ~= "string" then return nil end
	local parts = {}
	for part in path:gmatch("[^%.]+") do
		table.insert(parts, part)
	end
	if #parts == 0 then return nil end
	local current = game
	for i = 1, #parts do
		if not current then return nil end
		current = current:FindFirstChild(parts[i])
	end
	if current and current.Parent then return current end
	return nil
end

function FavoritesManager.new(plugin)
	local self = setmetatable({}, FavoritesManager)
	self.plugin = plugin
	self._paths = {} -- set of full paths (string)
	self:loadFromStorage()
	return self
end

function FavoritesManager:loadFromStorage()
	self._paths = {}
	local key = Storage.getStorageKey("Favorites")
	local json = self.plugin:GetSetting(key)
	if not json or type(json) ~= "string" then return end
	local ok, list = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(list) ~= "table" then return end
	for _, path in ipairs(list) do
		if type(path) == "string" and path ~= "" then
			self._paths[path] = true
		end
	end
end

function FavoritesManager:saveToStorage()
	local key = Storage.getStorageKey("Favorites")
	local list = {}
	for path, _ in pairs(self._paths) do
		table.insert(list, path)
	end
	table.sort(list)
	local json = HttpService:JSONEncode(list)
	self.plugin:SetSetting(key, json)
end

function FavoritesManager:addFavorite(instance)
	if not instance or not instance.Parent then return false end
	local ok, path = pcall(function() return instance:GetFullName() end)
	if not ok or not path then return false end
	if self._paths[path] then return false end -- already in favorites (same name and path)
	self._paths[path] = true
	self:saveToStorage()
	return true
end

function FavoritesManager:removeFavorite(instance)
	if not instance then return false end
	local ok, path = pcall(function() return instance:GetFullName() end)
	if ok and path then
		self._paths[path] = nil
		self:saveToStorage()
		return true
	end
	-- Also allow remove by path (e.g. instance already destroyed)
	for p, _ in pairs(self._paths) do
		if p == tostring(instance) then
			self._paths[p] = nil
			self:saveToStorage()
			return true
		end
	end
	return false
end

function FavoritesManager:removeFavoriteByPath(path)
	if not path or type(path) ~= "string" then return false end
	if self._paths[path] then
		self._paths[path] = nil
		self:saveToStorage()
		return true
	end
	return false
end

function FavoritesManager:isFavorite(instance)
	if not instance then return false end
	local ok, path = pcall(function() return instance:GetFullName() end)
	return ok and path and self._paths[path] == true
end

-- Return list of Instances that currently resolve (invalid paths skipped).
function FavoritesManager:getFavorites()
	local out = {}
	for path, _ in pairs(self._paths) do
		local obj = resolvePathToInstance(path)
		if obj and obj.Parent then
			table.insert(out, obj)
		end
	end
	table.sort(out, function(a, b)
		local pa = pcall(function() return a:GetFullName() end)
		local pb = pcall(function() return b:GetFullName() end)
		if pa and pb then
			return a:GetFullName() < b:GetFullName()
		end
		return tostring(a) < tostring(b)
	end)
	return out
end

-- Add multiple instances (e.g. from drag). Dedupes by path; returns number added.
function FavoritesManager:addFavorites(instances)
	local added = 0
	for _, obj in ipairs(instances) do
		if not obj or not obj.Parent then continue end
		if self:isFavorite(obj) then continue end -- same name and path already in list
		if self:addFavorite(obj) then added = added + 1 end
	end
	return added
end

return FavoritesManager
