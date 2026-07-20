ITEM.name = "PDA"
ITEM.model = "models/lostsignalproject/items/devices/pda.mdl"
ITEM.width = 1
ITEM.height = 1
ITEM.category = "Comunicação"
ITEM.price = 1000
ITEM.busflag = {"hardware"}
ITEM.equipIcon = ix.util.GetMaterial("materials/vgui/ui/stalker/misc/equip.png")
ITEM.img = ix.util.GetMaterial("vgui/hud/pda1.png")
ITEM.repairCost = ITEM.price/100*1

function ITEM:GetDescription()
	return "Um PDA que incentiva a comunicação de longo alcance entre indivíduos. Sendo a versão mais recente da série PDA, isso permite que o usuário selecione um avatar e também seu próprio nome de usuário." .. "\n\nAvatar: " .. self:GetData("avatar","vgui/icons/face_31.png") .. "\n\nNickname: " .. self:GetData("nickname", "meme")
end

-- ====================================================================
-- Rede: pedido/abertura do seletor visual de avatar (SERVER -> CLIENT)
-- e confirmação da escolha (CLIENT -> SERVER)
-- ====================================================================

-- aceita "face_31.png" e "face31.png" (com ou sem underline)
local AVATAR_PATTERN = "^vgui/icons/face_?%d+%.png$"

if (SERVER) then
	util.AddNetworkString("ixPDARequestAvatar")
	util.AddNetworkString("ixPDASetAvatar")

	net.Receive("ixPDASetAvatar", function(length, client)
		local itemID = net.ReadUInt(32)
		local avatarPath = net.ReadString()

		-- valida o formato do caminho antes de aceitar qualquer coisa
		if (!string.match(avatarPath, AVATAR_PATTERN)) then
			return
		end

		local item = ix.item.instances[itemID]

		if (!item or item.uniqueID != "pda") then
			return
		end

		-- garante que quem está mandando o net é realmente o dono do item
		local owner = item:GetOwner()

		if (owner != client) then
			return
		end

		item:SetData("avatar", avatarPath)

		if (IsValid(client) and client:GetCharacter()) then
			-- SetPdaavatar já foi gerado pelo ix.char.RegisterVar (field = "pdaavatar")
			-- e cuida de persistir + sincronizar sozinho, então não repetimos com SetData.
			client:GetCharacter():SetPdaavatar(avatarPath)
		end
	end)
end

