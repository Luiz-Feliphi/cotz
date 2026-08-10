AddCSLuaFile()

DEFINE_BASECLASS("base_anim")

ENT.Type = "anim"
ENT.PrintName = "Campfire"
ENT.Category = "Helix"
ENT.Spawnable = true

ENT.Model = "models/z-o-m-b-i-e/st/fireplace/st_fireplace_01_1.mdl"

-- Modelo de base (suporte) que fica embaixo do modelo
-- principal da fogueira.
ENT.BaseModel = "models/z-o-m-b-i-e/st/fireplace/st_fireplace_01_2.mdl"

-- Offset do modelo de base em relação à campfire.
-- Ajuste testando in-game se ele não encaixar perfeitamente.
ENT.BaseModelOffset = Vector(0, 0, 0)

-- =========================================================
-- CONFIGURAÇÕES
-- =========================================================

-- Tamanho do fogo do env_fire.
ENT.FireSize = 32

-- Raio do dano manual.
--
-- OBS: Estava em 75 (depois 40), ainda grande demais.
-- O hull de um player tem ~32 unidades de diâmetro, então
-- um raio de 20 já exige estar praticamente encostado
-- na chama pra tomar dano.
ENT.FireRadius = 20

-- Dano causado.
ENT.FireDamage = 5

-- Intervalo entre danos.
ENT.DamageInterval = 1

-- Offset usado APENAS como fallback, caso o modelo não
-- tenha um attachment chamado "fire". Ajuste esses valores
-- testando in-game até a chama ficar visualmente encaixada
-- na lenha do modelo.
ENT.FireOffset = Vector(0, 0, 40)

-- Cor/intensidade da luz emitida pela fogueira.
--
-- Copiado do "Color and Brightness" do light no Hammer:
-- "225 95 0 600" (R G B Intensidade). A intensidade 600 é
-- bem mais forte que o padrão do Hammer (~200), por isso
-- o Brightness aqui ficou mais alto que o normal do GMod.
ENT.LightColor = Color(225, 95, 0)
ENT.LightBrightness = 6
ENT.LightSize = 256

-- Padrão de light style "Gentle Pulse 1" do Source Engine.
-- Cada letra de 'a' (0% de brilho) a 'z' (~208% de brilho)
-- representa um nível; o engine interpola suavemente entre
-- uma letra e a próxima, atualizando 10x por segundo.
ENT.LightPattern = "m"

-- Configuração do env_steam (efeito "Heat Wave" visto no
-- Hammer, dá aquele efeito de calor distorcendo o ar).
ENT.SteamSpreadSpeed = 15
ENT.SteamSpeed = 50
ENT.SteamStartSize = 20
ENT.SteamEndSize = 20
ENT.SteamRate = 26
ENT.SteamJetLength = 80
ENT.SteamTranslucency = 255
ENT.SteamRollSpeed = 8

-- Configuração do ambient_generic (som de fogo em loop).
ENT.SoundName = "ambient/fire/fire_med_loop1.wav"
ENT.SoundRadius = 1250
ENT.SoundVolume = 10
ENT.SoundPitch = 100

-- =========================================================
-- COMPARTILHADO
-- =========================================================

-- Retorna a posição correta onde a chama (e a luz) devem
-- ficar. Primeiro tenta usar um attachment "fire" do
-- modelo; se não existir, usa o ENT.FireOffset como
-- fallback.
function ENT:GetFirePosition()

	local attachmentId = self:LookupAttachment("fire")

	if attachmentId and attachmentId > 0 then

		local attachment = self:GetAttachment(attachmentId)

		if attachment then
			return attachment.Pos
		end

	end

	return self:GetPos() + self.FireOffset

end

-- =========================================================
-- SERVIDOR
-- =========================================================

