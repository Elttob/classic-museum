--[[
	
	ApiDump
	Manages access to various parts of Roblox's API dump.
	
--]]

local HttpService = game:GetService("HttpService")
local apiWebService = ""
local maxApiDumpCacheTime = 60*60*24*7

local ApiDump = {}

-- The name of the root class (surprisingly, not Instance!)
ApiDump.RootClassName = "<<<ROOT>>>"

-- A copy of the latest cached API dump.
ApiDump.CachedApiDump = nil

--[[
	Downloads and caches a fresh copy of the API dump.
--]]
function ApiDump:FetchApiDump(plugin)
	local shouldSaveApiDump = plugin:GetSetting("ApiDumpShouldSave") == true
	if shouldSaveApiDump then
		local lastApiDumpCacheTime = plugin:GetSetting("LastApiDumpCacheTime") or 0
		if os.time() - lastApiDumpCacheTime < maxApiDumpCacheTime then
			ApiDump.CachedApiDump = plugin:GetSetting("ApiDumpCache")
			if ApiDump.CachedApiDump then return true end
		end
	end
	
	local dumpString
	local success, err = pcall(function()
		dumpString = HttpService:GetAsync(apiWebService)
	end)
	if not success then
		local httpDisabled = err:find("not enabled")
		return false, httpDisabled and "HTTPDisabled" or "HTTPError", err
	end
	
	success, err = pcall(function()
		ApiDump.CachedApiDump = HttpService:JSONDecode(dumpString)
	end)
	if not success then
		return false, "JSONDecodeError", err
	end
	
	if shouldSaveApiDump then
		pcall(function()
			plugin:SetSetting("ApiDumpCache", ApiDump.CachedApiDump)
			plugin:SetSetting("LastApiDumpCacheTime", os.time())
		end)
	end
	
	return true
end

--[[
	Returns the class API entry for the given class name.
--]]
local classEntryCache = {}
function ApiDump:getClassEntry(className)
	if classEntryCache[className] then return classEntryCache[className] end
	for _, entry in pairs(ApiDump.CachedApiDump.Classes) do
		if entry.Name == className then
			classEntryCache[className] = entry
			return entry
		end
	end
end

--[[
	Returns the subclass names for the given class name.
--]]
local subclassesCache = {}
function ApiDump:getSubclasses(className)
	if subclassesCache[className] then return subclassesCache[className] end
	local subclasses = {}
	for _, entry in pairs(ApiDump.CachedApiDump.Classes) do
		if entry.Superclass == className then
			subclasses[#subclasses + 1] = entry
		end
	end
	subclassesCache[className] = subclasses
	return subclasses
end

--[[
	Returns a list of member entries belonging to the given class name or its superclasses.
--]]
local membersCache = {}
function ApiDump:getMembers(className)
	if membersCache[className] then return membersCache[className] end
	local members = {}
	
	local entries = {}
	
	do
		local currentEntry = ApiDump:getClassEntry(className)
		while currentEntry and currentEntry.Superclass ~= ApiDump.RootClassName do
			table.insert(entries, 1, currentEntry)
			currentEntry = ApiDump:getClassEntry(currentEntry.Superclass)
		end
		if currentEntry == nil then
			error("Class name " .. className .. " could not be found")
		end
		table.insert(entries, 1, currentEntry)
	end
	
	for i, v in ipairs(entries) do
		for _, member in ipairs(v.Members) do
			members[#members + 1] = member
		end
	end
	
	membersCache[className] = members
	return members
end

--[[
	Returns a list of property names which should be considered during object conversion.
--]]
local ignoreTags = {
	ReadOnly = true,
	Deprecated = true,
	Hidden = true
}
function ApiDump:getConvertableProperties(className)
	local members = self:getMembers(className)
	
	local props = {}
	for _, member in ipairs(members) do
		if member.MemberType == "Property" then
			local convertable = true
			if member.Tags then
				for _, tag in pairs(member.Tags) do
					if ignoreTags[tag] then
						convertable = false
						break
					end
				end
			end
			if convertable then
				props[#props + 1] = member.Name
			end
		end
	end
	
	return props
end


return ApiDump