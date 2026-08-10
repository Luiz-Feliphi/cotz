local PLUGIN = PLUGIN
PLUGIN.name = "EventController - Adv"
PLUGIN.author = "gumlefar"
PLUGIN.desc = "Makes events occur randomly on your server. More intricate and complex configuration possible."

PLUGIN.eventdefs = PLUGIN.eventdefs or {}
PLUGIN.eventpoints = PLUGIN.eventpoints or {} -- EVENTPOINT STRUCTURE table.insert( PLUGIN.eventpoints, { position, name, difficulty } )

ix.util.Include("sh_eventdefs.lua")

ix.config.Add("eventControllerAdvThreshold", 5, "How many events can be active at any one time.", nil, {
	data = {min = 1, max = 50},
	category = "Spawning"
})

PLUGIN.updaterate = 5
PLUGIN.noSpaceRate = 450

PLUGIN.spawnratebase = 5400
PLUGIN.spawnrateplayer = 30
PLUGIN.spawnradius = 128
PLUGIN.populateAmount = 5

PLUGIN.saferadius = 1000

PLUGIN.currentEvents = {} --To keep track of and update running events

PLUGIN.spawntime = CurTime() + math.random(3600, 7200)
PLUGIN.updatetime = CurTime() + 30
PLUGIN.populate = false

-- Mesmo controle de "aguarda limpar antes de spawnar de novo" do
-- eventcontroller, mas por PONTO individual (não uma contagem global).
-- Como aqui os NPCs são criados dentro dos funcStart/funcUpdate de cada
-- eventdef (sh_eventdefs.lua), os próprios eventdefs precisam chamar
-- PLUGIN:TrackEventNPC(ent, dat.eventpoint) ao criar um NPC pra entrar
-- nessa contagem (o "Dog_Ambush" já foi ajustado). Cobre também spawns
-- forçados via /eventadvforce, que passam pelo mesmo spawnEvent -- eles
-- só não são bloqueados pelo gate, mas contam pra ele.
PLUGIN.eventNPCCheckInterval = 300 -- 5 minutos
PLUGIN.eventSpawnGraceTime = 300 -- 5 minutos
PLUGIN.spawnedNPCsByPoint = PLUGIN.spawnedNPCsByPoint or {} -- [eventpoint] = {[entity]=true, ...}
PLUGIN.pointGateState = PLUGIN.pointGateState or {} -- [eventpoint] = {allowedTime = nil/timestamp}
PLUGIN.nextEventCheck = 0

local icon = "vgui/icons/news.png"

PLUGIN.MapToDifficultyMap = {
	["rp_marsh_cs"] = 1,
	["rp_waystation"] = 2,
	["rp_pripyat_remaster"] = 3,
	["stalkercotz_1"] = 4, -- ainda não existe nenhum eventdef com difficulty = 4,
	                       -- então eventos avançados não vão spawnar aqui até
	                       -- vocês cadastrarem algum em sh_eventdefs.lua.
}

ix.chat.Register("eventpda", {
	CanSay = function(self, speaker, text)
		if IsValid(speaker) then
			if speaker:IsAdmin() or speaker:GetCharacter():HasFlags("N") then
				return true
			else
				return false
			end
		else
			return false
		end
	end,
	OnChatAdd = function(self, speaker, text)
		chat.AddText(Color(0,191,255), "[LPDA-SYSTEM] ", Color(0,241,255), ix.util.GetMaterial(icon), ": "..text)
	end,
	prefix = {"/eventpda"},
	CanHear = function(self, speaker, listener)
		local pda = listener:GetCharacter():GetData("pdaequipped", false)
		listener:EmitSound( "stalkersound/pda/pda_news.wav", 55, 100, 0.2, CHAN_AUTO ) 

		return true
	end,
})

