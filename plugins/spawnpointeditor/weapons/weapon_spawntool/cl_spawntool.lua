--[[
	Como funciona:

	- Cada "modo" (caixa, stash, radiação, anomalia, evento, container) tem uma
	  função getAddArgs() e (quando aplicável) getRemoveArgs() que leem os
	  valores atuais dos campos do painel de configurações.
	- O painel é criado UMA vez e só fica oculto/visível (não é destruído),
	  então os valores escolhidos continuam valendo mesmo com o painel fechado
	  — exatamente como o toolgun de sandbox guarda a config no Q menu.
	- Clique esquerdo/direito chamam ix.command.Send com os mesmos comandos que
	  já existiam nos plugins originais (boxspawnadd, stashspawneradd, etc), só
	  isso. As permissões continuam sendo checadas no servidor normalmente.
]]

local modeDefs = {} -- modeDefs[modeId] = { addCmd, getAddArgs, removeCmd, getRemoveArgs }
local activeIndex = 1
local settingsFrame
local sheet

-- -----------------------------------------------------------------------
-- Helpers de layout
-- -----------------------------------------------------------------------

local function FieldLabel(parent, text)
	local lbl = vgui.Create("DLabel", parent)
	lbl:Dock(TOP)
	lbl:DockMargin(4, 6, 4, 2)
	lbl:SetText(text)
	lbl:SetTextColor(Color(210, 210, 210))
	return lbl
end

local function HelpText(parent, text)
	local lbl = vgui.Create("DLabel", parent)
	lbl:Dock(TOP)
	lbl:DockMargin(4, 4, 4, 6)
	lbl:SetText(text)
	lbl:SetWrap(true)
	lbl:SetAutoStretchVertical(true)
	lbl:SetTextColor(Color(255, 255, 255))
	return lbl
end

local function Combo(parent, label)
	FieldLabel(parent, label)
	local combo = vgui.Create("DComboBox", parent)
	combo:Dock(TOP)
	combo:DockMargin(4, 0, 4, 2)
	combo:SetTall(26)
	return combo
end

local function TextEntry(parent, label, placeholder)
	FieldLabel(parent, label)
	local entry = vgui.Create("DTextEntry", parent)
	entry:Dock(TOP)
	entry:DockMargin(4, 0, 4, 2)
	entry:SetTall(26)
	if placeholder then entry:SetPlaceholderText(placeholder) end

	-- O painel fica com o teclado desativado (pra não travar o movimento
	-- do jogador enquanto ele mira e atira com a ferramenta), então aqui a
	-- gente reativa só enquanto o campo estiver focado.
	entry.OnGetFocus = function(self)
		if IsValid(settingsFrame) then settingsFrame:SetKeyboardInputEnabled(true) end
	end
	entry.OnLoseFocus = function(self)
		if IsValid(settingsFrame) then settingsFrame:SetKeyboardInputEnabled(false) end
	end

	return entry
end

local function NumberWang(parent, label, min, max, default)
	FieldLabel(parent, label)
	local wang = vgui.Create("DNumberWang", parent)
	wang:Dock(TOP)
	wang:DockMargin(4, 0, 4, 2)
	wang:SetTall(26)
	wang:SetMin(min)
	wang:SetMax(max)
	wang:SetValue(default)
	return wang
end

