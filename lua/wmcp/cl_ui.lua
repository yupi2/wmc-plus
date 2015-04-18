function wmcp.OpenUI()
	local fr = vgui.Create("DFrame")
	fr:SetSkin("WMCPUI")
	fr:SetTitle("Wyozi Media Center +")
	fr:SetSizable(true)

	fr:SetSize(900, 600)
	fr:Center()

	wmcp.CreateMediaList(fr)
	wmcp.CreatePlayer(fr)

	fr:MakePopup()

	wmcp.Frame = fr

	hook.Call("WMCPPostOpenUI", nil, fr)

	fr.OnClose = function()
		hook.Call("WMCPPreCloseUI", nil, fr)
	end
end

function wmcp.IsOpen()
	return IsValid(wmcp.Frame) and wmcp.Frame:IsVisible()
end

function wmcp.CloseUI()
	if not IsValid(wmcp.Frame) then return end

	wmcp.Frame:Close()
end

concommand.Add("wmcp", function()
	wmcp.OpenUI()
end)

local t = nettable.get("WMCPMedia.Main")
function wmcp.CreateMediaList(par)
	local medialist = par:Add("DListView")
	medialist:SetHeaderHeight(22)
	medialist:SetDataHeight(22)
	medialist:SetMultiSelect(false)
	medialist:Dock(FILL)
	medialist:AddColumn("ID")
	medialist:AddColumn("Title")
	medialist:AddColumn("Added by")
	medialist.Columns[1]:SetFixedWidth(20)
	medialist.Columns[3]:SetFixedWidth(150)

	-- Remove sorting by removing DButton functionality. This retains WMCPUI skin
	for _,v in pairs(medialist.Columns) do v.DoClick = function() end end

	local olddl = medialist.DataLayout
	medialist.DataLayout = function(self)
		table.Copy(self.Sorted, self.Lines)
		table.sort(self.Sorted, function(a, b)
			local aval = tonumber(a:GetColumnText(1))
			local bval = tonumber(b:GetColumnText(1))
			if not aval then return false end
			if not bval then return true end
			return  aval < bval
		end)

		--PrintTable(self.Sorted)
		return olddl(self)
	end

	-- Add "add new video" entry as the last row
	do
		local adder = vgui.Create("DButton")
		adder:SetSkin("WMCPUI")
		adder:SetText("Add new video by clicking here")
		adder.DoClick = function()
			Derma_StringRequest("Video adder", "Please input an URL", "", function(url)
				RunConsoleCommand("wmcp_add", url)
			end)
		end
		medialist:AddLine("", adder, nil)
	end

	function medialist:DoDoubleClick(id, line)
		if not line.MediaId then return end
		
		wmcp.Play(line.Url, {title = line:GetColumnText(2)})
	end

	function medialist:OnRowRightClick(id, line)
		if not line.MediaId then return end
		
		local menu = DermaMenu()

		menu:AddOption("Play", function()
			wmcp.Play(line.Url, {title = line:GetColumnText(2)})
		end):SetImage("icon16/control_play.png")

		menu:AddOption("Play for Everyone", function()
			RunConsoleCommand("wmcp_play", line.Url, line:GetColumnText(2))
		end):SetImage("icon16/control_play_blue.png")

		menu:AddSpacer()

		menu:AddOption("Copy URL", function()
			SetClipboardText(line.Url)
		end):SetImage("icon16/paste_plain.png")

		menu:AddSpacer()

		menu:AddOption("Set title", function()
			local title = line:GetColumnText(2)
			Derma_StringRequest("WMCP: Set title", "Set title of '" .. title .. "'", title, function(newTitle)
				RunConsoleCommand("wmcp_settitle", line.MediaId, newTitle)
			end)
		end):SetImage("icon16/monitor_edit.png")
		menu:AddOption("Delete", function()
			RunConsoleCommand("wmcp_del", line.MediaId)
		end):SetImage("icon16/monitor_delete.png")

		menu:Open()
	end

	local function ModLine(id, media)
		local line
		for _,iline in pairs(medialist.Lines) do
			if iline.MediaId == id then
				line = iline
				break
			end
		end

		if not line then
			line = medialist:AddLine(id)
			line:SetCursor("hand")
		end

		line.MediaId = id

		if media.title then
			line:SetColumnText(2, media.title):SetFont("WMCPUINormalFont")
		end
		if media.a_sid and media.a_nick then
			local plycell = line:Add("WMCPlayerCell")
			plycell.NickLabel:SetFont("WMCPUINormalFont")
			plycell:SetSIDNick(media.a_sid, media.a_nick)
			line:SetColumnText(3, plycell)
		end
		if media.url then
			line.Url = media.url
		end
	end

	for id,media in pairs(t) do
		ModLine(id, media)
	end

	nettable.setChangeListener(t, "UIUpdater", function(e)
		if not IsValid(medialist) then return end

		for id, media in pairs(e.modified) do
			ModLine(id, media)
		end
		for id,_ in pairs(e.deleted) do
			local lineid
			for _,line in pairs(medialist.Lines) do if line.MediaId == id then lineid = line:GetID() break end end

			if lineid then medialist:RemoveLine(lineid) end
		end
	end)

	return medialist
end

surface.CreateFont("WMCPMediaTitle", {
	font = "Roboto",
	size = 22
})
function wmcp.CreatePlayer(par)
	local player = par:Add("DPanel")
	par.Player = player

	player:Dock(BOTTOM)
	player:SetTall(50)

	player.Seeker = player:Add("WMCMediaSeeker")
	player.Seeker.OnSeeked = function(_, frac)
		local clip = wmcp.GetClip()
		local meta = wmcp.GetClipMeta()
		if IsValid(clip) and meta and meta.duration then
			clip:seek(meta.duration * frac)
		end
	end

	player.VolSeeker = player:Add("WMCMediaSeeker")
	player.VolSeeker:SetDuration(100)
	player.VolSeeker:SetElapsed(wmcp.GetVolume()*100)
	player.VolSeeker.OnSeeking = function(pself, frac)
		pself:SetElapsed(frac * 100)
		wmcp.SetVolume(frac)
	end
	player.VolSeeker.OnSeeked = player.VolSeeker.OnSeeking

	player.Title = player:Add("DLabel")
	player.Title:SetFont("WMCPMediaTitle")
	player.Title:SetText("")

	player.Play = player:Add("DButton")
	player.Play:SetText("Play")
	player.Play.DoClick = function()
		wmcp.TogglePlay()
	end

	function player:Think()
		local clip = wmcp.GetClip()
		if IsValid(clip) and clip:isPlaying() then
			player.Play:SetText("Pause")
		else
			player.Play:SetText("Play")
		end

		local meta = wmcp.GetClipMeta()
		if meta and meta.title then
			player.Title:SetText(meta.title)
		end
		
		if IsValid(clip) then
			player.Seeker:SetElapsed(clip:getTime())
		end
		if meta and meta.duration then
			player.Seeker:SetDuration(meta.duration)
		end
	end
	function player:PerformLayout()
		local mid = self:GetWide() / 2
		self.Play:SetPos(5, 22)
		self.Play:SetSize(100, 25)

		self.Title:SetPos(115, 22)
		self.Title:SetSize(self:GetWide() - 210, 26)

		self.Seeker:SetPos(5, 4)
		self.Seeker:SetSize(self:GetWide() - 10, 16)

		self.VolSeeker:SetPos(self:GetWide() - 105, 22)
		self.VolSeeker:SetSize(100, 25)
	end
end