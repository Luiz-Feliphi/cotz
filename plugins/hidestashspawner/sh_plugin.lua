local PLUGIN = PLUGIN
PLUGIN.name = "Hidden Stash System Spawning"
PLUGIN.author = "verne"
PLUGIN.desc = "Simple autospawning hidestash system."
PLUGIN.stashspawnpoints = PLUGIN.stashspawnpoints or {}

ix.util.Include("sh_definitions.lua")

-- ---------------------------------------------------------------------
-- Spawn automático de caixinha de madeira nos pontos de stash escondido.
-- ---------------------------------------------------------------------
-- Mesmo padrão do boxspawner: de tempos em tempos, olha os pontos
-- marcados com /stashspawneradd e, se a área estiver livre (sem jogador
-- perto, sem outra caixa/item já ali), spawna uma "ix_wood_entbox" com o
-- CustomSpawngroup = categoria que você digitou no /stashspawneradd —
-- isso reaproveita o loot automático que a própria ix_wood_entbox já usa
-- (ix.util.GetRandomItemFromPool(self.CustomSpawngroup or "ix_entbox_drops")).
-- Isso é INDEPENDENTE do sistema de "Lost Note" do hidestash.lua — os
-- dois podem coexistir sem conflito, já que usam pontos/tabelas diferentes.
PLUGIN.boxSpawnRate = 300
PLUGIN.boxSafeRadius = 512
PLUGIN.boxClass = "ix_wood_entbox"

ix.config.Add("hideStashBoxThreshold", 30, "Quantas caixas de stash escondido o sistema mantém no mapa ao mesmo tempo.", nil, {
	data = {min = 0, max = 200},
	category = "Spawning"
})

if SERVER then
	local boxSpawnTime = 1

	local function isAreaClear(position, radius)
		for _, ent in pairs(ents.FindInSphere(position, radius)) do
			if (ent:IsPlayer()) then
				return false
			end
		end

		for _, ent in pairs(ents.FindInSphere(position, 20)) do
			if (string.find(ent:GetClass(), "entbox") or ent:GetClass() == "ix_item") then
				return false
			end
		end

		return true
	end

	function PLUGIN:GetNumStashBoxes()
		local count = 0

		for _, ent in ipairs(ents.FindByClass(self.boxClass)) do
			if (IsValid(ent) and ent.ixIsHideStashBox) then
				count = count + 1
			end
		end

		return count
	end

	function PLUGIN:SpawnStashBoxes()
		local map = game.GetMap()
		local points = self.stashspawnpoints and self.stashspawnpoints[map]

		if (not points) then return end

		local numBoxes = self:GetNumStashBoxes()
		local maxBoxes = ix.config.Get("hideStashBoxThreshold", 30)

		for _, point in RandomPairs(points) do
			if (numBoxes >= maxBoxes) then return end
			if (not point) then continue end

			local pos = point[1]
			local category = point[2]

			if (isAreaClear(pos, self.boxSafeRadius)) then
				local box = ents.Create(self.boxClass)
				box.CustomSpawngroup = category
				box.ixIsHideStashBox = true
				box:SetPos(pos)
				box:Spawn()
				box:PhysWake()

				numBoxes = numBoxes + 1
			end
		end
	end

	function PLUGIN:Think()
		if (boxSpawnTime > CurTime()) then return end
		boxSpawnTime = CurTime() + self.boxSpawnRate

		if (self:GetNumStashBoxes() >= ix.config.Get("hideStashBoxThreshold", 30)) then return end

		self:SpawnStashBoxes()
	end
end

if SERVER then
	local spawntime = 1

	function PLUGIN:ItemShouldSave(entity)
		return (!entity.generated)
	end

	function PLUGIN:LoadData()
		self.stashspawnpoints = self:GetData() or {}

		self.stashspawnpoints[game.GetMap()] = self.stashspawnpoints[game.GetMap()] or {}
	end

	function PLUGIN:SaveData()
		self:SetData(self.stashspawnpoints)
	end

	--[[
	function PLUGIN:GetPointFromCategory(category)
		if(!isstring(category)) then return end
		self.stashspawnpoints[category] = self.stashspawnpoints[category] or {}
		return table.Random(self.stashspawnpoints[category])
	end
	]]--

	function PLUGIN:GetPoint(map)
		map = map or game.GetMap()
		self.stashspawnpoints = self.stashspawnpoints or {}
		return table.Random(self.stashspawnpoints[map])
	end

