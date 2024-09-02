return function(plugin)
	
	local Package = script.Parent
	local MakeWidget = require(Package.Libraries.MakeWidget)(plugin)
	local Studio = settings().Studio
	local TweenService = game:GetService("TweenService")
	local RunService = game:GetService("RunService")
	local StudioService = game:GetService("StudioService")
	local TextService = game:GetService("TextService")
	local SmoothScroll = require(Package.Libraries.SmoothScroll)
	
	local function BindColour(item, modifier, callback)
		if callback == nil then return BindColour(item, "Default", modifier) end
		
		item = Enum.StudioStyleGuideColor[item]
		modifier = Enum.StudioStyleGuideModifier[modifier]
		
		local function update()
			callback(Studio.Theme:GetColor(item, modifier))
		end
		update()
		return Studio.ThemeChanged:Connect(update)
	end
	
	local function BindPath(item, modifier, callback)
		if callback == nil then return BindPath(item, "Default", modifier) end
		
		item = Enum.StudioStyleGuideColor[item]
		modifier = Enum.StudioStyleGuideModifier[modifier]
		
		local function update()
			callback(Studio.Theme:GetPath(item, modifier))
		end
		update()
		return Studio.ThemeChanged:Connect(update)
	end
	
	local function BindToInstance(conn, ins)
		ins.AncestryChanged:Connect(function()
			if not ins.Parent then
				conn:Disconnect()
			end
		end)
	end
	
	local function BindToPlugin(conn)
		plugin.Unloading:Connect(function()
			conn:Disconnect()
		end)
	end
	
	local _TweenInstantly = true
	local function Tween(ins, properties, easingStyle, easingDirection, tm)
		local tweenInfo = TweenInfo.new(_TweenInstantly and 0 or tm, Enum.EasingStyle[easingStyle], Enum.EasingDirection[easingDirection])
		local tween = TweenService:Create(ins, tweenInfo, properties)
		tween:Play()
	end
	
	local function Ease(x, direction)
		if direction < 0 then
			return x^2
		end
		return 1-(1-x)^2
	end
	
	--[[
		
		UIManager
		Responsible for handling the plugin's UI.
		
	--]]
	
	local UIManager = {}
	
	UIManager.messages = {
		noSelection = {message = "Nothing's selected yet!", icon = ""},
		lockedInstances = {message = "Can't convert locked instances.", icon = ""},
		noSuggestions = {message = "No suggestions for this class type.", icon = ""},
		noClassesFound = {message = "No classes found.", icon = ""},
		manyClasses = {message = "Multiple class types selected; no suggestions.", icon = ""},
		httpNeeded = {message = "Reclass needs HTTP permissions to access the latest API dump.\n\n(did you grant Reclass permission to send HTTP requests?)", icon = ""},
		downloadingApi = {message = "Downloading API dump...", icon = ""},
		apiError = {message = "There was an error while accessing the latest API dump. Check the output log for more information.", icon = ""},
		disableOnTest = {message = "Reclass is disabled during Play Solo and other offline modes.", icon = ""}
	}
	
	UIManager.icons = {
		convert = {
			light = "",
			dark = ""
		},
		automatic = {
			light = "",
			dark = ""
		}
	}
	
	UIManager.currentFindClassText = ""
	UIManager.isMessageVisible = false
	UIManager.isConvertButtonEnabled = false
	UIManager.onConvertWidgetShown = Instance.new "BindableEvent"
	UIManager.onConvertButtonClicked = Instance.new "BindableEvent"
	UIManager.onRetryButtonClicked = Instance.new "BindableEvent"
	UIManager.onAutoConvertButtonClicked = Instance.new "BindableEvent"
	UIManager.onFindClassChanged = Instance.new "BindableEvent"
	UIManager.selectedListItem = nil
	UIManager.listItems = {}
	
	function UIManager:init()
		_TweenInstantly = true
		
		self.toolbar = plugin:CreateToolbar "Reclass"
		
		local iconTheme = self:getCurrentIconTheme()
		self.buttons = {
			Convert = self.toolbar:CreateButton("Convert", "Change the class type of the selected instances", self.icons.convert[iconTheme]),
			Automatic = self.toolbar:CreateButton("Automatic", "Change the selected instances to the recommended class type", self.icons.automatic[iconTheme])
		}
		Studio.ThemeChanged:Connect(function()
			local iconTheme = self:getCurrentIconTheme()
			self.buttons.Convert.Icon = self.icons.convert[iconTheme]
			self.buttons.Automatic.Icon = self.icons.automatic[iconTheme]
		end)
		
		for _, button in pairs(self.buttons) do
			button.ClickableWhenViewportHidden = true
		end
		
		self.widget = MakeWidget(Package.UI.ReclassGui, "ReclassConvert", DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Float, false, false,
			225, 200, 225, 200
		), "Reclass")
			
