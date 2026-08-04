local PLUGIN = PLUGIN
PLUGIN.name = "EventController"
PLUGIN.author = "gumlefar"
PLUGIN.desc = "Makes events occur randomly on your server - used more like a monster spawner now, more complex and intricate events are possible in eventcontrolleradv"

PLUGIN.eventdefs = PLUGIN.eventdefs or {}
PLUGIN.eventpoints = PLUGIN.eventpoints or {} -- EVENTPOINT STRUCTURE table.insert( PLUGIN.eventpoints, { position, name, difficulty } )

ix.util.Include("sh_eventdefs.lua")

PLUGIN.spawnradius = 750
PLUGIN.populateAmount = 7

PLUGIN.pdachatter = false 
PLUGIN.pdachatterchance = 100

PLUGIN.saferadius = 1500

PLUGIN.spawnrate = 30

-- Categorias do menu nativo de NPCs (list.Get("NPC"), o mesmo menu que
-- aparece no F4 -> NPCs) que serão exibidas na aba "NPCs Personalizados"
-- do /eventmenu. Adicione/remova nomes de categoria aqui se seus NPCs
-- do STALKER estiverem cadastrados sob outro nome.
PLUGIN.customSpawnCategories = {
	"S.T.A.L.K.E.R RP",
	"S.T.A.L.K.E.R RP Humans",
	"Zumbis + Aliens Inimigos",
}

-- Limites de segurança para o spawn personalizado via /eventmenu, pra um
-- admin não travar o servidor pedindo 500 controllers de uma vez.
PLUGIN.customSpawnMaxPerClass = 50
PLUGIN.customSpawnMaxTotal = 60
PLUGIN.eventDefMaxRepeats = 10

local icon = Material("vgui/icons/news.png")

ix.config.Add("eventControllerThreshold", 70, "How many mutants should the controller keep on the map.", nil, {
	data = {min = 10, max = 100},
	category = "Spawning"
})