else

	netstream.Hook("nut_DisplayStashSpawnPoints", function(data)
		for i=1, #data do
			local emitter = ParticleEmitter( data[i] )
			local smoke = emitter:Add( "sprites/glow04_noz", data[i] )
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

	netstream.Hook("nut_DisplayStashSpawnPointsSingle", function(data)
		local stashmaterial = Material("vgui/icons/stash.png", "smooth noclamp")
		local emitter = ParticleEmitter( data )
		local smoke = emitter:Add( stashmaterial, data )
		smoke:SetVelocity( Vector( 0, 0, 1 ) )
		smoke:SetDieTime(10)
		smoke:SetStartAlpha(255)
		smoke:SetEndAlpha(255)
		smoke:SetStartSize(2)
		smoke:SetEndSize(2)
		smoke:SetColor(255,255,255)
		smoke:SetAirResistance(300)

	end)
end
--[[
ix.command.Add("stashspawntest", {
	adminOnly = true,
	arguments = {
		ix.type.text,
	},
	OnRun = function(self, client, category)
		local stashcontent = "CONTENT: "
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local mt = 0

		local loot = table.Random(PLUGIN.StashItems[category])
		local spawnpoint = table.Random(PLUGIN.stashspawnpoints)
		ix.plugin.list["hidestash"]:SpawnStash(spawnpoint, { loot[1], loot[2] })

		for i = 1, #loot[1] do
			stashcontent = stashcontent..", "..loot[i][1]
			client:Notify( "You hid ".. loot[i][1] )
		end

		ix.log.Add(client, "command", "created a stash at x:"..spawnpoint.x.." y:"..spawnpoint.y.." z:"..spawnpoint.z.." with "..stashcontent)
		mt = mt + 1
		
		if mt > 0 then
			--ix.chat.Send(client, "iteminternal", "hides something away.", false)
		end
	end
}) ]]--

ix.command.Add("stashspawneradd", {
	superAdminOnly = true,
	arguments = {
		ix.type.text,
	},
	OnRun = function(self, client, text)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local text = text
        PLUGIN.stashspawnpoints = PLUGIN.stashspawnpoints or {}
        PLUGIN.stashspawnpoints[game.GetMap()] = PLUGIN.stashspawnpoints[game.GetMap()] or {}
		table.insert( PLUGIN.stashspawnpoints[game.GetMap()], {hitpos, text} )
		client:Notify( "You added a hidden stash spawner." )
	end
})

ix.command.Add("stashspawnerremove", {
	superAdminOnly = true,
	arguments = {
		ix.type.number,
	},
	OnRun = function(self, client, radius)
		local trace = client:GetEyeTraceNoCursor()
		local hitpos = trace.HitPos + trace.HitNormal*5
		local range = radius or 128
		local mt = 0
		for k, v in pairs( PLUGIN.stashspawnpoints[game.GetMap()] ) do
			local distance = v[1]:Distance( hitpos )
			if distance <= tonumber(range) then
				PLUGIN.stashspawnpoints[game.GetMap()][k] = nil
				mt = mt + 1
			end
		end
		client:Notify( "You have removed "..mt.." stash spawners." )
	end
})

ix.command.Add("stashspawnerdisplay", {
	adminOnly = true,
	OnRun = function(self, client, arguments)
		if SERVER then
			local data = {}

			for k, v in pairs(PLUGIN.stashspawnpoints[game.GetMap()]) do
				table.insert(data, v[1])
			end	

			netstream.Start(client, "nut_DisplayStashSpawnPoints", data)
			client:Notify( "Displayed all stash spawners for 10 secs." )
		end
	end
})

ix.command.Add("stashspawnerforce", {
	adminOnly = true,
	OnRun = function(self, client)
		if SERVER then
			PLUGIN:SpawnStashBoxes()
			client:Notify("Spawn de caixas de stash forçado.")
		end
	end
})
