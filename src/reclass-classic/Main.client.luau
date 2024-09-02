local Package = script.Parent
local ApiDump = require(Package.ApiDump)
local UIManager = require(Package.UIManager)(plugin)
local Converter = require(Package.Converter)
local Recommender = require(Package.Recommender)
local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local PluginUpdates = require(Package.PluginUpdates)
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Pretty = require(Package.Libraries.Pretty)

local function size(t)
	local size = 0
	for _ in pairs(t) do size = size + 1 end
	return size
end

UIManager:init()

if not RunService:IsEdit() then
	UIManager:setMessage(UIManager.messages.disableOnTest)
	return
end


Recommender:loadScores(plugin)

delay(1, function()
	while true do
		PluginUpdates:getLatestVersion()
		UIManager:setUpdateNoticeVisible(PluginUpdates:isUpdateAvailable())
		wait(10 * 60)
	end
end)

while wait() do
	UIManager:setMessage(UIManager.messages.downloadingApi)
	local success, errorType, message = ApiDump:FetchApiDump(plugin)
	if not success then
		if errorType == "HTTPDisabled" then
			UIManager:setMessage(UIManager.messages.httpNeeded)
		else
			UIManager:setMessage(UIManager.messages.apiError)
			warn("Reclass API error start...")
			warn("Error type " .. errorType)
			warn(message)
			warn("Reclass API error end...")
		end
		UIManager:setRetryButtonVisible(true)
		UIManager.onRetryButtonClicked.Event:Wait()
		UIManager:setRetryButtonVisible(false)
	else break end
end

local currentClassName = nil
local lastFindClassText = nil
local function updateOptions()
	if not UIManager:isConvertWidgetShown() then return end
	
	local selection = Selection:Get()
	
	if #selection < 1 then
		UIManager:setMessage(UIManager.messages.noSelection)
		currentClassName = nil
		return
	end
	
	local className
	for _, ins in pairs(selection) do
		if not pcall(function() ins.Name = ins.Name end) then
			UIManager:setMessage(UIManager.messages.lockedInstances)
			currentClassName = nil
			return
		end
		
		if className ~= nil and className ~= ins.ClassName then
			className = nil
			break
		end
		className = ins.ClassName
	end
	
	if currentClassName ~= className or UIManager.currentFindClassText ~= lastFindClassText then
		currentClassName = className
		lastFindClassText = UIManager.currentFindClassText
	else
		return
	end
	
	if #UIManager.currentFindClassText > 0 then
		
		local suggestions = Recommender:getFilteredClasses(className, UIManager.currentFindClassText)
		if size(suggestions) < 1 then
			UIManager:setMessage(UIManager.messages.noClassesFound)
			return
		end
		
		UIManager:setMessage(nil)
		UIManager:setListItemsVisible(suggestions)
		
	else
		if not className then
			UIManager:setMessage(UIManager.messages.manyClasses)
			return
		end
		
		local suggestions = Recommender:getRelevantClasses(className)
		
		if size(suggestions) < 1 then
			UIManager:setMessage(UIManager.messages.noSuggestions)
			return
		end
		
		UIManager:setMessage(nil)
		UIManager:setListItemsVisible(suggestions)
		
		local topSuggestion
		for className, rank in pairs(suggestions) do
			if topSuggestion == nil or suggestions[topSuggestion] > rank then
				topSuggestion = className
			end
		end
		
		UIManager:getListItem(topSuggestion):setSuggested(true)
	end
	
end

updateOptions()
local connections = {
	Selection.SelectionChanged:Connect(updateOptions),
	
	UIManager.onConvertWidgetShown.Event:Connect(updateOptions),
	
	UIManager.onFindClassChanged.Event:Connect(updateOptions),
	
	UIManager.onConvertButtonClicked.Event:Connect(function()
		if UIManager.selectedListItem then
			
			local typeCache = {}
			for i, v in pairs(Selection:Get()) do
				if not typeCache[v.ClassName] then
					typeCache[v.ClassName] = true
					Recommender:addScore(v.ClassName, UIManager.selectedListItem.className, 1)
				end
			end
			Recommender:saveScores(plugin)
			
			local option = UIManager.selectedListItem.className
			ChangeHistoryService:SetWaypoint("Reclass: Convert to " .. option)
			Selection:Set(Converter:convertAll(Selection:Get(), option))
			ChangeHistoryService:SetWaypoint("Reclass: Convert to " .. option)
		end
	end),
	
	UIManager.onAutoConvertButtonClicked.Event:Connect(function()
		local selection = Selection:Get()
		
		if #selection < 1 then
			return
		end
		
		local className
		for _, ins in pairs(selection) do
			if not pcall(function() ins.Name = ins.Name end) then
				return
			end
			
			if className ~= nil and className ~= ins.ClassName then
				className = nil
				break
			end
			className = ins.ClassName
		end
		
		if not className then return end
		
		local suggestions = Recommender:getRelevantClasses(className)
		
		if size(suggestions) < 1 then
			return
		end
		
		local topSuggestion
		for className, rank in pairs(suggestions) do
			if topSuggestion == nil or suggestions[topSuggestion] > rank then
				topSuggestion = className
			end
		end
		
		if not topSuggestion then return end
		
		ChangeHistoryService:SetWaypoint("Reclass: Automatic Convert to " .. topSuggestion)
		Selection:Set(Converter:convertAll(Selection:Get(), topSuggestion))
		ChangeHistoryService:SetWaypoint("Reclass: Automatic Convert to " .. topSuggestion)
	end)
}

plugin.Unloading:Connect(function()
	for _, connection in pairs(connections) do
		connection:Disconnect()
	end
	UIManager:destroy()
end)