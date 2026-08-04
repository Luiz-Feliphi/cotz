--[[
	Painel gráfico para os plugins de spawn.

	Importante: os combos de "Anomalias", "Radiação", "Containers Cíclicos" e
	"Stash Escondido" leem as definições diretamente das tabelas dos plugins
	originais (ix.plugin.list["anomalycontroller"].anomalydefs, etc), então se
	você adicionar novas categorias/definições lá, elas aparecem aqui
	automaticamente sem precisar editar este arquivo.

	Este arquivo NÃO duplica nenhuma lógica de spawn: todo botão apenas chama
	ix.command.Send(...) com os mesmos comandos que você já usava no chat.
	As permissões (superAdminOnly / adminOnly) continuam sendo checadas
	normalmente no servidor.
]]

local PLUGIN = PLUGIN

local frame

-- ---------------------------------------------------------------------
-- Permite continuar andando com o painel aberto.
-- ---------------------------------------------------------------------
-- Vários schemas de Helix travam o movimento sempre que existe um menu com
-- o cursor visível (pra evitar o jogador "andar às cegas" enquanto lê algo).
-- Isso também bloqueava este painel. Para contornar, forçamos manualmente
-- os valores de movimento no CreateMove enquanto o painel estiver visível,
-- lendo as teclas WASD/espaço diretamente — isso sobrescreve qualquer outro
-- hook que tenha zerado o movimento antes do nosso.
local MOVE_SPEED = 400

hook.Add("CreateMove", "SpawnPointEditor_AllowMovement", function(cmd)
	if not IsValid(frame) or not frame:IsVisible() then return end

	local forward, side = 0, 0

	if input.IsKeyDown(KEY_W) then forward = forward + 1 end
	if input.IsKeyDown(KEY_S) then forward = forward - 1 end
	if input.IsKeyDown(KEY_A) then side = side - 1 end
	if input.IsKeyDown(KEY_D) then side = side + 1 end

	cmd:SetForwardMove(forward * MOVE_SPEED)
	cmd:SetSideMove(side * MOVE_SPEED)

	if input.IsKeyDown(KEY_SPACE) then
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_JUMP))
	end

	if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then
		cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_SPEED))
	end
end)

-- ---------------------------------------------------------------------
-- Bola 3D mostrando o raio ao vivo, seguindo a mira.
-- ---------------------------------------------------------------------
-- Cada aba pode registrar em previewGetters[índice da aba] uma função
-- addRadius (raio de área onde algo VAI spawnar, ex: anomalias) e/ou
-- removeRadius (raio que será afetado ao clicar em remover). Desenhamos
-- os dois ao vivo, sempre no ponto que sua mira está tocando, enquanto
-- o painel estiver aberto.
local previewGetters = {}
local activeTabIndex = 1

local PREVIEW_ADD_COLOR = Color(80, 220, 120, 90)
local PREVIEW_REMOVE_COLOR = Color(220, 90, 70, 90)

hook.Add("PostDrawTranslucentRenderables", "SpawnPointEditor_SpherePreview", function()
	if not IsValid(frame) or not frame:IsVisible() then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local getters = previewGetters[activeTabIndex]
	if not getters then return end

	local trace = ply:GetEyeTrace()
	if not trace.Hit then return end

	local pos = trace.HitPos

	render.SetColorMaterial()

	if getters.addRadius then
		local r = getters.addRadius()
		if r and r > 0 then
			render.DrawSphere(pos, r, 24, 24, PREVIEW_ADD_COLOR)
		end
	end

	if getters.removeRadius then
		local r = getters.removeRadius()
		if r and r > 0 then
			render.DrawSphere(pos, r, 24, 24, PREVIEW_REMOVE_COLOR)
		end
	end
end)

-- ---------------------------------------------------------------------
-- Helpers de layout (evitam repetir código de posicionamento em cada aba)
-- ---------------------------------------------------------------------

local function Spacer(parent, h)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:SetTall(h or 8)
	p.Paint = function() end
	return p
end

local function SectionTitle(parent, text)
	local lbl = vgui.Create("DLabel", parent)
	lbl:Dock(TOP)
	lbl:DockMargin(4, 10, 4, 2)
	lbl:SetFont("DermaDefaultBold")
	lbl:SetText(text)
	lbl:SetTextColor(color_white)
	return lbl
end

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
	lbl:SetTextColor(Color(255, 255, 255))-- COR DO TEXTO DOS HELPTEXT
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
	if placeholder then
		entry:SetPlaceholderText(placeholder)
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

