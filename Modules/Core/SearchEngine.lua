--[[
	Core/SearchEngine.lua
	Basic name search over full game tree. Debounced by caller.
]]

local SearchEngine = {}
SearchEngine.__index = SearchEngine

function SearchEngine.new(tagManager)
	local self = setmetatable({}, SearchEngine)
	self.tagManager = tagManager
	return self
end

function SearchEngine:search(query, options)
	options = options or {}
	local results = {}
	local searchSpace = options.scope or game:GetDescendants()

	if not query or query == "" then
		for _, obj in ipairs(searchSpace) do
			table.insert(results, { object = obj, relevance = 0 })
		end
		return results
	end

	local queryLower = query:lower()
	for _, object in ipairs(searchSpace) do
		local relevance = 0
		local name = object.Name:lower()
		if name == queryLower then
			relevance = 100
		elseif #name >= #queryLower and name:sub(1, #queryLower) == queryLower then
			relevance = 75
		elseif name:find(queryLower, 1, true) then
			relevance = 50
		end
		if relevance > 0 then
			table.insert(results, { object = object, relevance = relevance })
		end
	end

	table.sort(results, function(a, b)
		if a.relevance ~= b.relevance then
			return a.relevance > b.relevance
		end
		return a.object.Name < b.object.Name
	end)
	return results
end

return SearchEngine
