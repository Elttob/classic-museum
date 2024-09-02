local StudioService = game:GetService("StudioService")

local Package = script.Parent
local ApiDump = require(Package.ApiDump)

local function size(t)
	local size = 0
	for _ in pairs(t) do size = size + 1 end
	return size
end

local Recommender = {}

local DefaultScores = require(script.DefaultScores)

Recommender.userScores = {}

function Recommender:loadScores(plugin)
	local scores = plugin:GetSetting "RecommenderUserScores"
	Recommender.userScores = scores or DefaultScores
end

function Recommender:saveScores(plugin)
	plugin:SetSetting("RecommenderUserScores", Recommender.userScores)
end

function Recommender:addScore(itemA, itemB, delta)
	if not Recommender.userScores[itemA] then
		Recommender.userScores[itemA] = {}
	end
	Recommender.userScores[itemA][itemB] = (Recommender.userScores[itemA][itemB] or 0) + delta
end

local excludeTags = {
	"NotCreatable",
	"NotBrowsable",
	"Deprecated",
	"Service"
}
function Recommender:shouldExcludeClass(entry)
	if entry.Tags then
		for _, tag in pairs(excludeTags) do
			if table.find(entry.Tags, tag) then
				return true
			end
		end
	end
	
	-- check if the class exists in Studio - this could happen if
	-- the API dump gets ahead of Studio!
	-- GetClassIcon errors when given an invalid class
if not pcall(StudioService.GetClassIcon, StudioService, entry.Name) then
		return true
	end
	
	return false
end

function Recommender:getRelevantClasses(className)	
	local foundItems = {}
	local foundItemMap = {}
	
	if Recommender.userScores[className] then
		for className, defaultRank in pairs(Recommender.userScores[className]) do
			foundItems[className] = -defaultRank
		end
	end
	
	local function process(class, relativeRank)
		if class == "Instance" or foundItemMap[class] or relativeRank < -12 then
			return
		end
		local entry = ApiDump:getClassEntry(class)
		if not entry then return end
		if class ~= className and not Recommender:shouldExcludeClass(entry) then
			foundItems[class] = (foundItems[class] or 0) - relativeRank
			foundItemMap[class] = true
		end
		process(entry.Superclass, relativeRank - 5)
		for _, subclass in pairs(ApiDump:getSubclasses(class)) do
			process(subclass.Name, relativeRank - 1)
		end
	end
	
	process(className, 0)
	
	return foundItems
end

local filteredCache = {}
function Recommender:getFilteredClasses(className, query)	
	query = query:lower()
	if filteredCache[query] then return filteredCache[query] end
	
	local superclasses = {}
	local function process(className)
		local entry = ApiDump:getClassEntry(className)
		if not entry then return end
		superclasses[#superclasses + 1] = className
		process(entry.Superclass)
	end
	process(className)
	
	local hits = {}
	for i, v in pairs(ApiDump.CachedApiDump.Classes) do
		if v.Name ~= className and string.find(v.Name:lower(), query, 1, true) and not Recommender:shouldExcludeClass(v) then
			
			local originalClassName = className
			local distance = 0
			local function process(className)
				local entry = ApiDump:getClassEntry(className)
				if not entry then distance = 999 return end
				if className == originalClassName then distance = -distance return end
				if table.find(superclasses, className) then return end
				distance = distance + 1
				process(entry.Superclass)
			end
			process(v.Name)
			
			hits[v.Name] = distance
		end
	end
	
	filteredCache[query] = hits
	return hits
end

return Recommender