if (CLIENT) then
	-- ================================================================
	-- Texturas do painel (materials/cotz/panels/...)
	-- Troque os nomes abaixo se seus arquivos reais forem diferentes.
	-- ================================================================
	local MAT_FUNDO = Material("cotz/panels/frame1.png")
	local MAT_BOTAO_FECHA = Material("cotz/panels/button3_1.png")
	local MAT_BOTAO_SELECIONA = Material("cotz/panels/button3_2.png")

	-- margem interna do grid dentro do fundo.png (ajuste conforme a moldura da sua arte)
	local GRID_MARGIN_TOP = 50
	local GRID_MARGIN_SIDES = 20
	local GRID_MARGIN_BOTTOM = 60

	local PANEL_SIZE = 72
	local PANEL_SPACING = 8

	-- nomes de arquivo que não devem aparecer na lista (ex: placeholder "sem foto")
	local EXCLUDED_FILES = {
		["face_31.png"] = true,
	}

	-- pega o tamanho nativo da textura de fundo, com fallback caso o arquivo não exista ainda
	local function GetMatSize(mat, fallbackW, fallbackH)
		local w, h = mat:Width(), mat:Height()

		if (!w or !h or w <= 1 or h <= 1) then
			return fallbackW, fallbackH
		end

		return w, h
	end

	local function CreateImageButton(parent, mat, w, h)
		local btn = vgui.Create("DButton", parent)
		btn:SetText("")
		btn:SetSize(w, h)

		btn.Paint = function(self, pw, ph)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect(0, 0, pw, ph)

			if (self:IsHovered()) then
				surface.SetDrawColor(255, 255, 255, 30)
				surface.DrawRect(0, 0, pw, ph)
			end
		end

		return btn
	end

	local function OpenPDAAvatarPicker(currentAvatar, itemID)
		if (IsValid(ixPDAAvatarPickerFrame)) then
			ixPDAAvatarPickerFrame:Remove()
		end

		local frameW, frameH = GetMatSize(MAT_FUNDO, 760, 500)

		local frame = vgui.Create("DFrame")
		frame:SetSize(frameW, frameH)
		frame:SetSizable(false) -- fundo.png é uma imagem fixa, não faz sentido esticar
		frame:Center()
		frame:SetTitle("Selecionar Avatar")
		frame:ShowCloseButton(false)
		frame:MakePopup()
		frame:SetDeleteOnClose(true)
		ixPDAAvatarPickerFrame = frame

		frame.Paint = function(self, w, h)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(MAT_FUNDO)
			surface.DrawTexturedRect(0, 0, w, h)
		end

		local scroll = vgui.Create("DScrollPanel", frame)
		scroll:SetPos(GRID_MARGIN_SIDES, GRID_MARGIN_TOP)
		scroll:SetSize(frameW - GRID_MARGIN_SIDES * 2, frameH - GRID_MARGIN_TOP - GRID_MARGIN_BOTTOM)

		local grid = vgui.Create("DIconLayout", scroll)
		grid:Dock(TOP)
		grid:SetSpaceX(PANEL_SPACING)
		grid:SetSpaceY(PANEL_SPACING)
		grid:SetStretchWidth(false)

		local selected = currentAvatar

		-- junta os dois formatos de nome (com e sem underline) numa lista só, sem duplicar
		local seen = {}
		local files = {}

		for _, fileName in ipairs(file.Find("materials/vgui/icons/face_*.png", "GAME")) do
			if (!seen[fileName] and !EXCLUDED_FILES[fileName]) then
				seen[fileName] = true
				files[#files + 1] = fileName
			end
		end

		for _, fileName in ipairs(file.Find("materials/vgui/icons/face*.png", "GAME")) do
			if (!seen[fileName] and !EXCLUDED_FILES[fileName]) then
				seen[fileName] = true
				files[#files + 1] = fileName
			end
		end

		table.sort(files, function(a, b)
			local numA = tonumber(string.match(a, "%d+")) or 0
			local numB = tonumber(string.match(b, "%d+")) or 0

			return numA < numB
		end)

		if (#files == 0) then
			local warn = vgui.Create("DLabel", grid)
			warn:SetText("Nenhuma imagem encontrada em vgui/icons/face*.png")
			warn:SetTextColor(color_white)
			warn:SizeToContents()
		end

		for _, fileName in ipairs(files) do
			local path = "vgui/icons/" .. fileName

			local icon = grid:Add("DButton")
			icon:SetText("")
			icon:SetSize(PANEL_SIZE, PANEL_SIZE)
			icon.avatarPath = path

			icon.Paint = function(self, w, h)
				if (selected == self.avatarPath) then
					surface.SetDrawColor(70, 130, 220, 255)
				elseif (self:IsHovered()) then
					surface.SetDrawColor(60, 60, 60, 200)
				else
					surface.SetDrawColor(35, 35, 35, 200)
				end

				surface.DrawRect(0, 0, w, h)

				if (selected == self.avatarPath) then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.DrawOutlinedRect(0, 0, w, h, 2)
				end
			end

			local img = vgui.Create("DImage", icon)
			img:SetSize(PANEL_SIZE - 8, PANEL_SIZE - 8)
			img:SetPos(4, 4)
			img:SetMaterial(Material(path))
			img:SetMouseInputEnabled(false)

			icon.DoClick = function(self)
				surface.PlaySound("stalkersound/pda/pda_tip.wav")
				selected = self.avatarPath
			end
		end

		-- ------------------------------------------------------------
		-- Botões de imagem (fecha / seleciona) na parte de baixo do fundo.png
		-- ------------------------------------------------------------
		local btnW, btnH = GetMatSize(MAT_BOTAO_SELECIONA, 140, 40)
		local btnFecharW, btnFecharH = GetMatSize(MAT_BOTAO_FECHA, 140, 40)

		local selectButton = CreateImageButton(frame, MAT_BOTAO_SELECIONA, btnW, btnH)
		selectButton:SetPos(frameW - GRID_MARGIN_SIDES - btnW, frameH - btnH - 12)
		selectButton:SetText("Selecionar")
		selectButton:SetFont("stalkerregularfont2")
		selectButton.DoClick = function()
			if (!selected or selected == "") then
				return
			end

			net.Start("ixPDASetAvatar")
				net.WriteUInt(itemID, 32)
				net.WriteString(selected)
			net.SendToServer()
			surface.PlaySound("stalkersound/pda/pda_update.wav")
			frame:Close()
		end

		local cancelButton = CreateImageButton(frame, MAT_BOTAO_FECHA, btnFecharW, btnFecharH)
		cancelButton:SetPos(GRID_MARGIN_SIDES, frameH - btnFecharH - 12)
		cancelButton:SetText("Cancelar")
		cancelButton:SetFont("stalkerregularfont2")
		cancelButton.DoClick = function()
			surface.PlaySound("stalkersound/pda/pda_tip.wav")
			frame:Close()
		end
	end

	ix.pda = ix.pda or {}
	ix.pda.OpenAvatarPicker = OpenPDAAvatarPicker

	net.Receive("ixPDARequestAvatar", function(length)
		local currentAvatar = net.ReadString()
		local itemID = net.ReadUInt(32)

		OpenPDAAvatarPicker(currentAvatar, itemID)
	end)
end

ITEM.functions.setavatar = { -- sorry, for name order.
	name = "Selecionar Avatar",
	tip = "useTip",
	icon = "icon16/stalker/customize.png",
	OnRun = function(item)
		-- OnRun de item roda só no servidor; o cliente abre o
		-- seletor quando recebe o net "ixPDARequestAvatar" abaixo.
		local client = item.player

		net.Start("ixPDARequestAvatar")
			net.WriteString(item:GetData("avatar", "vgui/icons/face_31.png"))
			net.WriteUInt(item.id, 32)
		net.Send(client)

		return false
	end,
	OnCanRun = function(item)
		local client = item.player

		return !IsValid(item.entity) and IsValid(client)
	end
}

ITEM.functions.setnickname = { -- sorry, for name order.
	name = "Defina seu apelido",
	tip = "useTip",
	icon = "icon16/stalker/customize.png",
	OnRun = function(item)
		item.player:RequestString("Set Nickname", "Qual apelido você gostaria de usar com este PDA?", function(text)
			item:SetData("nickname", text)
			item:GetOwner():GetCharacter():SetData("pdanickname", text)
		end, item:GetData("nickname", item.player:Name()))
		return false
	end,
}

function ITEM:OnEquipped()
	self.player:GetCharacter():SetData("pdaavatar", self:GetData("avatar", "lutz"))
	self.player:GetCharacter():SetData("pdanickname", self:GetData("nickname", "lutz"))
end

function ITEM:OnUnEquipped()

end

function ITEM:OnInstanced()
	self:SetData("avatar", "vgui/icons/face_31.png")
	self:SetData("nickname", "NEW_USER")
end
