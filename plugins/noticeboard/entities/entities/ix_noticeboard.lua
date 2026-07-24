local PLUGIN = PLUGIN
AddCSLuaFile()

ENT.Type = "anim"
ENT.PrintName = "Notice Board"
ENT.Category = "Helix"
ENT.Spawnable = true
ENT.AdminOnly = true

if (SERVER) then
	function ENT:Initialize()
		self:SetModel("models/hunter/plates/plate1x2.mdl")
		self:SetSolid(SOLID_VPHYSICS)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetUseType(SIMPLE_USE)
		self:SetMaterial("models/props/CS_militia/roofbeams02")
		self:AddProps()

		local physObj = self:GetPhysicsObject()

		if (IsValid(physObj)) then
			physObj:EnableMotion(true)
			physObj:Wake()
		end
	end

    function ENT:AddProps()
        local Up = 2

        -- Offsets/angles are defined LOCAL to the board (as if the board had
        -- angle 0,0,0). We convert them to world space below using
        -- LocalToWorld/LocalToWorldAngles so they always end up flush with
        -- the board's actual surface, no matter how the board itself is
        -- rotated/placed in the map.
        local propData = {
            {model = "models/lostsignalproject/items/quest/notes_letter_1.mdl", offset = Vector(10, 30, Up), angle = Angle(0, -10, 0)},
            {model = "models/lostsignalproject/items/quest/notes_paper_2.mdl", offset = Vector(5, -10, Up), angle = Angle(0, 5, 0)},
            {model = "models/lostsignalproject/items/quest/notes_paper_1.mdl", offset = Vector(-10, -30, Up), angle = Angle(0, -5, 0)},
            {model = "models/lostsignalproject/items/quest/notes_photo.mdl", offset = Vector(-10, 20, Up), angle = Angle(0, 7, 0)},
        }

        self.props = self.props or {}

        for _, data in ipairs(propData) do
            local note = ents.Create("prop_dynamic")
            note:SetModel(data.model)
            note:SetPos(self:LocalToWorld(data.offset))
            note:SetAngles(self:LocalToWorldAngles(data.angle))
            note:Spawn()
            note:SetCollisionGroup(COLLISION_GROUP_WORLD)
            note:SetParent(self)
            -- Lock the offset relative to the board now that it's parented,
            -- so it stays put even if the board moves later.
            note:SetLocalPos(data.offset)
            note:SetLocalAngles(data.angle)
            note:DeleteOnRemove(self)

            self.props[#self.props + 1] = note
        end
    end

	function ENT:Use(activator)
		PLUGIN:OpenNoticeBoard(activator)
	end

	function ENT:OnRemove()

	end
else
    ENT.PopulateEntityInfo = true

    function ENT:OnPopulateEntityInfo(container)
        local name = container:AddRow("name")
        name:SetImportant()
        name:SetText("Noticeboard")
        name:SizeToContents()
        local descriptionText = self:GetNetVar("Description", "An old wooden noticeboard used to display notices. (Press E to interact)")

        if descriptionText ~= nil then
            local description = container:AddRow("Description")
            description:SetText(descriptionText)
            description:SizeToContents()
        end
    end
end