--		self.optionsWidget = MakeWidget(Package.UI.OptionsGui, "ReclassOptions", DockWidgetPluginGuiInfo.new(
--			Enum.InitialDockState.Float, false, false,
--			225, 200, 225, 200
--		), "Reclass Options")
			
		self:initWidgets()
		self:initTheme()
		
		self.buttons.Convert.Click:Connect(function()
			self.widget.Enabled = not self.widget.Enabled
		end)
		
		self.buttons.Automatic.Click:Connect(function()
			UIManager.onAutoConvertButtonClicked:Fire()
		end)
		
		self.widget:GetPropertyChangedSignal "Enabled":Connect(function()
			self.buttons.Convert:SetActive(self.widget.Enabled)
			if self.widget.Enabled then
				UIManager.onConvertWidgetShown:Fire()
			end
		end)
		
		_TweenInstantly = false
	end
	
	function UIManager:isConvertWidgetShown()
		return self.widget.Enabled
	end
	
	function UIManager:getListItem(className)
		if UIManager.listItems[className] then
			return UIManager.listItems[className]
		end
		
		local listItemObj = {className = className}
		
		local gui = Package.UI.ListItem:Clone()
		gui.Name = className
		gui.ItemName.Text = className
		
		local iconData = StudioService:GetClassIcon(className)
		gui.Icon.Image = iconData.Image
		gui.Icon.ImageRectOffset = iconData.ImageRectOffset
		gui.Icon.ImageRectSize = iconData.ImageRectSize
		
		function listItemObj:setVisible(visible)
			gui.Visible = visible
			if not visible then
				self:setSelected(false)
			end
		end
		
		function listItemObj:setOrder(order)
			gui.LayoutOrder = order
		end
		
		function listItemObj:setSelected(isSelected)
			if UIManager.selectedListItem == self then
				UIManager.selectedListItem = nil
				UIManager:setConvertButtonEnabled(false)
			end
			if isSelected then
				UIManager:setConvertButtonEnabled(true)
			end
			Tween(gui.Background, {ImageTransparency = isSelected and 0.5 or 1}, "Quad", "Out", 0.1)
		end
		
		function listItemObj:setSuggested(isSuggested)
			Tween(gui.SuggestedBorder, {ImageTransparency = isSuggested and 0.25 or 1}, "Quad", "Out", 0.2)
			Tween(gui.SuggestedIcon, {ImageTransparency = isSuggested and 0 or 1}, "Quad", "Out", 0.2)
			if isSuggested then
				gui.LayoutOrder = gui.LayoutOrder-9999
			end
		end
		
		BindToInstance(BindColour("MainText", function(c)
			gui.ItemName.TextColor3 = c
		end), gui)
		
		gui.MouseEnter:Connect(function()
			Tween(gui.HoverBorder, {ImageTransparency = 0.75}, "Quad", "Out", 0.02)
		end)
		
		gui.MouseLeave:Connect(function()
			Tween(gui.HoverBorder, {ImageTransparency = 1}, "Quad", "Out", 0.2)
		end)
		
		gui.Activated:Connect(function()
			if UIManager.selectedListItem then
				UIManager.selectedListItem:setSelected(false)
			end
			listItemObj:setSelected(true)
			UIManager.selectedListItem = listItemObj
		end)
		
		gui.Parent = self.widget.Main.ScrollArea
		
		UIManager.listItems[className] = listItemObj
		return listItemObj
	end
	
	function UIManager:setConvertButtonEnabled(canConvert)
		self.isConvertButtonEnabled = canConvert
		if UIManager.isMessageVisible then return end
		Tween(self.widget.Convert, {ImageTransparency = canConvert and 0 or 0.75}, "Quad", "Out", canConvert and 0.1 or 0.2)
		Tween(self.widget.Convert.Label, {TextTransparency = canConvert and 0 or 0.75}, "Quad", "Out", canConvert and 0.1 or 0.2)
	end
	
	function UIManager:setRetryButtonVisible(visible)
		self.widget.Retry.Visible = visible
	end
	
	function UIManager:setUpdateNoticeVisible(visible)
		local updateNotice = self.widget.UpdateNotice
		Tween(updateNotice, {Size = UDim2.new(updateNotice.Size.X, UDim.new(0, visible and 24 or 0))}, "Quart", "Out", 0.3)
		Tween(self.widget.Main.ScrollArea.UIPadding, {PaddingTop = UDim.new(0, visible and 24 + 4 or 0)}, "Quart", "Out", 0.3)
	end
	
	function UIManager:setListItemsVisible(visibleItems)
		local shouldKeepItem = {}
		for item, order in pairs(visibleItems) do
			local li = UIManager:getListItem(item)
			li:setVisible(true)
			li:setSuggested(false)
			li:setOrder(order)
			shouldKeepItem[item] = true
		end
		for _, item in pairs(UIManager.listItems) do
			if not shouldKeepItem[item.className] then
				item:setVisible(false)
			end
		end
	end
	
	function UIManager:setMessage(messageData)
		local updateNotice = self.widget.UpdateNotice
		if messageData == nil then
			UIManager.isMessageVisible = false
			self.widget.Message.Visible = false
			self.widget.Main.Visible = true
			Tween(updateNotice, {Size = UDim2.new(UDim.new(1, -16), updateNotice.Size.Y)}, "Quart", "Out", 0.3)
			
			Tween(self.widget.Convert, {ImageTransparency = self.isConvertButtonEnabled and 0 or 0.75}, "Quad", "Out", 0.1)
			Tween(self.widget.Convert.Label, {TextTransparency = self.isConvertButtonEnabled and 0 or 0.75}, "Quad", "Out", 0.1)
		else
			local message, icon = messageData.message, messageData.icon
			UIManager.isMessageVisible = true
			
			Tween(self.widget.Convert, {ImageTransparency = 0.75}, "Quad", "Out", 0.1)
			Tween(self.widget.Convert.Label, {TextTransparency = 0.75}, "Quad", "Out", 0.1)
			
			self.widget.Message.Text.Text = message
			self.widget.Message.Icon.Image = icon
			self.widget.Message.Visible = true
			self.widget.Main.Visible = false
			Tween(updateNotice, {Size = UDim2.new(UDim.new(1, -8), updateNotice.Size.Y)}, "Quart", "Out", 0.3)
		end
	end
	
	function UIManager:initWidgets()
		
		-- Convert window
		do
			self.widget.Retry.Activated:Connect(function()
				UIManager.onRetryButtonClicked:Fire()
			end)
			
			self.widget.FindClass.TextBox:GetPropertyChangedSignal "Text":Connect(function()
				UIManager.currentFindClassText = self.widget.FindClass.TextBox.Text
				UIManager.onFindClassChanged:Fire(self.widget.FindClass.TextBox.Text)
				local isEmpty = self.widget.FindClass.TextBox.Text:len() < 1
				Tween(self.widget.FindClass.Placeholder, {TextTransparency = isEmpty and 0.5 or 1, Position = UDim2.new(isEmpty and 0 or 0.1, 6, 0, 0)}, "Quad", "Out", 0.2)
			end)
			
			local function updateMessageSize()
				local textBounds = TextService:GetTextSize(self.widget.Message.Text.Text, self.widget.Message.Text.TextSize, self.widget.Message.Text.Font, Vector2.new(self.widget.Message.Text.AbsoluteSize.X, 9999))
				self.widget.Message.Text.Size = UDim2.new(1, 0, 0, textBounds.Y)
			end
			updateMessageSize()
			self.widget.Message.Text:GetPropertyChangedSignal "Text":Connect(updateMessageSize)
			self.widget.Message.Text:GetPropertyChangedSignal "AbsoluteSize":Connect(updateMessageSize)
			
			self.widget.Convert.Activated:Connect(function()
				if self.isConvertButtonEnabled and not UIManager.isMessageVisible then
					UIManager.onConvertButtonClicked:Fire(UIManager.selectedListItem)
				end
			end)
			
			local listLayout = self.widget.Main.ScrollArea:FindFirstChildWhichIsA "UIListLayout"
			local function updateListSize()
				self.widget.Main.ScrollArea.CanvasSize = UDim2.new(0, listLayout.AbsoluteContentSize.X, 0, listLayout.AbsoluteContentSize.Y)
			end
			updateListSize()
			listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateListSize)
			
			SmoothScroll(self.widget.Main.ScrollArea, 0.35)
			
			self:setConvertButtonEnabled(false)
			self:setMessage(UIManager.messages.downloadingAPI)
		end
		
		-- Options window
