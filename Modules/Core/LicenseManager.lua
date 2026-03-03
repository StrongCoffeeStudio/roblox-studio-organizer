--[[
	Core/LicenseManager.lua
	Tier check.
]]

local LicenseManager = {}
LicenseManager.__index = LicenseManager

function LicenseManager.new(plugin)
	local self = setmetatable({}, LicenseManager)
	self.plugin = plugin
	return self
end

function LicenseManager:getTier()
	return "free"
end

function LicenseManager:checkFeature(feature)
	local tier = self:getTier()
	return true
end

return LicenseManager