if SERVER then

	-- =====================================================
	-- INITIALIZE
	-- =====================================================

	function ENT:Initialize()

		self:SetModel(self.Model)

		self:SetMoveType(MOVETYPE_NONE)

		-- OBS: SOLID_VPHYSICS usava a malha física do
		-- modelo (que é côncava, tipo uma "tigela"), e o
		-- player ficava preso dentro dela ao pisar em cima.
		-- SOLID_BBOX usa a caixa simples definida em
		-- SetCollisionBounds abaixo, evitando esse problema.
		self:SetSolid(SOLID_BBOX)
		self:SetUseType(SIMPLE_USE)

		-- OBS: Os vetores de min/max estavam invertidos
		-- (o "min" tinha valores maiores que o "max"), o que
		-- é inválido para o engine. Corrigido abaixo.
		self:SetCollisionBounds(
			Vector(-15, -15, 1),
			Vector(15, 15, 15)
		)

		-- Estado da fogueira.
		self.IsOn = false
		self:SetNWBool("IsOn", false)

		-- Entidade env_fire.
		--
		-- IMPORTANTE:
		-- NÃO usamos "self.Fire", pois Fire é uma
		-- função nativa das entidades do GMod.
		self.FireEntity = nil

		-- Entidade env_steam (efeito de calor).
		self.SteamEntity = nil

		-- Entidade ambient_generic (som do fogo).
		self.SoundEntity = nil

		-- Entidade do modelo de base.
		self.BaseModelEntity = nil

		self.NextDamage = 0

		-- Cria o modelo de base embaixo da fogueira.
		self:CreateBaseModel()

	end


	-- =====================================================
	-- CRIAR MODELO DE BASE
	-- =====================================================

	function ENT:CreateBaseModel()

		-- Se já existe, não cria outro.
		if IsValid(self.BaseModelEntity) then
			return self.BaseModelEntity
		end

		if not self.BaseModel or self.BaseModel == "" then
			return nil
		end

		local baseEntity = ents.Create("prop_dynamic")

		if not IsValid(baseEntity) then

			ErrorNoHalt(
				"[Campfire] Não foi possível criar o modelo de base.\n"
			)

			return nil

		end

		self.BaseModelEntity = baseEntity

		baseEntity:SetModel(self.BaseModel)

		baseEntity:SetPos(
			self:GetPos() + self.BaseModelOffset
		)

		baseEntity:SetAngles(
			self:GetAngles()
		)

		-- Puramente decorativo, sem colisão própria
		-- (a campfire já tem a colisão principal).
		baseEntity:SetSolid(SOLID_NONE)
		baseEntity:SetMoveType(MOVETYPE_NONE)
		baseEntity:SetCollisionGroup(COLLISION_GROUP_WORLD)

		baseEntity:Spawn()
		baseEntity:Activate()

		baseEntity:SetParent(self)

		return baseEntity

	end


	-- =====================================================
	-- CRIAR ENV_FIRE
	-- =====================================================

	function ENT:CreateFire()

		-- Se já existe um fogo, não cria outro.
		if IsValid(self.FireEntity) then
			return self.FireEntity
		end

		local fireEntity = ents.Create("env_fire")

		if not IsValid(fireEntity) then

			ErrorNoHalt(
				"[Campfire] Não foi possível criar env_fire.\n"
			)

			return nil

		end

		-- Guarda a entidade.
		self.FireEntity = fireEntity


		-- =================================================
		-- POSIÇÃO
		-- =================================================

		fireEntity:SetPos(
			self:GetFirePosition()
		)

		fireEntity:SetAngles(
			self:GetAngles()
		)


		-- =================================================
		-- CONFIGURAÇÃO DO ENV_FIRE
		-- =================================================

		-- Tamanho da chama.
		fireEntity:SetKeyValue(
			"firesize",
			tostring(self.FireSize)
		)

		-- Velocidade com que o fogo chega ao tamanho máximo.
		fireEntity:SetKeyValue(
			"fireattack",
			"1"
		)

		-- Multiplicador de dano do env_fire.
		--
		-- Colocamos 0 porque vamos controlar o dano
		-- manualmente abaixo.
		fireEntity:SetKeyValue(
			"damagescale",
			"0"
		)

		-- Fogo natural.
		fireEntity:SetKeyValue(
			"firetype",
			"0"
		)

		-- Infinite Duration.
		fireEntity:SetKeyValue(
			"spawnflags",
			"32"
		)


		-- =================================================
		-- SPAWN
		-- =================================================

		fireEntity:Spawn()
		fireEntity:Activate()


		-- =================================================
		-- COMEÇA APAGADO
		-- =================================================

		fireEntity:Fire(
			"Extinguish",
			"",
			0
		)


		-- =================================================
		-- PARENT
		-- =================================================

		fireEntity:SetParent(self)


		return fireEntity

	end


	-- =====================================================
	-- CRIAR ENV_STEAM (efeito de calor)
	-- =====================================================

	function ENT:CreateSteam()

		if IsValid(self.SteamEntity) then
			return self.SteamEntity
		end

		local steamEntity = ents.Create("env_steam")

		if not IsValid(steamEntity) then

			ErrorNoHalt(
				"[Campfire] Não foi possível criar env_steam.\n"
			)

			return nil

		end

		self.SteamEntity = steamEntity


		-- =================================================
		-- POSIÇÃO
		-- =================================================
		--
		-- No Hammer o Pitch Yaw Roll era -90 0 0, ou seja,
		-- o efeito sai apontando pra cima independente da
		-- rotação da fogueira no mapa.

		steamEntity:SetPos(
			self:GetFirePosition()
		)

		steamEntity:SetAngles(
			Angle(-90, 0, 0)
		)


		-- =================================================
		-- CONFIGURAÇÃO (valores copiados do Hammer)
		-- =================================================

		-- Particle Type: Heat Wave.
		steamEntity:SetKeyValue(
			"type",
			"1"
		)

		steamEntity:SetKeyValue(
			"SpreadSpeed",
			tostring(self.SteamSpreadSpeed)
		)

		steamEntity:SetKeyValue(
			"Speed",
			tostring(self.SteamSpeed)
		)

		steamEntity:SetKeyValue(
			"StartSize",
			tostring(self.SteamStartSize)
		)

		steamEntity:SetKeyValue(
			"EndSize",
			tostring(self.SteamEndSize)
		)

		steamEntity:SetKeyValue(
			"Rate",
			tostring(self.SteamRate)
		)

		steamEntity:SetKeyValue(
			"JetLength",
			tostring(self.SteamJetLength)
		)

		steamEntity:SetKeyValue(
			"renderamt",
			tostring(self.SteamTranslucency)
		)

		steamEntity:SetKeyValue(
			"rollspeed",
			tostring(self.SteamRollSpeed)
		)

		steamEntity:SetKeyValue(
			"rendercolor",
			"0 0 0"
		)


		-- =================================================
		-- SPAWN
		-- =================================================

		steamEntity:Spawn()
		steamEntity:Activate()


		-- =================================================
		-- COMEÇA DESLIGADO
		-- =================================================

		steamEntity:Fire(
			"TurnOff",
			"",
			0
		)


		-- =================================================
		-- PARENT
		-- =================================================

		steamEntity:SetParent(self)


		return steamEntity

	end


	-- =====================================================
	-- CRIAR AMBIENT_GENERIC (som do fogo)
	-- =====================================================

	function ENT:CreateSound()

		if IsValid(self.SoundEntity) then
			return self.SoundEntity
		end

		local soundEntity = ents.Create("ambient_generic")

		if not IsValid(soundEntity) then

			ErrorNoHalt(
				"[Campfire] Não foi possível criar ambient_generic.\n"
			)

			return nil

		end

		self.SoundEntity = soundEntity

		soundEntity:SetPos(
			self:GetFirePosition()
		)

		-- Nome do som.
		soundEntity:SetKeyValue(
			"message",
			self.SoundName
		)

		-- No FGD do ambient_generic, o campo "Volume"
		-- exibido no Hammer usa a keyvalue "health" por
		-- questões legadas do engine.
		soundEntity:SetKeyValue(
			"health",
			tostring(self.SoundVolume)
		)

		soundEntity:SetKeyValue(
			"pitch",
			tostring(self.SoundPitch)
		)

		soundEntity:SetKeyValue(
			"radius",
			tostring(self.SoundRadius)
		)

		soundEntity:Spawn()
		soundEntity:Activate()

		-- Começa em silêncio.
		soundEntity:Fire(
			"StopSound",
			"",
			0
		)

		soundEntity:SetParent(self)

		return soundEntity

	end


	-- =====================================================
	-- LIGAR
	-- =====================================================

	function ENT:TurnOn()

		-- Cria o env_fire se ainda não existir.
		local fireEntity = self:CreateFire()

		if not IsValid(fireEntity) then
			return
		end

		self.IsOn = true
		self:SetNWBool("IsOn", true)

		-- Liga o fogo.
		fireEntity:Fire(
			"StartFire",
			"",
			0
		)

		-- Liga o efeito de calor (env_steam).
		local steamEntity = self:CreateSteam()

		if IsValid(steamEntity) then

			steamEntity:Fire(
				"TurnOn",
				"",
				0
			)

		end

		-- Liga o som do fogo (ambient_generic).
		local soundEntity = self:CreateSound()

		if IsValid(soundEntity) then

			soundEntity:Fire(
				"PlaySound",
				"",
				0
			)

		end

		-- Dano imediatamente disponível.
		self.NextDamage = CurTime()

	end


	-- =====================================================
	-- DESLIGAR
	-- =====================================================

	function ENT:TurnOff()

		self.IsOn = false
		self:SetNWBool("IsOn", false)

		if IsValid(self.FireEntity) then

			-- Apaga o fogo.
			self.FireEntity:Fire(
				"Extinguish",
				"",
				0
			)

		end

		if IsValid(self.SteamEntity) then

			-- Desliga o efeito de calor.
			self.SteamEntity:Fire(
				"TurnOff",
				"",
				0
			)

		end

		if IsValid(self.SoundEntity) then

			-- Para o som.
			self.SoundEntity:Fire(
				"StopSound",
				"",
				0
			)

		end

	end


	-- =====================================================
	-- USE / E
	-- =====================================================

	function ENT:Use(activator, caller)

		if not IsValid(activator) then
			return
		end

		if not activator:IsPlayer() then
			return
		end

		-- Alterna entre ligado/desligado.
		if self.IsOn then
			self:TurnOff()
		else
			self:TurnOn()
		end

	end


	-- =====================================================
	-- THINK
	-- =====================================================

	function ENT:Think()

		-- Se estiver desligada, não causa dano.
		if not self.IsOn then

			self:NextThink(
				CurTime() + 0.1
			)

			return true

		end


		-- Verifica o intervalo do dano.
		if CurTime() >= self.NextDamage then

			self:DamageNearbyPlayers()

			self.NextDamage =
				CurTime() + self.DamageInterval

		end


		self:NextThink(
			CurTime() + 0.1
		)

		return true

	end


	-- =====================================================
	-- DANO
	-- =====================================================

	function ENT:DamageNearbyPlayers()

		-- Usa a posição real da chama (não a base do
		-- modelo) para calcular quem está perto o
		-- suficiente para se queimar.
		local position = self:GetFirePosition()

		for _, client in ipairs(
			ents.FindInSphere(
				position,
				self.FireRadius
			)
		) do

			if not IsValid(client) then
				continue
			end

			if not client:IsPlayer() then
				continue
			end

			if not client:Alive() then
				continue
			end

			-- Verifica se o jogador possui um personagem ativo no Helix
			local character = client:GetCharacter()

			if not character then
				continue
			end


			-- =============================================
			-- DANO E EFEITOS
			-- =============================================

            -- Acende o jogador por 1 segundo (ajuda o Helix e a engine
            -- a reconhecer o estado de queimadura)
            client:Ignite(1)

            -- Estrutura de dano padrão do Source Engine
			local damage = DamageInfo()

			damage:SetDamage(
				self.FireDamage
			)

			damage:SetDamageType(
				DMG_BURN
			)

			damage:SetAttacker(
				self
			)

			damage:SetInflictor(
				self
			)

			damage:SetDamagePosition(
				client:GetPos()
			)

            -- Se o Helix tiver o método customizado de dano no personagem, usa ele.
            -- Caso contrário, usa o sistema de TakeDamageInfo padrão.
            if character.TakeDamage then
                character:TakeDamage(self.FireDamage, DMG_BURN, self)
            else
			client:TakeDamageInfo(
				damage
			)
            end

        end

    end


	-- =====================================================
	-- REMOVER
	-- =====================================================

	function ENT:OnRemove()

		self.IsOn = false

		-- Remove o env_fire junto com a fogueira.
		if IsValid(self.FireEntity) then

			self.FireEntity:Remove()

			self.FireEntity = nil

		end

		-- Remove o env_steam junto com a fogueira.
		if IsValid(self.SteamEntity) then

			self.SteamEntity:Remove()

			self.SteamEntity = nil

		end

		-- Remove o ambient_generic junto com a fogueira.
		if IsValid(self.SoundEntity) then

			self.SoundEntity:Remove()

			self.SoundEntity = nil

		end

		-- Remove o modelo de base junto com a fogueira.
		if IsValid(self.BaseModelEntity) then

			self.BaseModelEntity:Remove()

			self.BaseModelEntity = nil

		end

	end