local function Button(parent, text, callback)
	local btn = vgui.Create("DButton", parent)
	btn:Dock(TOP)
	btn:DockMargin(4, 6, 4, 0)
	btn:SetTall(30)
	btn:SetText(text)
	btn.DoClick = callback
	return btn
end

local function CheckboxGrid(parent, defs, nameKey)
	-- Cria uma checkbox por definição, na ordem da tabela (a ordem importa,
	-- pois vira uma bitstring tipo "1010011...").
	local list = vgui.Create("DPanel", parent)
	list:Dock(TOP)
	list.Paint = function() end

	local checks = {}
	local count = 0

	for i = 1, #defs do
		count = count + 1
	end

	list:SetTall(count * 22 + 4)

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

local function BuildBitstring(defs, checks)
	local str = ""
	for i = 1, #defs do
		str = str .. ((checks[i] and checks[i]:GetChecked()) and "1" or "0")
	end
	return str
end

local function NewTabScroll(sheet, name, icon)
	local scroll = vgui.Create("DScrollPanel")
	sheet:AddSheet(name, scroll, icon)
	return scroll
end

-- ---------------------------------------------------------------------
-- Abas
-- ---------------------------------------------------------------------

local function BuildBoxTab(sheet)
	local p = NewTabScroll(sheet, "Caixas", "icon16/box.png")

	HelpText(p, "Mire no local do mapa onde a caixa de loot deve spawnar e clique em " ..
		"Adicionar. O ponto criado é exatamente onde sua mira estiver no momento do clique.")

	local typeCombo = Combo(p, "Tipo de caixa")
	typeCombo:AddChoice("Pequena (ix_entbox)", 1)
	typeCombo:AddChoice("Grande (madeira / papel)", 2)
	typeCombo:ChooseOptionID(1)

	local group = TextEntry(p, "Grupo customizado (opcional)", "deixe vazio para nenhum")

	Button(p, "+ Adicionar ponto na mira", function()
		local _, typeId = typeCombo:GetSelected()
		local g = group:GetValue()
		if g == "" then g = nil end
		ix.command.Send("boxspawnadd", typeId or 1, g)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("boxspawnremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("boxspawndisplay")
	end)

	Button(p, "Forçar spawn agora", function()
		ix.command.Send("boxspawnforce")
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildStashTab(sheet)
	local p = NewTabScroll(sheet, "Stash Escondido", "icon16/lock.png")

	HelpText(p, "Mire no local onde o stash escondido deve poder aparecer e escolha uma " ..
		"categoria de loot (definida em hidestashspawner/sh_definitions.lua).")

	local stashPlugin = ix.plugin.list["hidestashspawner"]
	local categoryCombo = Combo(p, "Categoria de loot")

	if stashPlugin and stashPlugin.StashItems then
		local keys = {}
		for k in pairs(stashPlugin.StashItems) do
			keys[#keys + 1] = k
		end
		table.sort(keys)

		for _, k in ipairs(keys) do
			categoryCombo:AddChoice(k, k)
		end

		if keys[1] then
			categoryCombo:ChooseOption(keys[1], 1)
		end
	else
		categoryCombo:AddChoice("(plugin hidestashspawner não encontrado)", nil)
	end

	Button(p, "+ Adicionar ponto na mira", function()
		local text = categoryCombo:GetSelected()
		if not text or text == "" then return end
		ix.command.Send("stashspawneradd", text)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("stashspawnerremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("stashspawnerdisplay")
	end)

	Button(p, "Forçar spawn de caixas de stash agora", function()
		ix.command.Send("stashspawnerforce")
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildRadiationTab(sheet)
	local p = NewTabScroll(sheet, "Radiação", "icon16/error.png")

	HelpText(p, "Mire no local onde a entidade de radiação deve aparecer e marque quais " ..
		"tipos podem ser sorteados nesse ponto (um deles será escolhido aleatoriamente).")

	local radPlugin = ix.plugin.list["radiationcontroller"]
	local checks = {}

	if radPlugin and radPlugin.radiationdefs then
		SectionTitle(p, "Tipos de radiação permitidos neste ponto")
		checks = CheckboxGrid(p, radPlugin.radiationdefs)
	else
		HelpText(p, "(plugin radiationcontroller não encontrado)")
	end

	Button(p, "+ Adicionar ponto na mira", function()
		if not radPlugin then return end
		local bitstring = BuildBitstring(radPlugin.radiationdefs, checks)
		ix.command.Send("radiationadd", bitstring)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("radiationremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("radiationdisplay")
	end)

	local entRadius = NumberWang(p, "Raio para remover entidades já spawnadas", 8, 2048, 256)

	Button(p, "Remover entidades de radiação próximas", function()
		ix.command.Send("radiationentremove", entRadius:GetValue())
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildAnomalyTab(sheet)
	local p = NewTabScroll(sheet, "Anomalias", "icon16/asterisk_yellow.png")

	HelpText(p, "Mire no centro da área e defina um raio: as anomalias marcadas abaixo " ..
		"poderão aparecer dentro desse raio ao redor do ponto.")

	local anomPlugin = ix.plugin.list["anomalycontroller"]
	local checks = {}

	local radius = NumberWang(p, "Raio da área (unidades)", 8, 4096, 256)

	if anomPlugin and anomPlugin.anomalydefs then
		SectionTitle(p, "Anomalias permitidas nesta área")
		checks = CheckboxGrid(p, anomPlugin.anomalydefs)
	else
		HelpText(p, "(plugin anomalycontroller não encontrado)")
	end

	Button(p, "+ Adicionar ponto na mira", function()
		if not anomPlugin then return end
		local bitstring = BuildBitstring(anomPlugin.anomalydefs, checks)

		if not string.find(bitstring, "1") then
			LocalPlayer():ChatPrint("[Spawn Editor] Marque pelo menos uma anomalia antes de adicionar o ponto.")
			return
		end

		ix.command.Send("anomalyadd", radius:GetValue(), bitstring)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local removeRadius = NumberWang(p, "Raio de remoção de pontos (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("anomalyremove", removeRadius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("anomalydisplay")
	end)

	local entRadius = NumberWang(p, "Raio para remover entidades já spawnadas", 8, 2048, 256)

	Button(p, "Remover entidades de anomalia próximas", function()
		ix.command.Send("anomalyentremove", entRadius:GetValue())
	end)

	Spacer(p, 6)

	Button(p, "Limpar TODAS as anomalias do mapa", function()
		ix.command.Send("cleananomalies")
	end)

	Button(p, "Forçar spawn de anomalias agora", function()
		ix.command.Send("spawnanomalies")
	end)

	previewGetters[#sheet.Items] = {
		addRadius = function() return radius:GetValue() end,
		removeRadius = function() return removeRadius:GetValue() end,
	}
end

local function BuildEventTab(sheet)
	local p = NewTabScroll(sheet, "Eventos", "icon16/flag_blue.png")

	HelpText(p, "Mire no centro da área de evento e dê um nome. A 'dificuldade' desse " ..
		"sistema é um código de 2 dígitos (mapa + tipo de local) que precisa bater com " ..
		"algum evento cadastrado em sh_eventdefs.lua, então escolha nos dois campos " ..
		"abaixo em vez de digitar um número solto.")

	local nameEntry = TextEntry(p, "Nome da área", "ex: Zona Norte")

	local mapCombo = Combo(p, "Mapa")
	mapCombo:AddChoice("1 - Marsh / Swamps", 1)
	mapCombo:AddChoice("2 - Waystation", 2)
	mapCombo:AddChoice("3 - Pripyat", 3)
	mapCombo:AddChoice("4 - Stalkercotz 1", 4)
	mapCombo:ChooseOptionID(1)

	local typeCombo = Combo(p, "Tipo de local")
	typeCombo:AddChoice("1 - Perto do spawn (natureza)", 1)
	typeCombo:AddChoice("2 - Longe do spawn (natureza)", 2)
	typeCombo:AddChoice("3 - Área povoada / prédio", 3)
	typeCombo:AddChoice("4 - Ponto de sniper", 4)
	typeCombo:AddChoice("5 - Subterrâneo", 5)
	typeCombo:ChooseOptionID(1)

	HelpText(p, "Aviso: hoje não existe NENHUM evento cadastrado com o dígito de mapa 4 " ..
		"(Stalkercotz 1) em sh_eventdefs.lua -- pontos criados nesse mapa não vão " ..
		"spawnar nada até vocês adicionarem eventdefs com dificuldade 41-45 lá.")

	local eventPlugin = ix.plugin.list["eventcontroller"]
	local defCombo = Combo(p, "Evento específico (opcional)")
	defCombo:AddChoice("Aleatório (usa a dificuldade acima)", "")

	if eventPlugin and eventPlugin.eventdefs then
		local keys = {}
		for k in pairs(eventPlugin.eventdefs) do keys[#keys + 1] = k end
		table.sort(keys)

		for _, k in ipairs(keys) do
			defCombo:AddChoice(k, k)
		end
	end

	defCombo:ChooseOptionID(1)

	HelpText(p, "Se escolher um evento específico aqui, esse ponto SEMPRE vai spawnar " ..
		"exatamente esse evento (ignora a dificuldade pra escolher, mas ela ainda é " ..
		"salva com o ponto). Deixe em 'Aleatório' pra manter o comportamento antigo " ..
		"(sorteia entre todos os eventos que aceitam aquela dificuldade).")

	Button(p, "+ Adicionar ponto na mira", function()
		local name = nameEntry:GetValue()
		if name == "" then name = "UNNAMED AREA" end

		local _, mapDigit = mapCombo:GetSelected()
		local _, typeDigit = typeCombo:GetSelected()
		local difficulty = (mapDigit or 1) * 10 + (typeDigit or 1)

		local defName = defCombo:GetSelected()

		if defName and defName ~= "" then
			ix.command.Send("eventadd", name, difficulty, defName)
		else
			ix.command.Send("eventadd", name, difficulty)
		end
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("eventremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("eventdisplay")
	end)

	Button(p, "Forçar 1 evento agora", function()
		ix.command.Send("eventforce")
	end)

	Button(p, "Popular evento agora (rajada de vários)", function()
		ix.command.Send("eventpopulate")
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildEventAdvTab(sheet)
	local p = NewTabScroll(sheet, "Eventos Avançados", "icon16/flag_red.png")

	HelpText(p, "Sistema diferente do 'Eventos' comum: eventos roteirizados específicos " ..
		"(ex: caixa de suprimentos, base de mercenários). Cada ponto precisa de um nome " ..
		"INTERNO exato que já existe em eventcontrolleradv/sh_eventdefs.lua -- por isso " ..
		"o campo abaixo é um dropdown com os nomes válidos em vez de texto livre. " ..
		"Também depende do addon AdvDupe2 estar instalado, dependendo do evento.")

	local advPlugin = ix.plugin.list["eventcontrolleradv"]
	local nameEntry = TextEntry(p, "Nome de exibição", "ex: Base Abandonada")
	local internalCombo = Combo(p, "Nome interno (allowedPoints)")

	if advPlugin and advPlugin.eventdefs then
		local seen = {}
		local keys = {}

		for _, def in pairs(advPlugin.eventdefs) do
			if def.allowedPoints then
				for _, pointName in ipairs(def.allowedPoints) do
					if not seen[pointName] then
						seen[pointName] = true
						keys[#keys + 1] = pointName
					end
				end
			end
		end

		table.sort(keys)

		for _, k in ipairs(keys) do
			internalCombo:AddChoice(k, k)
		end

		if keys[1] then
			internalCombo:ChooseOption(keys[1], 1)
		end
	else
		HelpText(p, "(plugin eventcontrolleradv não encontrado)")
	end

	Button(p, "+ Adicionar ponto na mira", function()
		local name = nameEntry:GetValue()
		if name == "" then name = "UNNAMED AREA" end

		local internalName = internalCombo:GetSelected()
		if not internalName or internalName == "" then return end

		ix.command.Send("eventadvadd", name, internalName)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("eventadvremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("eventadvdisplay")
	end)

	Button(p, "Forçar 1 evento avançado agora", function()
		ix.command.Send("eventadvforce")
	end)

	Button(p, "Popular eventos avançados agora (rajada)", function()
		ix.command.Send("eventadvpopulate")
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildContainerTab(sheet)
	local p = NewTabScroll(sheet, "Containers Cíclicos", "icon16/package.png")

	HelpText(p, "Mire diretamente em um container (ix_container) já existente no mapa " ..
		"(spawnado pelo firsttimesetup ou manualmente) para marcá-lo como cíclico.")

	local cyclicPlugin = ix.plugin.list["cycliccontainer"]
	local categoryCombo = Combo(p, "Categoria cíclica")

	if cyclicPlugin and cyclicPlugin.categoryDefs then
		local keys = {}
		for k in pairs(cyclicPlugin.categoryDefs) do
			keys[#keys + 1] = k
		end
		table.sort(keys)

		for _, k in ipairs(keys) do
			categoryCombo:AddChoice(k, k)
		end

		if keys[1] then
			categoryCombo:ChooseOption(keys[1], 1)
		end
	else
		categoryCombo:AddChoice("(plugin cycliccontainer não encontrado)", nil)
	end

	Button(p, "Marcar container mirado como cíclico", function()
		local cat = categoryCombo:GetSelected()
		if not cat or cat == "" then return end
		ix.command.Send("containercyclicaladd", cat)
	end)

	Button(p, "Desmarcar container mirado", function()
		ix.command.Send("containercyclicalremove")
	end)

	Button(p, "Tornar container mirado 'no-collide'", function()
		ix.command.Send("containercyclicalmakenocollide")
	end)

	SectionTitle(p, "Utilidades")

	Button(p, "Mostrar todos os containers cíclicos (10s)", function()
		ix.command.Send("containercyclicaldisplay")
	end)

	Button(p, "Forçar aparecer com loot novo (container na mira)", function()
		ix.command.Send("containercyclicalforce")
	end)

	Button(p, "Forçar TODOS os containers cíclicos do mapa a aparecer", function()
		ix.command.Send("containercyclicalforceall")
	end)
end

local function BuildItemSpawnTab(sheet)
	local p = NewTabScroll(sheet, "Itens no Mapa", "icon16/note.png")

	HelpText(p, "Mire no local do mapa onde itens soltos devem poder spawnar " ..
		"periodicamente (worlditemspawner) e escolha um grupo de loot.")

	local group = TextEntry(p, "Grupo de spawn (pool de itens)", "ex: default")

	Button(p, "+ Adicionar ponto na mira", function()
		local g = group:GetValue()
		if g == "" then g = "default" end
		ix.command.Send("itemspawnadd", g)
	end)

	SectionTitle(p, "Remoção / utilidades")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 1024, 128)

	Button(p, "Remover pontos próximos à mira", function()
		ix.command.Send("itemspawnremove", radius:GetValue())
	end)

	Button(p, "Mostrar todos os pontos (10s)", function()
		ix.command.Send("itemspawndisplay")
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildContainerSpawnTab(sheet)
	local p = NewTabScroll(sheet, "Loot em Containers", "icon16/box.png")

	HelpText(p, "Mire DIRETAMENTE em um container (ix_container) já existente no mapa " ..
		"para definir de qual grupo de itens ele deve sortear loot periodicamente " ..
		"(containeritemspawn). Isso é diferente da aba 'Containers Cíclicos': aqui " ..
		"não há categoria fixa, é só um nome de pool de itens.")

	local group = TextEntry(p, "Grupo de loot (pool de itens)", "ex: ix_entbox_drops")

	Button(p, "Definir grupo no container mirado", function()
		local g = group:GetValue()
		if g == "" then return end
		ix.command.Send("containerspawnadd", g)
	end)

	Button(p, "Remover grupo do container mirado", function()
		ix.command.Send("containerspawnremove")
	end)

	SectionTitle(p, "Utilidades")

	Button(p, "Forçar item no container na mira agora", function()
		ix.command.Send("containerspawnforce")
	end)

	HelpText(p, "Não existe comando de 'mostrar todos' para este sistema.")
end

local function BuildContainerEntitySpawnTab(sheet)
	local p = NewTabScroll(sheet, "Spawnar Container", "icon16/package_add.png")

	HelpText(p, "Mire no local do mapa e escolha um modelo já registrado em " ..
		"ix.container.stored (containers/sh_definitions.lua) para criar um " ..
		"ix_container de verdade, com inventário funcional, direto na mira.")

	local modelCombo = Combo(p, "Modelo do container")

	if ix.container and ix.container.stored then
		local keys = {}
		for model in pairs(ix.container.stored) do keys[#keys + 1] = model end
		table.sort(keys)

		for _, model in ipairs(keys) do
			local data = ix.container.stored[model]
			local label = (data and data.name or "?") .. "  [" .. model .. "]"
			modelCombo:AddChoice(label, model)
		end

		if keys[1] then
			modelCombo:ChooseOptionID(1)
		end
	else
		HelpText(p, "(ix.container não encontrado — o plugin 'containers' está carregado?)")
	end

	Button(p, "+ Criar container na mira", function()
		local model = select(2, modelCombo:GetSelected())
		if not model or model == "" then return end
		ix.command.Send("containerspawn", model)
	end)

	SectionTitle(p, "Remoção")

	local radius = NumberWang(p, "Raio de remoção (unidades)", 8, 512, 64)

	Button(p, "Remover containers próximos à mira", function()
		ix.command.Send("containerentremove", radius:GetValue())
	end)

	previewGetters[#sheet.Items] = { removeRadius = function() return radius:GetValue() end }
end

local function BuildInfoTab(sheet)
	local p = NewTabScroll(sheet, "Início", "icon16/information.png")

	SectionTitle(p, "Como usar")
	HelpText(p,
		"Este painel só existe para você não precisar decorar/digitar comandos. " ..
		"Cada botão aqui dispara exatamente o mesmo comando que você já usava " ..
		"(boxspawnadd, stashspawneradd, radiationadd, anomalyadd, eventadd, " ..
		"containercyclicaladd, etc), então as permissões continuam as mesmas " ..
		"(superadmin/admin) e nenhum dado antigo é perdido.\n\n" ..
		"1. Aponte a mira para o local desejado no mapa.\n" ..
		"2. Abra este painel (o jogo pausa a mira, mas a direção que você estava " ..
		"olhando é mantida).\n" ..
		"3. Preencha os campos da aba desejada e clique em Adicionar.\n\n" ..
		"Dica: bind uma tecla para abrir o painel rapidamente, ex:\n" ..
		"bind \"end\" \"spawnmenu\""
	)

	SectionTitle(p, "Descobrir o uniqueID de um item jogado no chão")
	HelpText(p, "Mire em um item já jogado no mapa (entidade ix_item) e clique no botão " ..
		"abaixo. O uniqueID aparece no chat e já é copiado para a área de transferência, " ..
		"pronto pra colar nos campos de 'grupo/pool' das outras abas.")

	Button(p, "Copiar uniqueID do item na mira", function()
		ix.command.Send("itemid")
	end)
end

-- ---------------------------------------------------------------------
-- Frame principal
-- ---------------------------------------------------------------------

local function OpenSpawnMenu()
	if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then
		LocalPlayer():ChatPrint("Você precisa ser admin para abrir este painel.")
		return
	end

	if IsValid(frame) then
		frame:Remove()
	end

	frame = vgui.Create("DFrame")
	frame:SetSize(600, 640)
	frame:Center()
	frame:SetTitle("Editor de Pontos de Spawn")
	frame:SetDeleteOnClose(true)
	frame:MakePopup()

	local sheet = vgui.Create("DPropertySheet", frame)
	sheet:Dock(FILL)
	sheet:DockMargin(2, 2, 2, 2)

	BuildInfoTab(sheet)
	BuildBoxTab(sheet)
	BuildStashTab(sheet)
	BuildItemSpawnTab(sheet)
	BuildRadiationTab(sheet)
	BuildAnomalyTab(sheet)
	BuildEventTab(sheet)
	BuildEventAdvTab(sheet)
	BuildContainerTab(sheet)
	BuildContainerSpawnTab(sheet)
	BuildContainerEntitySpawnTab(sheet)

	-- Trocar de aba também troca qual raio a bola 3D mostra.
	activeTabIndex = 1
	for i, item in ipairs(sheet.Items) do
		local oldDoClick = item.Tab.DoClick
		item.Tab.DoClick = function(btn)
			oldDoClick(btn)
			activeTabIndex = i
		end
	end
end

concommand.Add("spawnmenu", OpenSpawnMenu)

-- ---------------------------------------------------------------------
-- Atalho dentro do menu Q (aba "Utilities" / Ferramentas)
-- ---------------------------------------------------------------------
hook.Add("PopulateToolMenu", "SpawnPointEditor_QMenu", function()
	spawnmenu.AddToolMenuOption("Utilities", "Spawn Point Editor", "spawnpointeditor_open",
		"Editor de Pontos de Spawn", "", "", function(panel)
			panel:ClearControls()

			panel:Help("Ferramenta gráfica para posicionar pontos de spawn (caixas, " ..
				"stashes, radiação, anomalias, eventos, containers) sem digitar comandos.")

			local btn = panel:Button("Abrir Editor de Pontos de Spawn")
			btn.DoClick = function()
				OpenSpawnMenu()
			end

			panel:Help("Dica: também dá pra digitar 'spawnmenu' no console, ou pegar a " ..
				"Spawn Tool (estilo tool gun) com '/spawntool' no chat.")
		end)
end)
