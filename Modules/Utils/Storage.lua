--[[
	Utils/Storage.lua
	Per-project storage key namespacing for Studio Organizer.
]]

local Storage = {}

function Storage.getStorageKey(baseName)
	local placeId = game.PlaceId
	local placeKey = (placeId == 0) and "local" or tostring(placeId)
	return string.format("%s:%s", baseName, placeKey)
end

return Storage