ix.chat.Register("eventpdainternal", {
	CanSay = function(self, speaker, text)
	speaker:EmitSound( "stalkersound/pda/pda_news.wav", 55, 100, 0.2, CHAN_AUTO ) 

		return true
		/*if pda then
			speaker:EmitSound( "stalkersound/pda/pda_news.wav", 55, 100, 0.2, CHAN_AUTO ) 
			return true
		else 
			return false
		end
		return false*/
	end,
	OnChatAdd = function(self, speaker, text)
		chat.AddText(Color(0,191,255), "[LPDA-SYSTEM] ", Color(0,241,255), ix.util.GetMaterial(icon), ": "..text)
	end,
	prefix = {},
	CanHear = function(self, speaker, listener)

		return true
		/*if pda then
			return true
		else
			return false
		end*/
	end,
})

if SERVER then	
	local function isClear(position)
		
		local currentdefs = {}
		local currentents = ents.FindInSphere( position, PLUGIN.saferadius )

		for i,j in pairs (currentents) do
			if j:IsPlayer() then
				return false
			end
		end
		return true
	end
	
	function PLUGIN:spawnEvent(eventpoint, spawn)
		if isClear(eventpoint[1]) then
			key = spawn.key
			if(!self.currentEvents[key]) then
				self.currentEvents[key] = {}
				self.currentEvents[key].data = {}
				self.currentEvents[key].eventpoint = eventpoint
				self.currentEvents[key].eventDef = spawn.key


				local tmpfunc = self.eventdefs[spawn.key].funcPrestart
				local data = tmpfunc(self.currentEvents[key])
				self.currentEvents[key] = data
				tmpfunc = self.eventdefs[spawn.key].funcStart
				data = tmpfunc(self.currentEvents[key])
				self.currentEvents[key] = data
			end
		end
	end

	function PLUGIN:setSpawnTime(time)
		self.spawntime = time
	end
	
	function PLUGIN:setPopulate(bool)
		self.populate = bool
	end

	-- Chame isso de dentro de funcPrestart/funcStart/funcUpdate de um
	-- eventdef sempre que criar um NPC, passando o "dat.eventpoint" pra
	-- ele entrar na contagem do PONTO certo (não uma contagem global).
	function PLUGIN:TrackEventNPC(ent, eventpoint)
		if not IsValid(ent) then return end
		if not eventpoint then return end

		self.spawnedNPCsByPoint[eventpoint] = self.spawnedNPCsByPoint[eventpoint] or {}
		self.spawnedNPCsByPoint[eventpoint][ent] = true

		-- Bloqueia esse ponto JÁ, assim que um NPC nasce nele -- mesma
		-- correção do eventcontroller (não espera o check periódico de
		-- até 5 min, que deixava o ponto "aberto" e permitia rodar outro
		-- evento nele antes do check seguinte perceber que já tinha NPC).
		local state = self:GetPointGateState(eventpoint)
		state.allowedTime = nil

		ent:CallOnRemove("ixEventControllerAdv_UntrackNPC", function()
			local list = self.spawnedNPCsByPoint[eventpoint]
			if list then list[ent] = nil end
		end)
	end

	function PLUGIN:GetTrackedNPCCountForPoint(eventpoint)
		local list = self.spawnedNPCsByPoint[eventpoint]
		if not list then return 0 end

		for npc in pairs(list) do
			if not IsValid(npc) then
				list[npc] = nil
			end
		end

		return table.Count(list)
	end

	function PLUGIN:GetPointGateState(eventpoint)
		local state = self.pointGateState[eventpoint]

		if not state then
			state = { allowedTime = nil }
			self.pointGateState[eventpoint] = state
		end

		return state
	end

	-- Roda a cada eventNPCCheckInterval segundos e atualiza o gate de
	-- CADA ponto individualmente (não é uma contagem global).
	function PLUGIN:UpdateEventSpawnGate()
		if CurTime() < self.nextEventCheck then return end
		self.nextEventCheck = CurTime() + self.eventNPCCheckInterval

		for _, eventpoint in pairs(self.eventpoints) do
			local state = self:GetPointGateState(eventpoint)
			local count = self:GetTrackedNPCCountForPoint(eventpoint)

			if count >= 1 then
				state.allowedTime = nil
			elseif not state.allowedTime then
				state.allowedTime = CurTime() + self.eventSpawnGraceTime
			end
		end
	end

	-- Escolhe um eventdef + eventpoint válidos pro mapa atual, igual à
	-- lógica que já existia duplicada no Think(). Usado tanto pelo spawn
	-- automático (respectGate = true, só pontos liberados) quanto pelo
	-- /eventadvforce (respectGate = false/nil, ignora o gate).
	function PLUGIN:GetRandomEligibleEvent(respectGate)
		for n = 1, 15 do
			local spawn = table.Random(self.eventdefs)

			if spawn.difficulty != self.MapToDifficultyMap[game.GetMap()] then continue end

			local eventpoint = self.eventpoints[table.Random(spawn.allowedPoints)]
			if not eventpoint then continue end

			if respectGate then
				local state = self:GetPointGateState(eventpoint)
				if not (state.allowedTime and CurTime() >= state.allowedTime) then continue end
			end

			return eventpoint, spawn
		end

		return nil
	end

	function PLUGIN:LoadData()
		self.eventpoints = self:GetData() or {}

		self.nextEventCheck = 0 -- força o primeiro check já no próximo Think

		-- Mesma correção do eventcontroller: preserva o rastreamento entre
		-- reloads ao invés de zerar incondicionalmente, senão o sistema
		-- "esquece" de NPCs ainda vivos e libera spawn em cima de spawn.
		self.spawnedNPCsByPoint = self.spawnedNPCsByPoint or {}
		self.pointGateState = self.pointGateState or {}
	end

	function PLUGIN:SaveData()
		self:SetData(self.eventpoints)
	end
	
	function PLUGIN:Think()

		if self.populate then
			for i = 1, self.populateAmount do
				local eventpoint, spawn = self:GetRandomEligibleEvent()

				if not eventpoint then
					print("No eventpoint found")
					continue
				end
				
				print("spawned forced event")
				self:spawnEvent(eventpoint,spawn)
			end
			
			self.populate = false
		end
		
		if (self.updatetime < CurTime() ) then
			for k,v in pairs( self.currentEvents) do
				local tmpfunc = self.eventdefs[v.eventDef].funcUpdate
				v = tmpfunc(v)
				self.currentEvents[k] = v

				tmpfunc = self.eventdefs[v.eventDef].funcShouldEnd
				if tmpfunc(v) then
					tmpfunc = self.eventdefs[v.eventDef].funcEnd
					v = tmpfunc(v)
					self.currentEvents[k] = nil
				end
			end

			self.updatetime = CurTime() + self.updaterate
		end

		self:UpdateEventSpawnGate()

		if self.spawntime > CurTime() then return end

		if #self.currentEvents >= ix.config.Get("maxActiveEvents", 5) then 
			self.spawntime = CurTime() + self.noSpaceRate
			return 
		end

		self.spawntime = CurTime() + (self.spawnratebase - (self.spawnrateplayer * #player.GetAll()))

		-- Só considera pontos cujo gate individual já está liberado (NPCs
		-- do evento anterior daquele ponto morreram + período de graça já
		-- passou). /eventadvforce ignora esse gate (ver o command abaixo).
		local eventpoint, spawn = self:GetRandomEligibleEvent(true)

		if not eventpoint then
			self.spawntime = CurTime() + self.noSpaceRate
			return
		end

		self:spawnEvent(eventpoint, spawn)

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

ix.command.Add("eventadvadd", {
	superAdminOnly = true,
	arguments = {
		ix.type.string,
		ix.type.string,
	},
	OnRun = function(self, client, name, internalname)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local name = name or "UNNAMED AREA"
		local internalname = internalname or "UNDEFINED_INTERNAL_NAME"

		PLUGIN.eventpoints[internalname] = {hitpos,name}
		client:Notify( "Event area named '"..name.."'("..internalname..") succesfully added" )
	end
})

ix.command.Add("eventadvremove", {
	superAdminOnly = true,
	OnRun = function(self, client, arguments)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local range = arguments[1] or 128
		local mt = 0
		for k, v in pairs( PLUGIN.eventpoints ) do
			local distance = v[1]:Distance( hitpos )
			if distance <= tonumber(range) then
				PLUGIN.eventpoints[k] = nil

				-- Limpa o rastreamento de NPCs/gate desse ponto pra não
				-- ficar lixo acumulando nas tabelas.
				PLUGIN.spawnedNPCsByPoint[v] = nil
				PLUGIN.pointGateState[v] = nil

				mt = mt + 1
			end
		end
		client:Notify( mt .. " event locations has been removed.")
	end
})

ix.command.Add("eventadvdisplay", {
	adminOnly = true,
	OnRun = function(self, client, arguments)
		if SERVER then
			netstream.Start(client, "nut_DisplaySpawnPoints", PLUGIN.eventpoints)
			client:Notify( "Displayed All Points for 10 secs." )
		end
	end
})

ix.command.Add("eventadvforce", {
	adminOnly = true,
	OnRun = function(self, client)
		if table.IsEmpty(PLUGIN.eventpoints or {}) then
			client:Notify("Nenhum ponto de evento avançado cadastrado ainda. Use /eventadvadd primeiro.")
			return
		end

		-- Spawna direto, ignorando o gate de "aguarda limpar" (que só
		-- vale pro spawn automático) -- mas os NPCs criados ainda entram
		-- na contagem rastreada normalmente.
		local eventpoint, spawn = PLUGIN:GetRandomEligibleEvent()

		if not eventpoint then
			client:Notify("Nenhum evento avançado compatível com esse mapa/dificuldade foi encontrado.")
			return
		end

		PLUGIN:spawnEvent(eventpoint, spawn)
		client:Notify("Evento avançado '" .. spawn.key .. "' forçado no ponto '" .. eventpoint[2] .. "'.")
	end
})

ix.command.Add("eventadvgatestatus", {
	adminOnly = true,
	OnRun = function(self, client)
		if table.IsEmpty(PLUGIN.eventpoints or {}) then
			client:Notify("Nenhum ponto de evento avançado cadastrado ainda.")
			return
		end

		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5

		local closest, closestDist
		for _, point in pairs(PLUGIN.eventpoints) do
			local dist = point[1]:Distance(hitpos)
			if not closestDist or dist < closestDist then
				closest = point
				closestDist = dist
			end
		end

		if not closest then
			client:Notify("Nenhum ponto encontrado.")
			return
		end

		local count = PLUGIN:GetTrackedNPCCountForPoint(closest)
		local state = PLUGIN:GetPointGateState(closest)
		local nextCheckIn = math.max(0, math.Round(PLUGIN.nextEventCheck - CurTime()))

		client:ChatPrint("[EventControllerAdv] Ponto mais próximo: '" .. closest[2] .. "' (a " .. math.Round(closestDist) .. " unidades)")
		client:ChatPrint("[EventControllerAdv] NPCs vivos nesse ponto: " .. count)
		client:ChatPrint("[EventControllerAdv] Próximo check de TODOS os pontos em: " .. nextCheckIn .. "s")

		if not state.allowedTime then
			client:ChatPrint("[EventControllerAdv] Spawn automático nesse ponto: BLOQUEADO (aguardando NPCs zerarem).")
		elseif CurTime() < state.allowedTime then
			local remaining = math.Round(state.allowedTime - CurTime())
			client:ChatPrint("[EventControllerAdv] Spawn automático nesse ponto: em período de graça, libera em " .. remaining .. "s.")
		else
			client:ChatPrint("[EventControllerAdv] Spawn automático nesse ponto: LIBERADO agora.")
		end
	end
})

ix.command.Add("eventadvpopulate", {
	adminOnly = true,
	OnRun = function(self, client, arguments)
		if table.IsEmpty(PLUGIN.eventpoints or {}) then
			client:Notify("Nenhum ponto de evento avançado cadastrado ainda. Use /eventadvadd primeiro.")
			return
		end

		PLUGIN:setPopulate(true)
		client:Notify("Populando com " .. PLUGIN.populateAmount .. " eventos avançados no próximo tick do servidor.")
	end
})