local function CheckboxGrid(parent, defs)
	local list = vgui.Create("DPanel", parent)
	list:Dock(TOP)
	list.Paint = function() end
	list:SetTall(#defs * 22 + 4)

	local checks = {}
	for i = 1, #defs do
		local def = defs[i]
		local chk = vgui.Create("DCheckBoxLabel", list)
		chk:SetPos(4, (i - 1) * 22)
		chk:SetText(string.format("%d - %s", i, def.name or def.entityname or "?"))
		chk:SetValue(false)
		chk:SizeToContents()
		checks[i] = chk
	end

	return checks
end

local function Bitstring(defs, checks)
	local str = ""
	for i = 1, #defs do
		str = str .. ((checks[i] and checks[i]:GetChecked()) and "1" or "0")
	end
	return str
end

local function NewTab(sheetPanel, id, label, icon)
	local scroll = vgui.Create("DScrollPanel")
	sheetPanel:AddSheet(label, scroll, icon)
	return scroll
end

-- -----------------------------------------------------------------------
-- Definição de cada modo (aba). Cada bloco monta os campos e registra
-- getAddArgs / getRemoveArgs em modeDefs.
-- -----------------------------------------------------------------------

local function BuildBoxMode(sheetPanel)
	local p = NewTab(sheetPanel, "box", "Caixas", "icon16/box.png")

	HelpText(p, "Esquerdo: adiciona uma caixa na mira. Direito: remove pontos próximos.")

	local typeCombo = Combo(p, "Tipo de caixa")
	typeCombo:AddChoice("Pequena (ix_entbox)", 1)
	typeCombo:AddChoice("Grande (madeira / papel)", 2)
	typeCombo:ChooseOptionID(1)

	local group = TextEntry(p, "Grupo customizado (opcional)", "deixe vazio para nenhum")
	local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

	modeDefs.box = {
		addCmd = "boxspawnadd",
		getAddArgs = function()
			local _, typeId = typeCombo:GetSelected()
			local args = { typeId or 1 }
			local g = group:GetValue()
			if g ~= "" then args[#args + 1] = g end
			return args
		end,
		removeCmd = "boxspawnremove",
		getRemoveArgs = function() return { radius:GetValue() } end,
	}
end

local function BuildStashMode(sheetPanel)
	local p = NewTab(sheetPanel, "stash", "Stash Escondido", "icon16/box_closed.png")

	HelpText(p, "Esquerdo: adiciona um ponto de stash escondido. Direito: remove próximos.")

	local stashPlugin = ix.plugin.list["hidestashspawner"]
	local categoryCombo = Combo(p, "Categoria de loot")

	if stashPlugin and stashPlugin.StashItems then
		local keys = {}
		for k in pairs(stashPlugin.StashItems) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do categoryCombo:AddChoice(k, k) end
		if keys[1] then categoryCombo:ChooseOption(keys[1], 1) end
	end

	local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

	modeDefs.stash = {
		addCmd = "stashspawneradd",
		getAddArgs = function()
			local text = categoryCombo:GetSelected()
			if not text or text == "" then return nil end
			return { text }
		end,
		removeCmd = "stashspawnerremove",
		getRemoveArgs = function() return { radius:GetValue() } end,
	}
end

local function BuildRadiationMode(sheetPanel)
	local p = NewTab(sheetPanel, "radiation", "Radiação", "icon16/error.png")

	HelpText(p, "Marque os tipos permitidos. Esquerdo: adiciona ponto. Direito: remove próximos.")

	local radPlugin = ix.plugin.list["radiationcontroller"]
	local checks = {}

	if radPlugin and radPlugin.radiationdefs then
		checks = CheckboxGrid(p, radPlugin.radiationdefs)
	end

	local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

	modeDefs.radiation = {
		addCmd = "radiationadd",
		getAddArgs = function()
			if not radPlugin then return nil end
			return { Bitstring(radPlugin.radiationdefs, checks) }
		end,
		removeCmd = "radiationremove",
		getRemoveArgs = function() return { radius:GetValue() } end,
	}
end

local function BuildAnomalyMode(sheetPanel)
	local p = NewTab(sheetPanel, "anomaly", "Anomalias", "icon16/asterisk_yellow.png")

	HelpText(p, "Defina o raio da área e marque as anomalias permitidas nela.")

	local anomPlugin = ix.plugin.list["anomalycontroller"]
	local areaRadius = NumberWang(p, "Raio da área", 8, 4096, 256)

	local checks = {}
	if anomPlugin and anomPlugin.anomalydefs then
		checks = CheckboxGrid(p, anomPlugin.anomalydefs)
	end

	local removeRadius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

	modeDefs.anomaly = {
		addCmd = "anomalyadd",
		getAddArgs = function()
			if not anomPlugin then return nil end
			return { areaRadius:GetValue(), Bitstring(anomPlugin.anomalydefs, checks) }
		end,
		removeCmd = "anomalyremove",
		getRemoveArgs = function() return { removeRadius:GetValue() } end,
	}
end

local function BuildEventMode(sheetPanel)
	local p = NewTab(sheetPanel, "event", "Eventos", "icon16/flag_blue.png")

	HelpText(p, "Esquerdo: adiciona a área de evento na mira. Direito: remove próximas.")

	local nameEntry = TextEntry(p, "Nome da área", "ex: Zona Norte")
	local difficulty = NumberWang(p, "Dificuldade", 1, 10, 1)
	local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

	modeDefs.event = {
		addCmd = "eventadd",
		getAddArgs = function()
			local name = nameEntry:GetValue()
			if name == "" then name = "UNNAMED AREA" end
			return { name, difficulty:GetValue() }
		end,
		removeCmd = "eventremove",
		getRemoveArgs = function() return { radius:GetValue() } end,
	}
end

local function BuildContainerMode(sheetPanel)
	local p = NewTab(sheetPanel, "container", "Containers Cíclicos", "icon16/package.png")

	HelpText(p, "Mire DIRETAMENTE em um container (ix_container) já existente no mapa.\n" ..
		"Esquerdo: marca como cíclico com a categoria escolhida. Direito: desmarca.")

	local cyclicPlugin = ix.plugin.list["cycliccontainer"]
	local categoryCombo = Combo(p, "Categoria cíclica")

	if cyclicPlugin and cyclicPlugin.categoryDefs then
		local keys = {}
		for k in pairs(cyclicPlugin.categoryDefs) do keys[#keys + 1] = k end
		table.sort(keys)
		for _, k in ipairs(keys) do categoryCombo:AddChoice(k, k) end
		if keys[1] then categoryCombo:ChooseOption(keys[1], 1) end
	end

	modeDefs.container = {
		addCmd = "containercyclicaladd",
		getAddArgs = function()
			local cat = categoryCombo:GetSelected()
			if not cat or cat == "" then return nil end
			return { cat }
		end,
		removeCmd = "containercyclicalremove",
		getRemoveArgs = function() return {} end,
	}
end

-- -----------------------------------------------------------------------
-- Painel de configurações (criado uma vez, só oculta/mostra)
-- -----------------------------------------------------------------------

local function EnsureSettingsPanel(weapon)
	if IsValid(settingsFrame) then return end

	settingsFrame = vgui.Create("DFrame")
	settingsFrame:SetSize(420, 480)
	settingsFrame:SetPos(40, ScrH() / 2 - 240)
	settingsFrame:SetTitle("Spawn Tool - Configurações")
	settingsFrame:SetVisible(false)
	settingsFrame:SetDraggable(true)
	settingsFrame:ShowCloseButton(true)
	settingsFrame.OnClose = function() settingsFrame:SetVisible(false) end

	sheet = vgui.Create("DPropertySheet", settingsFrame)
	sheet:Dock(FILL)
	sheet:DockMargin(2, 2, 2, 2)

	BuildBoxMode(sheet)
	BuildStashMode(sheet)
	BuildRadiationMode(sheet)
	BuildAnomalyMode(sheet)
	BuildEventMode(sheet)
	BuildContainerMode(sheet)

	sheet:SetActiveTab(sheet.Items[activeIndex].Tab)

	-- Trocar de aba no painel também troca o modo ativo da ferramenta.
	for i, item in ipairs(sheet.Items) do
		local oldDoClick = item.Tab.DoClick
		item.Tab.DoClick = function(btn)
			oldDoClick(btn)
			activeIndex = i
		end
	end
end

function SWEP:ToggleSettings()
	EnsureSettingsPanel(self)

	if not IsValid(settingsFrame) then return end

	local show = not settingsFrame:IsVisible()
	settingsFrame:SetVisible(show)

	if show then
		settingsFrame:MakePopup()
		settingsFrame:SetKeyboardInputEnabled(false) -- mouse capturado, teclado (WASD etc) livre pro jogador
	else
		settingsFrame:SetMouseInputEnabled(false)
		settingsFrame:SetKeyboardInputEnabled(false)
		gui.EnableScreenClicker(false)
	end
end

function SWEP:CycleMode()
	EnsureSettingsPanel(self)

	activeIndex = (activeIndex % #self.ModeOrder) + 1
	local id = self.ModeOrder[activeIndex]

	if IsValid(sheet) and sheet.Items[activeIndex] then
		sheet:SetActiveTab(sheet.Items[activeIndex].Tab)
	end

	local ply = LocalPlayer()
	if IsValid(ply) then
		ply:ChatPrint("[Spawn Tool] Modo: " .. (self.ModeLabels[id] or id))
	end
	surface.PlaySound("buttons/lightswitch2.wav")
end

function SWEP:DoAdd()
	EnsureSettingsPanel(self)

	local id = self.ModeOrder[activeIndex]
	local def = modeDefs[id]
	if not def then return end

	local args = def.getAddArgs and def.getAddArgs()
	if not args then
		LocalPlayer():ChatPrint("[Spawn Tool] Configure este modo antes de usar (aperte R).")
		return
	end

	ix.command.Send(def.addCmd, unpack(args))
	self:EmitSound("weapons/toolgun/toolgun_fire.wav")
end

function SWEP:DoRemove()
	EnsureSettingsPanel(self)

	local id = self.ModeOrder[activeIndex]
	local def = modeDefs[id]
	if not def or not def.removeCmd then return end

	local args = def.getRemoveArgs and def.getRemoveArgs() or {}
	ix.command.Send(def.removeCmd, unpack(args))
	self:EmitSound("weapons/toolgun/toolgun_use.wav")
end

function SWEP:DrawHUD()
	local id = self.ModeOrder[activeIndex]
	local label = self.ModeLabels[id] or id

	draw.SimpleTextOutlined(
		"Spawn Tool - Modo: " .. label,
		"DermaDefaultBold", 20, ScrH() - 90, color_white,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black
	)
	draw.SimpleTextOutlined(
		"Esquerdo: adicionar | Direito: remover | Meio: trocar modo | R: configurações",
		"DermaDefault", 20, ScrH() - 70, Color(200, 200, 200),
		TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black
	)
end