if SERVER then
	local spawntime = 1
	local populate = true
	
	function PLUGIN:IsClear(position)
		
		local currentdefs = {}
		local currentents = ents.FindInSphere( position, PLUGIN.saferadius )

		for i,j in pairs (currentents) do
			if j:IsPlayer() then
				return false
			elseif (string.sub(j:GetClass(), 1, 4) == "npc_") then
				return false
			end
		end
		return true
	end
	
	function PLUGIN:spawnEvent(eventpoint, spawn)
		--spawnents
		if spawn.entities then
			for k = 1, #spawn.entities do
				for i = 1, spawn.entities[k][2] do
					local position = self:GetSpawnLocation( eventpoint[1] )
					local data = {}
					data.start = position
					data.endpos = position
					data.mins = Vector(-96, -96, 0)
					data.maxs = Vector(96, 96, 256)

					-- local trace = util.TraceHull(data)		
					-- if trace.Hit then
					-- 	continue
					-- end

					local newNPC = ents.Create(spawn.entities[k][1])

					-- Se a classe não existir no servidor (addon de mutantes
					-- faltando, nome errado, etc), ents.Create devolve uma
					-- entidade inválida -- sem isso aqui, o resto do código
					-- rodava "com sucesso" sem nada aparecer, sem erro nenhum.
					if not IsValid(newNPC) then
						ErrorNoHalt("[EventController] Classe de NPC inválida (addon faltando?): '" ..
							tostring(spawn.entities[k][1]) .. "'\n")
						continue
					end

					newNPC:SetPos(position)
					newNPC:Spawn()
					newNPC:DropToFloor()
				end
			end
		end
		--spawnitems
		if spawn.items then
			for k = 1, #spawn.items do
				local position = self:GetSpawnLocation( eventpoint[1] )
				local data = {}
				data.start = position
				data.endpos = position
				data.mins = Vector(-16, -16, 0)
				data.maxs = Vector(16, 16, 71)
				local trace = util.TraceHull(data)
					
				if trace.Entity:IsValid() then
					continue
				end
				ix.item.Spawn(spawn.items[k][1], position, nil, AngleRand(), spawn.items[k][2] or {})
			end
		end
			
		--spawn loot
		if spawn.loot then
			/*for k = 1, #spawn.loot do
				for i = 1, spawn.loot[k][2] do
					local position = self:GetSpawnLocation( eventpoint[1] )
					local data = {}
					data.start = position
					data.endpos = position
					data.mins = Vector(-16, -16, 0)
					data.maxs = Vector(16, 16, 71)
					local trace = util.TraceHull(data)
						
					if trace.Entity:IsValid() then
						continue
					end

					if math.random(100) <= spawn.lootChance then
						ix.item.Spawn(spawn.loot[k][1], position, nil, AngleRand(), spawn.loot[k][3] or {})
					end
				end
			end*/
		end
	end

	function PLUGIN:setSpawnTime(time)
		spawntime = time
	end
	
	function PLUGIN:setPopulate(bool)
		populate = bool
	end

	function PLUGIN:LoadData()
		self.eventpoints = self:GetData() or {}

		self.eventpoints[game.GetMap()] = self.eventpoints[game.GetMap()] or {}
	end

	function PLUGIN:SaveData()
		self:SetData(self.eventpoints)
	end

	function PLUGIN:GetSpawnLocation( pos )
		local tracegood = false
		local teleres
		local tracecnt = 0

		repeat
			local trace = util.TraceHull( {
				start = pos + Vector(0,0,16),
				endpos = pos + Vector(math.random(-PLUGIN.spawnradius,PLUGIN.spawnradius),math.random(-PLUGIN.spawnradius,PLUGIN.spawnradius),0),
				mins = Vector(-96, -96, 0),
				maxs = Vector(96, 96, 256),
				mask = MASK_SOLID,
				ignoreworld = false
			} )

			if not trace.Hit then
				tracegood = true
				teleres = trace.HitPos + ( trace.HitNormal * 32 )
			end

			tracecnt = tracecnt + 1

			if tracecnt > 50 then
				tracegood = true
				teleres = pos + Vector(0, 0, 16) -- Teleport to original position if we cant find a position
			end

		until tracegood


		return teleres
	end
	
	function PLUGIN:Think()
		if table.IsEmpty(self.eventpoints) then return end

		if populate then
			for i = 1, self.populateAmount do
				local eventpoint = table.Random(self.eventpoints[game.GetMap()])

				-- Antes, um "return" aqui saía da função inteira sem nunca
				-- zerar "populate", deixando ele preso em true (o Think
				-- ficava tentando de novo a cada tick, do zero). Agora só
				-- pulamos essa tentativa e seguimos as outras.
				if (!eventpoint) then continue end

				local spawn = self:GetEventDefForPoint(eventpoint)
				if (!spawn) then continue end

				self:spawnEvent(eventpoint,spawn)
			end
			
			populate = false
		end
		
		if spawntime > CurTime() then return end
		spawntime = CurTime() + self.spawnrate

		if( self:GetNumMutants() > ix.config.Get("eventControllerThreshold",35)) then return end

		local eventpoint = table.Random(self.eventpoints[game.GetMap()])
		if (!eventpoint) then
			return
		end
		if( !self:IsClear(eventpoint[1]) ) then return end

		local spawn = self:GetEventDefForPoint(eventpoint)
		if (!spawn) then return end

		self:spawnEvent(eventpoint, spawn)
		
		if ix.progression.IsCompleted("muteItemDelivery_Broadcast") then
			self.pdachatter = true
		else
			self.pdachatter = false
		end

		if self.pdachatter == true then
			if math.Rand(1,100) <= self.pdachatterchance then
				for k, ply in pairs( player.GetAll() ) do
					ix.chat.Send(ply, "eventpdainternal", Format(spawn.pdabroadcast, eventpoint[2]), true, ply)
					 // ply:EmitSound( "stalkersound/pda/pda.wav", 50, 100, 1, CHAN_AUTO )
				end
			end
		end

	end	

	function PLUGIN:GetNumMutants()
		return #ents.FindByClass("npc_*")
	end

	local function GetAimPosition(client)
		local trace = client:GetEyeTraceNoCursor()
		return trace.HitPos + trace.HitNormal * 5
	end

	-- Spawna um eventdef já cadastrado (dos sh_eventdefs.lua) "amount" vezes
	-- no ponto que o admin está mirando, ao invés de sortear aleatoriamente.
	netstream.Hook("ixEventMenuSpawnDef", function(client, defName, amount)
		if not IsValid(client) or not client:IsAdmin() then return end
		if not isstring(defName) then return end

		local def = PLUGIN.eventdefs[defName]

		if not def then
			client:Notify("Evento '" .. tostring(defName) .. "' não existe em sh_eventdefs.lua.")
			return
		end

		amount = math.Clamp(math.Round(tonumber(amount) or 1), 1, PLUGIN.eventDefMaxRepeats)

		local hitpos = GetAimPosition(client)
		local eventpoint = {hitpos, "Evento Manual (" .. client:Nick() .. ")", 0}

		local before = #ents.FindByClass("npc_*")

		for i = 1, amount do
			PLUGIN:spawnEvent(eventpoint, def)
		end

		local after = #ents.FindByClass("npc_*")

		client:Notify(Format("Evento '%s' spawnado %d vez(es). %d NPC(s) novo(s) no mapa.",
			defName, amount, after - before))
	end)

	-- Spawna uma lista de NPCs escolhidos manualmente (classe + quantidade)
	-- no ponto que o admin está mirando. Valida cada classe contra o menu
	-- nativo de NPCs (list.Get("NPC")) pra impedir ents.Create arbitrário.
	netstream.Hook("ixEventMenuSpawnCustom", function(client, payload)
		if not IsValid(client) or not client:IsAdmin() then return end
		if not istable(payload) then return end

		local npcRegistry = list.Get("NPC") or {}
		local sanitized = {}
		local totalRequested = 0

		for _, entry in ipairs(payload) do
			local class = entry[1]
			local count = math.Clamp(math.Round(tonumber(entry[2]) or 0), 0, PLUGIN.customSpawnMaxPerClass)

			if isstring(class) and npcRegistry[class] and count > 0 then
				sanitized[#sanitized + 1] = {class, count}
				totalRequested = totalRequested + count
			end
		end

		if #sanitized == 0 then
			client:Notify("Nenhum NPC válido foi enviado.")
			return
		end

		if totalRequested > PLUGIN.customSpawnMaxTotal then
			client:Notify("Você pediu " .. totalRequested .. " NPCs de uma vez -- o limite é " ..
				PLUGIN.customSpawnMaxTotal .. ". Reduza a quantidade.")
			return
		end

		local hitpos = GetAimPosition(client)
		local eventpoint = {hitpos, "NPCs Personalizados (" .. client:Nick() .. ")", 0}
		local spawn = {entities = sanitized}

		local before = #ents.FindByClass("npc_*")
		PLUGIN:spawnEvent(eventpoint, spawn)
		local after = #ents.FindByClass("npc_*")

		client:Notify((after - before) .. " NPC(s) personalizado(s) spawnado(s) no ponto mirado.")
	end)

	-- Antes disso, o código escolhia um eventdef ALEATÓRIO e só depois
	-- checava (também por sorteio) se a dificuldade batia -- então mesmo
	-- quando existia um evento válido pra aquele ponto, podia falhar por
	-- pura falta de sorte em até 15 tentativas. Agora filtramos direto
	-- quais eventdefs realmente aceitam essa dificuldade e sorteamos só
	-- entre eles.
	function PLUGIN:GetMatchingEventDef(difficulty)
		local candidates = {}

		for _, def in pairs(self.eventdefs) do
			if def.difficulty and table.HasValue(def.difficulty, difficulty) then
				candidates[#candidates + 1] = def
			end
		end

		if #candidates == 0 then return nil end

		return table.Random(candidates)
	end

	-- Pontos podem opcionalmente ter um 4º valor (eventpoint[4]) com o
	-- nome EXATO de um eventdef -- nesse caso, sempre usamos esse evento
	-- específico em vez de sortear entre os que batem com a dificuldade.
	-- Pontos antigos (só 3 valores, sem nome fixo) continuam funcionando
	-- exatamente como antes.
	function PLUGIN:GetEventDefForPoint(eventpoint)
		local defName = eventpoint[4]

		if defName and defName ~= "" and self.eventdefs[defName] then
			return self.eventdefs[defName]
		end

		return self:GetMatchingEventDef(eventpoint[3])
	end
else
	netstream.Hook("nut_DisplaySpawnPoints", function(data)
		for k, v in pairs(data) do
			local emitter = ParticleEmitter( v[1] )
			local smoke = emitter:Add( "sprites/glow04_noz", v[1] )
			smoke:SetVelocity( Vector( 0, 0, 1 ) )
			smoke:SetDieTime(10)
			smoke:SetStartAlpha(255)
			smoke:SetEndAlpha(255)
			smoke:SetStartSize(64)
			smoke:SetEndSize(64)
			smoke:SetColor(255,186,50)
			smoke:SetAirResistance(300)
		end
	end)

	--[[-------------------------------------------------------------------------
	Menu de eventos (/eventmenu)

	Duas abas:
	1) "Eventos Pré-definidos" - lista os eventdefs de sh_eventdefs.lua
	   (o arquivo é sh_, então PLUGIN.eventdefs já existe aqui no client)
	   e permite escolher um e repeti-lo N vezes no ponto mirado.
	2) "NPCs Personalizados" - lista os NPCs registrados no menu nativo
	   (list.Get("NPC"), o mesmo menu do F4 -> NPCs) filtrados pelas
	   categorias em PLUGIN.customSpawnCategories, permitindo escolher
	   quais NPCs e quantos de cada spawnar no ponto mirado.
	---------------------------------------------------------------------------]]
	function PLUGIN:OpenEventMenu()
		if IsValid(self.eventMenuFrame) then
			self.eventMenuFrame:Remove()
		end

		local frame = vgui.Create("DFrame")
		frame:SetSize(700, 520)
		frame:Center()
		frame:SetTitle("Gerenciador de Eventos")
		frame:MakePopup()
		self.eventMenuFrame = frame

		local sheet = vgui.Create("DPropertySheet", frame)
		sheet:Dock(FILL)

		----------------------------------------------------------------
		-- Aba 1: eventos pré-definidos
		----------------------------------------------------------------
		local defPanel = vgui.Create("DPanel")
		defPanel.Paint = function() end

		local defSearch = vgui.Create("DTextEntry", defPanel)
		defSearch:Dock(TOP)
		defSearch:DockMargin(5, 5, 5, 5)
		defSearch:SetPlaceholderText("Buscar evento por nome...")

		local defList = vgui.Create("DListView", defPanel)
		defList:Dock(FILL)
		defList:DockMargin(5, 0, 5, 5)
		defList:SetMultiSelect(false)
		defList:AddColumn("Evento")
		defList:AddColumn("Dificuldades")
		defList:AddColumn("NPCs")

		local function PopulateDefList(filter)
			defList:Clear()

			local keys = {}
			for name in pairs(self.eventdefs) do
				keys[#keys + 1] = name
			end
			table.sort(keys)

			for _, name in ipairs(keys) do
				if filter and filter ~= "" and not string.find(string.lower(name), string.lower(filter), 1, true) then
					continue
				end

				local def = self.eventdefs[name]
				local diffStr = def.difficulty and table.concat(def.difficulty, ", ") or ""
				local npcParts = {}

				if def.entities then
					for _, ent in ipairs(def.entities) do
						npcParts[#npcParts + 1] = ent[1] .. " x" .. ent[2]
					end
				end

				local line = defList:AddLine(name, diffStr, table.concat(npcParts, ", "))
				line.eventName = name
			end
		end

		PopulateDefList()

		defSearch.OnChange = function(this)
			PopulateDefList(this:GetValue())
		end

		local defBottom = vgui.Create("DPanel", defPanel)
		defBottom:Dock(BOTTOM)
		defBottom:SetTall(70)
		defBottom.Paint = function() end

		local amountLabel = vgui.Create("DLabel", defBottom)
		amountLabel:Dock(TOP)
		amountLabel:DockMargin(5, 5, 5, 0)
		amountLabel:SetText("Quantas vezes repetir o evento escolhido (máx " .. self.eventDefMaxRepeats .. "):")
		amountLabel:SizeToContentsY()

		local amountSlider = vgui.Create("DNumSlider", defBottom)
		amountSlider:Dock(TOP)
		amountSlider:DockMargin(5, 0, 5, 0)
		amountSlider:SetText("")
		amountSlider:SetMin(1)
		amountSlider:SetMax(self.eventDefMaxRepeats)
		amountSlider:SetDecimals(0)
		amountSlider:SetValue(1)

		local spawnDefBtn = vgui.Create("DButton", defBottom)
		spawnDefBtn:Dock(BOTTOM)
		spawnDefBtn:DockMargin(5, 5, 5, 0)
		spawnDefBtn:SetText("Spawnar evento selecionado no ponto que estou mirando")
		spawnDefBtn.DoClick = function()
			local selected = defList:GetSelectedLine()

			if not selected then
				LocalPlayer():ChatPrint("Selecione um evento na lista primeiro.")
				return
			end

			local line = defList:GetLine(selected)
			local amount = math.Round(amountSlider:GetValue())

			netstream.Start("ixEventMenuSpawnDef", line.eventName, amount)
			frame:Close()
		end

		sheet:AddSheet("Eventos Pré-definidos", defPanel, "icon16/bricks.png")

		----------------------------------------------------------------
		-- Aba 2: NPCs personalizados
		----------------------------------------------------------------
		local customPanel = vgui.Create("DPanel")
		customPanel.Paint = function() end

		local npcSearch = vgui.Create("DTextEntry", customPanel)
		npcSearch:Dock(TOP)
		npcSearch:DockMargin(5, 5, 5, 5)
		npcSearch:SetPlaceholderText("Buscar NPC por nome ou classe...")

		local npcList = vgui.Create("DListView", customPanel)
		npcList:Dock(FILL)
		npcList:DockMargin(5, 0, 0, 5)
		npcList:SetMultiSelect(false)
		npcList:AddColumn("NPC")
		npcList:AddColumn("Classe")
		npcList:AddColumn("Categoria")

		local selectedPanel = vgui.Create("DScrollPanel", customPanel)
		selectedPanel:Dock(RIGHT)
		selectedPanel:SetWide(230)
		selectedPanel:DockMargin(5, 0, 5, 5)

		local selectedNPCs = {} -- [class] = {name = "...", count = N}

		local function RefreshSelectedList()
			selectedPanel:Clear()

			for class, info in pairs(selectedNPCs) do
				local row = vgui.Create("DPanel", selectedPanel)
				row:Dock(TOP)
				row:SetTall(55)
				row:DockMargin(0, 0, 5, 4)
				row.Paint = function(this, w, h)
					surface.SetDrawColor(50, 50, 50, 220)
					surface.DrawRect(0, 0, w, h)
				end

				local lbl = vgui.Create("DLabel", row)
				lbl:Dock(TOP)
				lbl:DockMargin(4, 2, 20, 0)
				lbl:SetText(info.name)
				lbl:SetTextColor(color_white)

				local num = vgui.Create("DNumberWang", row)
				num:Dock(TOP)
				num:DockMargin(4, 2, 20, 2)
				num:SetMin(1)
				num:SetMax(self.customSpawnMaxPerClass)
				num:SetValue(info.count)
				num.OnValueChanged = function(this, val)
					if selectedNPCs[class] then
						selectedNPCs[class].count = math.Round(val)
					end
				end

				local remove = vgui.Create("DButton", row)
				remove:SetText("Remover")
				remove:Dock(BOTTOM)
				remove:SetTall(18)
				remove.DoClick = function()
					selectedNPCs[class] = nil
					RefreshSelectedList()
				end
			end
		end

		local function PopulateNPCList(filter)
			npcList:Clear()

			local npcRegistry = list.Get("NPC") or {}
			local allowedCategories = self.customSpawnCategories or {}
			local rows = {}

			for class, data in pairs(npcRegistry) do
				local category = data.Category or "Sem categoria"

				if #allowedCategories > 0 and not table.HasValue(allowedCategories, category) then
					continue
				end

				local name = data.Name or class

				if filter and filter ~= "" then
					local f = string.lower(filter)
					if not string.find(string.lower(name), f, 1, true) and not string.find(string.lower(class), f, 1, true) then
						continue
					end
				end

				rows[#rows + 1] = {name = name, class = class, category = category}
			end

			table.sort(rows, function(a, b) return a.name < b.name end)

			for _, row in ipairs(rows) do
				local line = npcList:AddLine(row.name, row.class, row.category)
				line.npcClass = row.class
				line.npcName = row.name
			end
		end

		PopulateNPCList()

		npcSearch.OnChange = function(this)
			PopulateNPCList(this:GetValue())
		end

		npcList.OnRowRightClick = function(this, index, line)
			if not selectedNPCs[line.npcClass] then
				selectedNPCs[line.npcClass] = {name = line.npcName, count = 1}
				RefreshSelectedList()
			end
		end

		local hint = vgui.Create("DLabel", customPanel)
		hint:Dock(BOTTOM)
		hint:DockMargin(5, 0, 5, 2)
		hint:SetText("Clique com o botão direito num NPC da lista da esquerda pra adicioná-lo à direita.")
		hint:SetTextColor(Color(200, 200, 200))

		local spawnCustomBtn = vgui.Create("DButton", customPanel)
		spawnCustomBtn:Dock(BOTTOM)
		spawnCustomBtn:DockMargin(5, 5, 5, 5)
		spawnCustomBtn:SetTall(32)
		spawnCustomBtn:SetText("Spawnar NPCs selecionados no ponto que estou mirando")
		spawnCustomBtn.DoClick = function()
			if table.IsEmpty(selectedNPCs) then
				LocalPlayer():ChatPrint("Selecione ao menos 1 NPC antes de spawnar.")
				return
			end

			local payload = {}

			for class, info in pairs(selectedNPCs) do
				payload[#payload + 1] = {class, info.count}
			end

			netstream.Start("ixEventMenuSpawnCustom", payload)
			frame:Close()
		end

		sheet:AddSheet("NPCs Personalizados", customPanel, "icon16/user.png")
	end

	netstream.Hook("ixOpenEventMenu", function()
		PLUGIN:OpenEventMenu()
	end)
end

ix.command.Add("eventadd", {
	superAdminOnly = true,
	arguments = {
		ix.type.string,
		ix.type.number,
		bit.bor(ix.type.string, ix.type.optional),
	},
	OnRun = function(self, client, name, difficulty, eventDefName)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local name = name or "UNNAMED AREA"
		local difficulty = difficulty or 1

		if not isnumber(difficulty) then
			client:ChatPrint("Difficulty must be a number.")
			return
		end

		-- Se o nome do evento vier errado/não existir mais em
		-- sh_eventdefs.lua, não trava o ponto com um nome inválido pra
		-- sempre -- salva só com a dificuldade (comportamento antigo).
		if eventDefName and eventDefName ~= "" and not PLUGIN.eventdefs[eventDefName] then
			client:Notify("Aviso: '" .. eventDefName .. "' não existe em sh_eventdefs.lua -- ponto salvo só com a dificuldade, sem evento fixo.")
			eventDefName = nil
		end

		table.insert( PLUGIN.eventpoints[game.GetMap()], { hitpos, name, difficulty, eventDefName } )

		if eventDefName and eventDefName ~= "" then
			client:Notify( "Event area named '"..name.."' fixado no evento '"..eventDefName.."' (dificuldade "..difficulty..")" )
		else
			client:Notify( "Event area named '"..name.."' with difficulty "..difficulty.." succesfully added"  )
		end
	end
})

ix.command.Add("eventremove", {
	superAdminOnly = true,
	OnRun = function(self, client, arguments)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local range = arguments[1] or 128
		local mt = 0
		for k, v in pairs( PLUGIN.eventpoints[game.GetMap()] ) do
			local distance = v[1]:Distance( hitpos )
			if distance <= tonumber(range) then
				PLUGIN.eventpoints[game.GetMap()][k] = nil
				mt = mt + 1
			end
		end
		client:Notify( mt .. " event locations has been removed.")
	end
})

ix.command.Add("eventdisplay", {
	adminOnly = true,
	OnRun = function(self, client, arguments)
		if SERVER then
			netstream.Start(client, "nut_DisplaySpawnPoints", PLUGIN.eventpoints[game.GetMap()])
			client:Notify( "Displayed All Points for 10 secs." )
		end
	end
})

ix.command.Add("eventmenu", {
	adminOnly = true,
	OnRun = function(self, client)
		netstream.Start(client, "ixOpenEventMenu")
	end
})

ix.command.Add("eventforce", {
	adminOnly = true,
	OnRun = function(self, client)
		local points = PLUGIN.eventpoints[game.GetMap()]

		if table.IsEmpty(points or {}) then
			client:Notify("Nenhum ponto de evento neste mapa ainda. Use /eventadd primeiro.")
			return
		end

		local eventpoint = table.Random(points)
		if not eventpoint then
			client:Notify("Não consegui escolher um ponto de evento.")
			return
		end

		local spawn = PLUGIN:GetEventDefForPoint(eventpoint)

		if not spawn then
			client:Notify("Nenhum evento em sh_eventdefs.lua usa a dificuldade " ..
				tostring(eventpoint[3]) .. " (ponto '" .. eventpoint[2] .. "'). Confira a dificuldade do ponto.")
			return
		end

		client:Notify("Rodando evento no ponto '" .. eventpoint[2] .. "' (dificuldade " .. eventpoint[3] .. ")...")

		local before = #ents.FindByClass("npc_*")
		PLUGIN:spawnEvent(eventpoint, spawn)
		local after = #ents.FindByClass("npc_*")

		if after > before then
			client:Notify((after - before) .. " NPC(s) apareceram no mapa.")
		else
			client:Notify("O evento rodou, mas NENHUM NPC apareceu. Provavelmente a(s) classe(s) de " ..
				"NPC desse evento não existem nesse servidor (addon de mutantes faltando?). " ..
				"Confira o console do servidor -- toda classe inválida agora é impressa lá.")
		end
	end
})

ix.command.Add("eventpopulate", {
	adminOnly = true,
	--syntax = "<number amount>",
	OnRun = function(self, client, arguments)
		local points = PLUGIN.eventpoints[game.GetMap()]

		if table.IsEmpty(points or {}) then
			client:Notify("Nenhum ponto de evento neste mapa ainda. Use /eventadd primeiro.")
			return
		end

		local before = #ents.FindByClass("npc_*")
		local eventsRan = 0

		for i = 1, PLUGIN.populateAmount do
			local eventpoint = table.Random(points)
			if not eventpoint then continue end

			local spawn = PLUGIN:GetEventDefForPoint(eventpoint)
			if not spawn then continue end

			PLUGIN:spawnEvent(eventpoint, spawn)
			eventsRan = eventsRan + 1
		end

		local after = #ents.FindByClass("npc_*")

		client:Notify(eventsRan .. "/" .. PLUGIN.populateAmount .. " eventos rodaram, " ..
			(after - before) .. " NPC(s) novo(s) no mapa.")

		if after == before then
			client:Notify("Nenhum NPC novo apareceu -- confira o console do servidor " ..
				"(classes inválidas são impressas lá agora) ou se os pontos têm dificuldade " ..
				"compatível com algum evento cadastrado.")
		end
		--local amount = tonumber(arguments[1]) or 5
		--if isnumber(amount) then
		--	PLUGIN.populateAmount = arguments[1]
		--else
		--	client:ChatPrint("Amount must be a number.")
		--end
	end
})	