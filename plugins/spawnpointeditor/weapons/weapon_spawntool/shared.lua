SWEP.PrintName = "Spawn Tool"
SWEP.Author = "you"
SWEP.Instructions = "Esquerdo: adicionar ponto | Direito: remover pontos próximos | " ..
	"Meio (mouse3): trocar modo | R: abrir/fechar configurações"
SWEP.Purpose = "Ferramenta gráfica para posicionar pontos de spawn (caixas, stashes, " ..
	"radiação, anomalias, eventos, containers cíclicos) sem precisar digitar comandos."

SWEP.Category = "Admin"
SWEP.Spawnable = false
SWEP.AdminOnly = true -- checagem real de permissão continua sendo feita nos comandos ix

SWEP.ViewModel = "models/weapons/v_toolgun.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true
SWEP.HoldType = "pistol"

SWEP.Slot = 5
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

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
-- O modo ativo decide qual comando ix.command.Send o clique esquerdo/direito dispara.
SWEP.ModeOrder = { "box", "stash", "radiation", "anomaly", "event", "container" }

SWEP.ModeLabels = {
	box = "Caixas",
	stash = "Stash Escondido",
	radiation = "Radiação",
	anomaly = "Anomalias",
	event = "Eventos",
	container = "Containers Cíclicos",
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

-- IN_ATTACK3 = clique do meio (mouse3), usado para trocar de modo rapidamente
-- sem precisar abrir o painel.
function SWEP:Think()
	if SERVER then return end

	local owner = self:GetOwner()
	if not IsValid(owner) then return end

	if owner:KeyPressed(IN_ATTACK3) then
		self:CycleMode()
	end
end