end

-- =========================================================
-- CLIENTE
-- =========================================================
--
-- env_fire não emite luz dinâmica sozinho, então criamos
-- uma DynamicLight manualmente enquanto a fogueira estiver
-- ligada, seguindo a posição real da chama.

if CLIENT then

	function ENT:Think()

		-- IMPORTANTE: sem isso, o Think do cliente não roda
		-- de forma confiável todo frame, fazendo o DynamicLight
		-- expirar (DieTime) e "piscar" ligado/desligado em vez
		-- de pulsar suavemente.
		self:SetNextClientThink(CurTime())

		if not self:GetNWBool("IsOn", false) then
			return true
		end

		local dlight = DynamicLight(self:EntIndex())

		if not dlight then
			return true
		end

		local pos = self:GetFirePosition()


		-- =================================================
		-- GENTLE PULSE (light style real do Source)
		-- =================================================
		--
		-- O style roda a 10 "frames" por segundo, interpolando
		-- linearmente entre a letra atual e a próxima do
		-- padrão, exatamente como o engine faz com light
		-- styles customizados no Hammer.

		local pattern = self.LightPattern
		local patternLength = #pattern

		local rawIndex = CurTime() * 10

		local index1 = math.floor(rawIndex) % patternLength
		local index2 = (index1 + 1) % patternLength

		local frac = rawIndex - math.floor(rawIndex)

		local level1 = string.byte(pattern, index1 + 1) - string.byte("a")
		local level2 = string.byte(pattern, index2 + 1) - string.byte("a")

		-- 'a' = 0, 'z' = 25 (nível mais alto que aparece no
		-- padrão). Normalizamos pelo 'z' em vez do 'm' (que
		-- seria o "100% padrão" do Source) porque usar 'm'
		-- como base deixava o pico passando de 2x o
		-- LightBrightness configurado e estourando a luz.
		-- Assim o pico bate exatamente no valor configurado.
		local level = Lerp(frac, level1, level2)
		local fraction = level / 25

		dlight.pos = pos
		dlight.r = 225 
		dlight.g = 95
		dlight.b = 0
		dlight.Brightness = self.LightBrightness
		dlight.Size = self.LightSize
		dlight.Decay = 1000
		dlight.DieTime = CurTime() + 0.1
		dlight.NoWorld = false
		dlight.NoModel = false
        dlight.Style = 6

		return true

	end

end