local Package = script.Parent
local ApiDump = require(Package.ApiDump)
local CollectionService = game:GetService("CollectionService")

local Converter = {}

function Converter:convert(instance, toClass)
	if not ApiDump:getClassEntry(toClass) then error("Invalid class to convert to!") end
	
	local fromProperties = ApiDump:getConvertableProperties(instance.ClassName)
	local toProperties = ApiDump:getConvertableProperties(toClass)
	
	local newInstance
	local success, err = pcall(function()
		newInstance = Instance.new(toClass)
	end)
	if not success then error("Couldn't create instance of type " .. toClass .. ": " .. err) end
	
	for _, propertyName in ipairs(fromProperties) do
		if propertyName ~= "Parent" and table.find(toProperties, propertyName) then
			pcall(function()
				newInstance[propertyName] = instance[propertyName]
			end)
		end
	end
	
	for _, tag in pairs(CollectionService:GetTags(instance)) do
		CollectionService:AddTag(newInstance, tag)
	end
	
	for _, child in pairs(instance:GetChildren()) do
		for _, propertyName in pairs(ApiDump:getConvertableProperties(child.ClassName)) do
			pcall(function()
				if child[propertyName] == instance then
					child[propertyName] = newInstance
				end
			end)
		end
		child.Parent = newInstance
	end
	
	newInstance.Parent = instance.Parent
	instance:Remove()
	
	return newInstance
end

function Converter:convertAll(instances, toClass)
	local t = {}
	for i, v in ipairs(instances) do
		pcall(function()
			t[#t + 1] = Converter:convert(v, toClass)
		end)
	end
	return t
end

return Converter