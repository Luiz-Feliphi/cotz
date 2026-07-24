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

				local spawn = self:GetMatchingEventDef(eventpoint[3])
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

		local spawn = self:GetMatchingEventDef(eventpoint[3])
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

end

ix.command.Add("eventadd", {
	superAdminOnly = true,
	arguments = {
		ix.type.string,
		ix.type.number
	},
	OnRun = function(self, client, name, difficulty)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local name = name or "UNNAMED AREA"
		local difficulty = difficulty or 1

		if isnumber(difficulty) then
			table.insert( PLUGIN.eventpoints[game.GetMap()], { hitpos, name, difficulty } )
			client:Notify( "Event area named '"..name.."' with difficulty "..difficulty.." succesfully added"  )
		else
			client:ChatPrint("Difficulty must be a number.")
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

		local spawn = PLUGIN:GetMatchingEventDef(eventpoint[3])

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

			local spawn = PLUGIN:GetMatchingEventDef(eventpoint[3])
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