--		do
--			local listLayout = self.optionsWidget.Main.ScrollArea:FindFirstChildWhichIsA "UIListLayout"
--			local function updateListSize()
--				self.optionsWidget.Main.ScrollArea.CanvasSize = UDim2.new(0, listLayout.AbsoluteContentSize.X, 0, listLayout.AbsoluteContentSize.Y)
--			end
--			updateListSize()
--			listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateListSize)
--			
--			SmoothScroll(self.optionsWidget.Main.ScrollArea, 0.35)
--			
--			
--			self.optionsWidget.Close.Activated:Connect(function()
--				self.optionsWidget.Enabled = false
--			end)
--		end
	end
	
	function UIManager:getCurrentIconTheme()
		local mainBackground = Studio.Theme:GetColor("MainBackground")
		local isDarkTheme = mainBackground.r + mainBackground.g + mainBackground.b < 1.5
		return isDarkTheme and "dark" or "light"
	end
	
	function UIManager:initTheme()
		BindToPlugin(BindColour("MainBackground", function(c)
			self.widget.Background.BackgroundColor3 = c
		end))
		
		BindToPlugin(BindColour("MainText", function(c)
			self.widget.FindClass.ImageColor3 = c
			self.widget.FindClass.TextBox.TextColor3 = c
			self.widget.FindClass.Placeholder.TextColor3 = c
			self.widget.Message.Text.TextColor3 = c
			self.widget.Main.ScrollArea.ScrollBarImageColor3 = c
		end))
		
		BindToPlugin(BindColour("Mid", function(c)
			self.widget.Main.ScrollTrack.ImageColor3 = c
		end))
	end
	
	function UIManager:destroy()
		for _, button in pairs(self.buttons) do
			button:Destroy()
		end
		self.toolbar:Destroy()
		self.widget:Destroy()
	end
	
	return UIManager
	
end