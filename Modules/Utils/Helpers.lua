--[[
	Utils/Helpers.lua
	Utility functions for path resolution and instance handling.
]]

local Helpers = {}

function Helpers.resolvePathToInstance(path)
	if not path or path == "" then
		return nil
	end
	local segments = {}
	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(segments, segment)
	end
	local current = game
	for _, segment in ipairs(segments) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end
	return current
end

function Helpers.getInstancePath(instance)
	if not instance or not instance.Parent then
		return nil
	end
	local success, path = pcall(function()
		return instance:GetFullName()
	end)
	return success and path or nil
end

function Helpers.pruneOrphanedPaths(pathTable)
	local cleaned = {}
	for path, value in pairs(pathTable) do
		local instance = Helpers.resolvePathToInstance(path)
		if instance and instance.Parent then
			cleaned[path] = value
		end
	end
	return cleaned
end

return Helpers
