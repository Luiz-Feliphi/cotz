local PLUGIN = PLUGIN

PLUGIN.name = "Spawn Point Editor (GUI)"
PLUGIN.author = "Luiz Feliphi"
PLUGIN.desc = "Adiciona um painel gráfico (F-menu) para gerenciar todos os pontos de spawn " ..
	"(caixas, stashes escondidos, radiação, anomalias, eventos e containers cíclicos) " ..
	"sem precisar digitar comandos manualmente. O painel apenas envia os mesmos comandos " ..
	"que já existiam (boxspawnadd, stashspawneradd, radiationadd, anomalyadd, eventadd, " ..
	"containercyclicaladd, etc), então toda a lógica e permissões originais continuam valendo."

-- Este plugin não guarda nenhum dado próprio: ele só é uma "casca" gráfica
-- em cima dos comandos que os outros plugins (boxspawner, hidestashspawner,
-- radiationcontroller, anomalycontroller, eventcontroller, cycliccontainer)
-- já registram com ix.command.Add. Por isso ele deve ser carregado DEPOIS
-- desses plugins (ordem alfabética de pastas já garante isso na maioria dos
-- casos, mas se algum combo aparecer vazio no painel, veja o comentário no
-- topo de cl_editor.lua).

ix.util.Include("cl_editor.lua")

-- ---------------------------------------------------------------------
-- Comando "itemid": mira num item já jogado no chão (entidade ix_item) e
-- mostra + copia pro clipboard o uniqueID dele, pra usar nos campos de
-- grupo/pool das outras abas.
-- ---------------------------------------------------------------------
if SERVER then
	util.AddNetworkString("SpawnPointEditor_CopyItemID")
end

ix.command.Add("itemid", {
	adminOnly = true,
	OnRun = function(self, client)
		if not SERVER then return end

		local trace = client:GetEyeTraceNoCursor()
		local ent = trace.Entity

		if not IsValid(ent) or ent:GetClass() != "ix_item" then
			client:Notify("Mire em um item jogado no chão e tente de novo.")
			return
		end

		local itemTable = ent:GetItemTable()
		if not itemTable then
			client:Notify("Não consegui ler os dados desse item.")
			return
		end

		client:Notify("uniqueID: " .. itemTable.uniqueID .. "  (" .. (itemTable.name or "?") .. ")")

		net.Start("SpawnPointEditor_CopyItemID")
			net.WriteString(itemTable.uniqueID)
		net.Send(client)
	end
})

if CLIENT then
	net.Receive("SpawnPointEditor_CopyItemID", function()
		local uniqueID = net.ReadString()
		SetClipboardText(uniqueID)

		local ply = LocalPlayer()
		if IsValid(ply) then
			ply:ChatPrint("[Spawn Tool] uniqueID copiado para a área de transferência: " .. uniqueID)
		end
	end)
end

-- ---------------------------------------------------------------------
-- Registro manual da SWEP "weapon_spawntool"
-- ---------------------------------------------------------------------
-- O Helix (nesta base) só carrega automaticamente pastas como "entities"
-- e "items" dentro de um plugin; ele NÃO escaneia uma pasta "weapons", e
-- passar dados entre arquivos via uma variável global "SWEP" também não
-- se mostrou confiável aqui. Por isso a arma inteira é montada como uma
-- tabela LOCAL, sem depender de nenhuma variável global entre arquivos,
-- e registrada diretamente com weapons.Register.
do
	local SWEP = {}
	SWEP.Base = "weapon_base"

	SWEP.PrintName = "Spawn Tool"
	SWEP.Author = "you"
	SWEP.Instructions = "Esquerdo: adicionar ponto | Direito: remover pontos próximos | " ..
		"Meio (mouse3): trocar modo | R: abrir/fechar configurações"
	SWEP.Purpose = "Ferramenta gráfica para posicionar pontos de spawn sem digitar comandos."

	SWEP.Category = "Admin"
	SWEP.Spawnable = false
	SWEP.AdminOnly = true -- checagem real de permissão é feita nos comandos ix, isto é só cosmético

	SWEP.ViewModel = "models/weapons/v_toolgun.mdl"
	SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
	SWEP.UseHands = true
	SWEP.HoldType = "pistol"

	SWEP.Slot = 5
	SWEP.SlotPos = 2
	SWEP.DrawAmmo = false
	SWEP.DrawCrosshair = true

	-- Como montamos o SWEP na mão (sem passar pelo carregador real do GMod),
	-- as subtabelas Primary/Secondary do "weapon_base" ainda não existem
	-- neste ponto — precisamos criá-las manualmente antes de usá-las.
	SWEP.Primary = {}
	SWEP.Secondary = {}

	SWEP.Primary.ClipSize = -1
	SWEP.Primary.DefaultClip = -1
	SWEP.Primary.Automatic = false
	SWEP.Primary.Ammo = "none"

	SWEP.Secondary.ClipSize = -1
	SWEP.Secondary.DefaultClip = -1
	SWEP.Secondary.Automatic = false
	SWEP.Secondary.Ammo = "none"

	SWEP.Weight = 5
	SWEP.AutoSwitchTo = false
	SWEP.AutoSwitchFrom = false

	-- Ordem dos "modos" da ferramenta (equivalente às abas do painel gráfico).
	SWEP.ModeOrder = {
		"box", "stash", "itemspawn", "radiation", "anomaly", "event", "eventadv",
		"container", "containerspawn", "containerentity",
	}

	SWEP.ModeLabels = {
		box = "Caixas",
		stash = "Stash Escondido",
		itemspawn = "Itens no Mapa",
		radiation = "Radiação",
		anomaly = "Anomalias",
		event = "Eventos",
		eventadv = "Eventos Avançados",
		container = "Containers Cíclicos",
		containerspawn = "Loot em Containers",
		containerentity = "Spawnar Container",
	}

	function SWEP:Initialize()
		self:SetHoldType(self.HoldType)
	end

	function SWEP:PrimaryAttack()
		self:SetNextPrimaryFire(CurTime() + 0.25)

		if SERVER then return end

		self:DoAdd()
	end

	function SWEP:SecondaryAttack()
		self:SetNextSecondaryFire(CurTime() + 0.25)

		if SERVER then return end

		self:DoRemove()
	end

	function SWEP:Reload()
		if CLIENT then
			self:ToggleSettings()
		end
	end

	-- IN_ATTACK3 não existe no GMod (não tem flag própria pra clique do
	-- meio) — detectamos o botão do mouse direto, com borda de subida pra
	-- não ficar trocando de modo repetidamente enquanto o botão fica preso.
	local wasMiddleDown = false

	function SWEP:Think()
		if SERVER then return end

		local owner = self:GetOwner()
		if not IsValid(owner) then return end

		local middleDown = input.IsMouseDown(MOUSE_MIDDLE)

		if middleDown and not wasMiddleDown then
			self:CycleMode()
		end

		wasMiddleDown = middleDown
	end

	if CLIENT then
		local modeDefs = {}
		local activeIndex = 1
		local settingsFrame
		local sheetPanel

		-- Mesmo motivo do painel /spawnmenu: garante que dá pra andar com
		-- este painel de configurações aberto, mesmo se o schema travar o
		-- movimento sempre que o cursor estiver visível.
		local MOVE_SPEED = 400

		hook.Add("CreateMove", "SpawnTool_AllowMovement", function(cmd)
			if not IsValid(settingsFrame) or not settingsFrame:IsVisible() then return end

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
			lbl:SetTextColor(Color(160, 160, 160))
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

		local function Button(parent, text, callback)
			local btn = vgui.Create("DButton", parent)
			btn:Dock(TOP)
			btn:DockMargin(4, 6, 4, 0)
			btn:SetTall(28)
			btn:SetText(text)
			btn.DoClick = callback
			return btn
		end

		local function TextEntry(parent, label, placeholder)
			FieldLabel(parent, label)
			local entry = vgui.Create("DTextEntry", parent)
			entry:Dock(TOP)
			entry:DockMargin(4, 0, 4, 2)
			entry:SetTall(26)
			if placeholder then entry:SetPlaceholderText(placeholder) end
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

		local function NewTab(sheet, label, icon)
			local scroll = vgui.Create("DScrollPanel")
			sheet:AddSheet(label, scroll, icon)
			return scroll
		end

		local function BuildBoxMode(sheet)
			local p = NewTab(sheet, "Caixas", "icon16/box.png")
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
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildStashMode(sheet)
			local p = NewTab(sheet, "Stash Escondido", "icon16/box_closed.png")
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

			Button(p, "Forçar spawn de caixas de stash agora", function()
				ix.command.Send("stashspawnerforce")
			end)

			modeDefs.stash = {
				addCmd = "stashspawneradd",
				getAddArgs = function()
					local text = categoryCombo:GetSelected()
					if not text or text == "" then return nil end
					return { text }
				end,
				removeCmd = "stashspawnerremove",
				getRemoveArgs = function() return { radius:GetValue() } end,
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildItemSpawnMode(sheet)
			local p = NewTab(sheet, "Itens no Mapa", "icon16/note.png")
			HelpText(p, "Esquerdo: adiciona ponto de itens soltos (worlditemspawner). Direito: remove.")

			local group = TextEntry(p, "Grupo de spawn (pool de itens)", "ex: default")
			local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

			modeDefs.itemspawn = {
				addCmd = "itemspawnadd",
				getAddArgs = function()
					local g = group:GetValue()
					if g == "" then g = "default" end
					return { g }
				end,
				removeCmd = "itemspawnremove",
				getRemoveArgs = function() return { radius:GetValue() } end,
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildRadiationMode(sheet)
			local p = NewTab(sheet, "Radiação", "icon16/error.png")
			HelpText(p, "Marque os tipos permitidos. Esquerdo: adiciona. Direito: remove próximos.")

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
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildAnomalyMode(sheet)
			local p = NewTab(sheet, "Anomalias", "icon16/asterisk_yellow.png")
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
					local bitstring = Bitstring(anomPlugin.anomalydefs, checks)

					if not string.find(bitstring, "1") then
						LocalPlayer():ChatPrint("[Spawn Tool] Marque pelo menos uma anomalia antes de adicionar (aperte R).")
						return nil
					end

					return { areaRadius:GetValue(), bitstring }
				end,
				removeCmd = "anomalyremove",
				getRemoveArgs = function() return { removeRadius:GetValue() } end,
				getPreviewAddRadius = function() return areaRadius:GetValue() end,
				getPreviewRemoveRadius = function() return removeRadius:GetValue() end,
			}
		end

		local function BuildEventMode(sheet)
			local p = NewTab(sheet, "Eventos", "icon16/flag_blue.png")
			HelpText(p, "Esquerdo: adiciona a área de evento na mira. Direito: remove próximas. " ..
				"A dificuldade é um código mapa+local, escolha nos dois dropdowns.")

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

			HelpText(p, "Aviso: hoje não existe evento cadastrado com dígito de mapa 4 " ..
				"(Stalkercotz 1) -- precisa adicionar eventdefs com dificuldade 41-45.")

			local eventPlugin = ix.plugin.list["eventcontroller"]
			local defCombo = Combo(p, "Evento específico (opcional)")
			defCombo:AddChoice("Aleatório (usa a dificuldade acima)", "")

			if eventPlugin and eventPlugin.eventdefs then
				local keys = {}
				for k in pairs(eventPlugin.eventdefs) do keys[#keys + 1] = k end
				table.sort(keys)
				for _, k in ipairs(keys) do defCombo:AddChoice(k, k) end
			end

			defCombo:ChooseOptionID(1)

			local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

			Button(p, "Forçar 1 evento agora", function()
				ix.command.Send("eventforce")
			end)

			Button(p, "Popular eventos agora (rajada)", function()
				ix.command.Send("eventpopulate")
			end)

			modeDefs.event = {
				addCmd = "eventadd",
				getAddArgs = function()
					local name = nameEntry:GetValue()
					if name == "" then name = "UNNAMED AREA" end

					local _, mapDigit = mapCombo:GetSelected()
					local _, typeDigit = typeCombo:GetSelected()
					local difficulty = (mapDigit or 1) * 10 + (typeDigit or 1)

					local defName = defCombo:GetSelected()
					local args = { name, difficulty }
					if defName and defName ~= "" then args[#args + 1] = defName end

					return args
				end,
				removeCmd = "eventremove",
				getRemoveArgs = function() return { radius:GetValue() } end,
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildEventAdvMode(sheet)
			local p = NewTab(sheet, "Eventos Avançados", "icon16/flag_red.png")
			HelpText(p, "Eventos roteirizados específicos. O nome interno precisa bater com " ..
				"um allowedPoints já cadastrado em eventcontrolleradv/sh_eventdefs.lua.")

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

				if keys[1] then internalCombo:ChooseOption(keys[1], 1) end
			end

			local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 1024, 128)

			Button(p, "Forçar 1 evento avançado agora", function()
				ix.command.Send("eventadvforce")
			end)

			Button(p, "Popular eventos avançados agora (rajada)", function()
				ix.command.Send("eventadvpopulate")
			end)

			modeDefs.eventadv = {
				addCmd = "eventadvadd",
				getAddArgs = function()
					local name = nameEntry:GetValue()
					if name == "" then name = "UNNAMED AREA" end

					local internalName = internalCombo:GetSelected()
					if not internalName or internalName == "" then return nil end

					return { name, internalName }
				end,
				removeCmd = "eventadvremove",
				getRemoveArgs = function() return { radius:GetValue() } end,
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function BuildContainerMode(sheet)
			local p = NewTab(sheet, "Containers Cíclicos", "icon16/package.png")
			HelpText(p, "Mire DIRETAMENTE em um container. Esquerdo: marca cíclico. Direito: desmarca.")

			local cyclicPlugin = ix.plugin.list["cycliccontainer"]
			local categoryCombo = Combo(p, "Categoria cíclica")

			if cyclicPlugin and cyclicPlugin.categoryDefs then
				local keys = {}
				for k in pairs(cyclicPlugin.categoryDefs) do keys[#keys + 1] = k end
				table.sort(keys)
				for _, k in ipairs(keys) do categoryCombo:AddChoice(k, k) end
				if keys[1] then categoryCombo:ChooseOption(keys[1], 1) end
			end

			Button(p, "Forçar aparecer com loot novo (mira)", function()
				ix.command.Send("containercyclicalforce")
			end)

			Button(p, "Forçar TODOS os cíclicos do mapa", function()
				ix.command.Send("containercyclicalforceall")
			end)

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

		local function BuildContainerSpawnMode(sheet)
			local p = NewTab(sheet, "Loot em Containers", "icon16/box.png")
			HelpText(p, "Mire DIRETAMENTE em um container. Define um grupo de itens (não " ..
				"tem raio, é sempre no container mirado).")

			local group = TextEntry(p, "Grupo de loot (pool de itens)", "ex: ix_entbox_drops")

			Button(p, "Forçar item no container na mira agora", function()
				ix.command.Send("containerspawnforce")
			end)

			modeDefs.containerspawn = {
				addCmd = "containerspawnadd",
				getAddArgs = function()
					local g = group:GetValue()
					if g == "" then return nil end
					return { g }
				end,
				removeCmd = "containerspawnremove",
				getRemoveArgs = function() return {} end,
			}
		end

		local function BuildContainerEntityMode(sheet)
			local p = NewTab(sheet, "Spawnar Container", "icon16/box_add.png")
			HelpText(p, "Esquerdo: cria um ix_container de verdade (com inventário) no " ..
				"modelo escolhido, na mira. Direito: remove containers próximos.")

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

				if keys[1] then modelCombo:ChooseOptionID(1) end
			end

			local radius = NumberWang(p, "Raio de remoção (botão direito)", 8, 512, 64)

			modeDefs.containerentity = {
				addCmd = "containerspawn",
				getAddArgs = function()
					local model = select(2, modelCombo:GetSelected())
					if not model or model == "" then return nil end
					return { model }
				end,
				removeCmd = "containerentremove",
				getRemoveArgs = function() return { radius:GetValue() } end,
				getPreviewRemoveRadius = function() return radius:GetValue() end,
			}
		end

		local function EnsureSettingsPanel()
			if IsValid(settingsFrame) then return end

			settingsFrame = vgui.Create("DFrame")
			settingsFrame:SetSize(420, 480)
			settingsFrame:SetPos(40, ScrH() / 2 - 240)
			settingsFrame:SetTitle("Spawn Tool - Configurações")
			settingsFrame:SetVisible(false)
			settingsFrame:SetDraggable(true)
			settingsFrame:ShowCloseButton(true)
			settingsFrame.OnClose = function() settingsFrame:SetVisible(false) end

			sheetPanel = vgui.Create("DPropertySheet", settingsFrame)
			sheetPanel:Dock(FILL)
			sheetPanel:DockMargin(2, 2, 2, 2)

			BuildBoxMode(sheetPanel)
			BuildStashMode(sheetPanel)
			BuildItemSpawnMode(sheetPanel)
			BuildRadiationMode(sheetPanel)
			BuildAnomalyMode(sheetPanel)
			BuildEventMode(sheetPanel)
			BuildEventAdvMode(sheetPanel)
			BuildContainerMode(sheetPanel)
			BuildContainerSpawnMode(sheetPanel)
			BuildContainerEntityMode(sheetPanel)

			sheetPanel:SetActiveTab(sheetPanel.Items[activeIndex].Tab)

			for i, item in ipairs(sheetPanel.Items) do
				local oldDoClick = item.Tab.DoClick
				item.Tab.DoClick = function(btn)
					oldDoClick(btn)
					activeIndex = i
				end
			end
		end

		-- Já monta o painel (e os modeDefs/getters de raio) assim que a arma
		-- é equipada, em vez de esperar o jogador apertar R pela primeira
		-- vez — assim a bola de raio já funciona desde o primeiro segundo.
		function SWEP:Deploy()
			EnsureSettingsPanel()
			return true
		end

		function SWEP:ToggleSettings()
			EnsureSettingsPanel()

			if not IsValid(settingsFrame) then return end

			local show = not settingsFrame:IsVisible()
			settingsFrame:SetVisible(show)

			if show then
				settingsFrame:MakePopup()
			else
				settingsFrame:SetMouseInputEnabled(false)
				settingsFrame:SetKeyboardInputEnabled(false)
				gui.EnableScreenClicker(false)
			end
		end

		function SWEP:CycleMode()
			EnsureSettingsPanel()

			activeIndex = (activeIndex % #self.ModeOrder) + 1
			local id = self.ModeOrder[activeIndex]

			if IsValid(sheetPanel) and sheetPanel.Items[activeIndex] then
				sheetPanel:SetActiveTab(sheetPanel.Items[activeIndex].Tab)
			end

			local ply = LocalPlayer()
			if IsValid(ply) then
				ply:ChatPrint("[Spawn Tool] Modo: " .. (self.ModeLabels[id] or id))
			end
			surface.PlaySound("buttons/lightswitch2.wav")
		end

		function SWEP:DoAdd()
			EnsureSettingsPanel()

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
			EnsureSettingsPanel()

			local id = self.ModeOrder[activeIndex]
			local def = modeDefs[id]
			if not def or not def.removeCmd then return end

			local args = def.getRemoveArgs and def.getRemoveArgs() or {}
			ix.command.Send(def.removeCmd, unpack(args))
			self:EmitSound("weapons/toolgun/toolgun_use.wav")
		end

		local PREVIEW_ADD_COLOR = Color(80, 220, 120, 90)
		local PREVIEW_REMOVE_COLOR = Color(220, 90, 70, 90)

		-- debugoverlay.* depende do sistema de debug do engine, que em geral
		-- só desenha de verdade com sv_cheats 1 no servidor. Usamos
		-- render.DrawSphere dentro de PostDrawTranslucentRenderables, que é
		-- renderização real e não depende de cheats.
		hook.Add("PostDrawTranslucentRenderables", "SpawnTool_SpherePreview", function()
			local ply = LocalPlayer()
			if not IsValid(ply) then return end

			local wpn = ply:GetActiveWeapon()
			if not IsValid(wpn) or wpn:GetClass() != "weapon_spawntool" then return end

			local id = wpn.ModeOrder[activeIndex]
			local def = modeDefs[id]
			if not def then return end

			local trace = ply:GetEyeTrace()
			if not trace.Hit then return end

			local pos = trace.HitPos

			render.SetColorMaterial()

			if def.getPreviewAddRadius then
				local r = def.getPreviewAddRadius()
				if r and r > 0 then
					render.DrawSphere(pos, r, 24, 24, PREVIEW_ADD_COLOR)
				end
			end

			if def.getPreviewRemoveRadius then
				local r = def.getPreviewRemoveRadius()
				if r and r > 0 then
					render.DrawSphere(pos, r, 24, 24, PREVIEW_REMOVE_COLOR)
				end
			end
		end)

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
	end

	weapons.Register(SWEP, "weapon_spawntool")
end

-- Dá a arma "Spawn Tool" (estilo tool gun) para o admin. Ela cobre as mesmas
-- ações do painel gráfico, mas por clique: esquerdo adiciona, direito remove,
-- clique do meio troca o modo, e R abre as configurações do modo atual.
ix.command.Add("spawntool", {
	superAdminOnly = true,
	OnRun = function(self, client)
		if not client:HasWeapon("weapon_spawntool") then
			client:Give("weapon_spawntool")
		end

		client:SelectWeapon("weapon_spawntool")
		client:Notify("Spawn Tool equipada. Aperte R para abrir as configurações.")
	end
})

-- ---------------------------------------------------------------------
-- Spawn de containers de verdade (ix_container), replicando o que o
-- Helix faz sozinho em PLUGIN:PlayerSpawnedProp (plugin "containers")
-- quando um prop com um modelo registrado em ix.container.stored é
-- spawnado. Como este schema não é sandbox, não existe o menu de spawn
-- de props pra fazer isso "sozinho", então esse comando faz na mão:
-- cria a entidade, aplica o modelo e já cria o inventário certo.
-- ---------------------------------------------------------------------
ix.command.Add("containerspawn", {
	superAdminOnly = true,
	arguments = {
		ix.type.string,
	},
	OnRun = function(self, client, model)
		if not SERVER then return end

		model = string.lower(model or "")
		local data = ix.container.stored and ix.container.stored[model]

		if not data then
			client:Notify("Esse model não está registrado em ix.container.stored (veja containers/sh_definitions.lua).")
			return
		end

		local trace = client:GetEyeTraceNoCursor()
		local pos = trace.HitPos + trace.HitNormal * 2

		local container = ents.Create("ix_container")
		container:SetPos(pos)
		container:SetAngles(Angle(0, client:EyeAngles().y, 0))
		container:SetModel(model)
		container:Spawn()

		local physObj = container:GetPhysicsObject()
		if IsValid(physObj) then
			physObj:EnableMotion(true)
			physObj:Wake()
		end

		ix.inventory.New(0, "container:" .. model, function(inventory)
			inventory.vars.isBag = true
			inventory.vars.isContainer = true

			if IsValid(container) then
				container:SetInventory(inventory)

				local containersPlugin = ix.plugin.list["containers"]
				if containersPlugin and containersPlugin.SaveContainer then
					containersPlugin:SaveContainer()
				end
			end
		end)

		client:Notify("Container '" .. (data.name or model) .. "' criado.")
	end
})

ix.command.Add("containerentremove", {
	superAdminOnly = true,
	arguments = {
		ix.type.number,
	},
	OnRun = function(self, client, range)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal * 5
		local removed = 0

		for _, ent in ipairs(ents.FindByClass("ix_container")) do
			if ent:GetPos():Distance(hitpos) <= (range or 128) then
				ent:Remove()
				removed = removed + 1
			end
		end

		client:Notify(removed .. " container(s) removido(s).")
	end
})

-- ---------------------------------------------------------------------
-- Descobrir o uniqueID de um item já jogado no chão (ix_item), pra usar
-- nos campos de pool/grupo das outras abas.
-- ---------------------------------------------------------------------
ix.command.Add("itemid", {
	OnRun = function(self, client)
		if not SERVER then return end

		local trace = client:GetEyeTraceNoCursor()
		local ent = trace.Entity

		if not IsValid(ent) or ent:GetClass() != "ix_item" then
			client:Notify("Mire em um item jogado no chão e tente de novo.")
			return
		end

		local itemTable = ent:GetItemTable()

		if not itemTable then
			client:Notify("Esse item não tem uma itemTable válida.")
			return
		end

		client:Notify("uniqueID: " .. itemTable.uniqueID .. "  |  nome: " .. (itemTable.name or "?"))
		client:PrintMessage(HUD_PRINTCONSOLE, "[itemid] uniqueID: " .. itemTable.uniqueID .. " | nome: " .. (itemTable.name or "?"))
	end
})
