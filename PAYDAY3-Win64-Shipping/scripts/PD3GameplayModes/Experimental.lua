local Experimental         = {}
local uevrUtils            = require("libs/uevr_utils")
local animation            = require('libs/animation')
local controllers          = require('libs/controllers')
local attachments          = require("libs/attachments")
local hands                = require('libs/hands')
local ik                   = require('libs/ik')
local gestures             = require('libs/gestures')
local PD3UserConfig        = require("libs/config/PD3UserConfig")
local WeaponAnimController = require("libs/WeaponAnimationController")
local Actions              = require("libs/Actions")
local mathLib              = require("libs/core/math_lib")
local handsAnimation       = require("libs/hands_animation")
local input                = require("libs/input")

-- This module will present seperate hand models, Manual reloads, manual bolting, and so on


-- Crash Counter: ~199
-- TODO:
-- Improve gestures by combining gestures and making it return what is the actual call
-- Improve code flow, For gestures experimental should handle State detection and Actions handles execution
-- With an exempt for impossible/inconvenient stuff
-- SFX/Sound Manager to play sounds on reload, etc etc
--  need to simultaneously set and cache firing animation
-- completely remove animation.findbonefname
-- Weight system?
-- Notes:

-- the normal weapon swap is very delayed for VR purposes
-- Predicting the user's input is a no go as  side trigger is 0-1
-- I've tried editing the abilities and their tags, nope
--I decided to store the meshes in a cache and hope the player would spend enough time before shooting
-- such as bringing his gun back into his view

-- this uses a state system for hands,weapons,magazines and disables abilities like firing a weapon etc when not equipped

-- Disabling the gun abilities uses C++ code and parsing a Tarray table then editing its a few properties to something out of bounds
-- in the case of activating an ability, when it has already been de-activated
-- the C++ will momentarily restore its original properties to enable the ability, stores it aswell for reactivation later

-- Dominant hand is handled through attachments.registerOnGripUpdateCallback(function()
-- whilst the non dominant is handled through regular attachments functions
-- this was due to the fact that
-- the hand sometimes needed to be attached and not attach to, I could use a variable now that I think about it
-- to unify methods honestly, better IMO

-- for future multiplayer support:
-- Check if P2P actually replicates stuff
--  Potential Solution 1: Use the existing player model
-- Need to use the actual model, no creation at all so no copied meshes, all  needs to be re used and so on
-- Setleaderposecomponent to stop the model from being animated
-- Issues are that the bone locations are enforced somehow, C++ hooks to prevent them?
--  Potential Solution 2: Use UE4SS and unused "RPC" or "ServerRPC" functions to send data from UEVR to UE4SS?

-- For future throwable support keep in mind
--	ASBZThrowable.Multicast_SetThrowDirection(const struct FVector_NetQuantizeNormal& ThrowDirection);
--	ASBZThrowable.Multicast_SetThrowState(ESBZThrowableState NewThrowState);

-- All created meshes MUST not be parented to the persistent level and deleted before a level restart/exit
-- to avoid a weird bug where the game starts tweaking out after a level restart


--Revamp todo: Gestures.GetmultipleGestures
-- Currently this handles alot of other things alongside hands so bare with me for a bit

Experimental.VRState          = {
    PrimaryHandIndex = PD3UserConfig.Settings["PreferredHand"],
    SecondaryHandIndex = Handed.Right == PD3UserConfig.Settings["PreferredHand"] and Handed.Left or Handed.Right,
    IsMasked = false, -- PD3 one fires too early, mine is after equip animation
    IsLeftHanded = Handed.Right == PD3UserConfig.Settings["PreferredHand"] and false or true,
    BaseModel = nil,
    SuitModel = nil,
    HandModel = nil,
    HandStates = {
        RightHandState = {
            CurrentAction = "",
            CurrentItem = nil,
            IsAttached = false,
        },

        LeftHandState = {
            CurrentAction = "",
            CurrentItem = nil,
            IsAttached = false,
        },
    },
    HolsterSlots = {
        Secondary = nil, -- Secondary
        Pouch     = nil, -- Mags
        Phone     = nil,
        Throwable = nil
    }
}

local DefaultMagazineState    = {
    State = "",                      -- Gripped,Grabbed (difference is is it attached to the weapons or not),Dropped
    Model = nil,                     -- If present
    LastMagazineGrabbedCapacity = 0, -- last recorded capacity after it is grabbed from the weapon
    LastGrabbedMag = 0,              -- to cooldown when grabbing it so it doesnt reinsert immediately, could substitute for intent checking if hand is going up
}

local defaultWeaponState      = {
    Model = nil,
    FakeModel = nil,       -- Used for any needed animations like moving a charging handle etc
    Family = nil,          -- AR, Pistol, etc
    Config = nil,          -- takes from WeaponFamiliesConfig
    DefaultMaterials = {}, -- On script reset these are used to revert previously overriden materials
    Parts = {},            -- Magazine,extra stuff attached, etc,
    Name = "",
    Slot = "",             -- Primary and secondary
    State = "",            -- Firing,ReloadingMag,ReloadingBolt, so on and so forth, Jammed?
    MagazineState = DefaultMagazineState
}
local defaultThrowableState   = {
    Model = nil,
    Config = nil, -- takes from ThrowableFamiliesConfig
    Lever = nil,
    Actor = nil,  -- Needed for multicast functions to set throw direction and activate
    -- Parts = {},            -- Magazine,extra stuff attached, etc,
    Name = "",
    State = "", -- Armed, gripped, and so on
}
-- Most weapons are using StatIK_LeftHand/RightHand, fallback incase there is not are secondaryGripBones
-- Pistols don't so
-- TBD: Add tables to each config of potential gripbones and iterate to see which one is valid
local WeaponFamiliesConfig    = {
    ["Weapon.Family.AssaultRifle"] = {
        CyclingMode         = { ["ChargingHandle"] = true },
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "StatIK_LeftHand",
        --  FallbackBone        = "ForeGrip"
    },
    ["Weapon.Family.Marksman"] = {
        CyclingMode         = { ["ChargingHandle"] = true },
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "StatIK_LeftHand",
        FallbackBone        = "ForeGrip"
    },
    ["Weapon.Family.SMG"] = {
        CyclingMode         = { ["ChargingHandle"] = true },
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "StatIK_LeftHand",
        FallbackBone        = "ForeGrip"
    },
    ["Weapon.Family.Sidearm.Pistol"] = {
        CyclingMode         = { ["ChargingHandle"] = true },
        IsMagazineGrabbable = false,
        SecondaryGripBone   = "Weapon",
    },
    -- Each overkill weapon is under its own family
    ["Weapon.Family.Overkill.Saw"] = {
        CyclingMode         = {}, -- Rename ChargingHandle to Rack
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "DynIK_LeftHand",
        FallbackBone        = "Grip"
        --Foregrip/grip,
    },
    ["Weapon.Family.Overkill.M606"] = {
        CyclingMode         = {}, -- Rename ChargingHandle to Rack
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "VerticalGrip",
        FallbackBone        = "Grip"
        --Foregrip/grip,
    },
    ["Weapon.Family.Overkill.Mamba"] = {
        CyclingMode         = {}, -- Rename ChargingHandle to Rack
        IsMagazineGrabbable = false,
        SecondaryGripBone   = "DynIK_LeftHand",
        FallbackBone        = "Grip"
        --Foregrip/grip,
    },
    ["Weapon.Family.Overkill.HET5"] = {
        CyclingMode         = {}, -- Rename ChargingHandle to Rack
        IsMagazineGrabbable = true,
        SecondaryGripBone   = "DynIK_LeftHand",
        FallbackBone        = "Grip"
        --Foregrip/grip,
    },
    ["Weapon.Family.Overkill.ARGES"] = {
        CyclingMode         = {}, -- Rename ChargingHandle to Rack
        IsMagazineGrabbable = false,
        SecondaryGripBone   = "DynIK_LeftHand",
        FallbackBone        = "Grip"
        --Foregrip/grip,
    },
}
local ThrowableFamiliesConfig = {
    ["BP_ShockGrenade_C"] = {
        isPin = false,
    },
    ["BP_ThrowableKnife_C"] = {
        IsPin = false
    },
    ["BP_Throwable_FragGrenade_C"] = {
        IsPin = false -- for now
    }
    --[[SBZThrowableKnife
SBZFlashBangGrenade
SBZGrenade
SBZGasGrenade
SBZShockGrenade
SBZFragGrenade]]
}
Experimental.Weapons          = {
    Current = nil,
    ["Primary"] = uevrUtils.deepCopyTable(defaultWeaponState),
    ["Secondary"] = uevrUtils.deepCopyTable(defaultWeaponState),
    ["Overkill"] = uevrUtils.deepCopyTable(defaultWeaponState)
}
Experimental.Throwables       = {
    ["Throwable"] = uevrUtils.deepCopyTable(defaultThrowableState), -- Grenades,Knives, etc etc yada
    ["Tool"] = uevrUtils.deepCopyTable(defaultThrowableState)       -- ECM,bla bla shockwave etc
}

local weaponsTable            = Experimental.Weapons
local VRState                 = Experimental.VRState

local vr                      = uevr.params.vr
local handStates              = VRState.HandStates
local currentMagazine         = {} -- Keep local just to not have to do if currentWeapon and currentWeapon.MagazineState everywhere


local PrimaryHandName    = PD3UserConfig.PreferredHandTypes[VRState.PrimaryHandIndex]
local SecondaryHandName  = PD3UserConfig.PreferredHandTypes[VRState.SecondaryHandIndex]
local PrimaryHandState   = handStates[PrimaryHandName .. "State"]
local SecondaryHandState = handStates[SecondaryHandName .. "State"]
print(SecondaryHandName, "secondaryname")
WeaponGripPresets = {
    ForeGrip = {
        rot = Experimental.VRState.SecondaryHandIndex == 0 and { 0, 45, 0 }
            or { -180, 135, 0 }, -- needs to be a 90+45 on righthand and rest is all zeros or smth
        boneA = "PalmSurface",
    },
    VerticalGrip = {
        rot = Experimental.VRState.SecondaryHandIndex == 0 and { 0, 0, 0 }
            or { -180, 135, 0 }, -- needs to be a 90+45 on righthand and rest is all zeros or smth
        boneA = "PalmSurface",
    },
    Horizontal = {
        rot = Experimental.VRState.SecondaryHandIndex == 0 and { 0, -90, 0 }
            or { 180, 0, -90 }, -- needs to be a 90+45 on righthand and rest is all zeros or smth
        --   boneA = "PalmSurface",
        boneA = SecondaryHandName .. "Weapon",

        boneB = Experimental.VRState.SecondaryHandIndex == 0
            and "LeftHandMiddle1"
            or "RightHandMiddle1",
        blend = 0.7
    },

    Side = {
        rot = Experimental.VRState.SecondaryHandIndex == 0 and { 0, 0, 0 }
            or { -180, 0, 0 }, -- needs to be a 90+45 on righthand and rest is all zeros or smth
        boneA = "PalmSurface"
    },

}

local Buttons     = {
    ["GripRightHand"] = XINPUT_GAMEPAD_RIGHT_SHOULDER,
    ["GripLeftHand"] = XINPUT_GAMEPAD_LEFT_SHOULDER,
}

-- Makes lines less longer


local isSwiping            = false
local isCrouching          = false
local isJumping            = false
local isModifyingSlots     = false
local crouchTimes          = 0
local lastCrouchHit        = 0
local isVRActivated        = false
local inputEnabledOverride = nil


-- configurable
local swipeStrength = 0.4
local punchStrength = 0.9
local assistedPunch = 0.50 -- Swipe/swing + punch lowers the threshold
local magGrabDistance = 0.08
local magDisconnectionDistance = 0.35
local offhandWeaponGrabDist = 0.15


function getCustomIKComponent(rigID)
    if PD3UserConfig.Settings["HandCoupling"] == "Experimental" then -- runs always so this ensure it doesnt on native
        return {
            { descriptor = "Pawn.Mesh1P" },
            { descriptor = "Pawn.Mesh1P(Gloves)", animation = "Arms" },
            { descriptor = "Pawn.Mesh1PSuit" },
            { descriptor = "Pawn.Mesh1PBody" },
        }
    else
        return nil
    end
end

---  function
local function GetVREquippedWeapon()
    local isEquipped = weaponsTable.Current.Model
    if not isEquipped then
        InitializeStates()
        return nil
    end
    return isEquipped or nil
end

-- populates Weapons.Primary and Weapons.Secondary
local function cacheEquippables()
    local weaponActors = uevrUtils.getAllActorsOfClass("Class /Script/Starbreeze.SBZRangedWeapon")

    for _, actor in ipairs(weaponActors) do
        if actor and actor.Mesh and actor.Owner == pawn and actor.EquippableIndex then
            local index = actor.EquippableIndex
            local equippableType = index == 0 and "Primary" or index == 1 and "Secondary" or "Overkill"
            local isModelValid = uevrUtils.getValid(weaponsTable[equippableType].Model)
            if not isModelValid then
                -- OVK weapons need constant model swapping per each time a user drops and grabs it
                if equippableType == "Overkill" and not isModelValid and weaponsTable[equippableType].Config then
                    weaponsTable[equippableType].Model = actor.Mesh
                    return
                end
                local equippableData = actor.EquippableConfig.EquippableData
                local equippableName = stripSuffix(equippableData.AccelByteReferenceName:to_string())
                local sbzEquippable = actor.Mesh:get_outer()
                local parts = sbzEquippable.ModularMeshComponent.VisibilityRig.AttachChildren

                local WeaponTable = weaponsTable[equippableType]
                local ModularMag, RegularMag
                local fakeModel = uevrUtils.createPoseableMeshFromSkeletalMesh(actor.Mesh,
                    { useDefaultPose = true, parent = pawn })
                QueueForGC(fakeModel)
                SetMeshVisibility({ fakeModel }, true)
                print(equippableType, "Here1")
                -- extract mags
                -- Some weapons have two mags or one,
                --the modular might interfere so I remove it from the parts+mag table
                -- also doesn't have good bone placements
                for i, v in pairs(parts) do
                    local partName = v.SkeletalMesh:get_full_name()
                    -- print(partName, "partname")
                    if partName:find("Mag") then
                        if partName:find("SBZModular") then ModularMag = i else RegularMag = i end
                        if ModularMag and RegularMag then
                            table.remove(parts, ModularMag)
                            ModularMag = nil
                        end
                    end
                end
                -- extract bullets and bind their visibility to the mag's
                -- great, bullets only get created when the user reloads
                -- so I have to create them myself from the reference (that only took a few hours to figure out, very fun)
                -- these meshes are highly fragile and will often silently error on normal methods
                local ammoData = sbzEquippable.CurrentAmmoData
                local path = ammoData:get_fname_property("LoadedMesh"):to_string()
                local bullet = uevr.api:find_uobject("StaticMesh " .. path .. "." .. path:match("([^/]+)$"))


                local targetLocation, targetRotation = actor.Mesh:K2_GetComponentLocation(),
                    actor.Mesh:K2_GetComponentRotation()
                -- Extract the default materials before modifying them later on


                table.insert(parts, bullet)
                BindMeshVisibilityToParent(actor.Mesh, { fakeModel })

                fakeModel:K2_AttachToComponent(actor.Mesh, "", 1, 1, 1, true)
                fakeModel:K2_SetWorldLocationAndRotation(targetLocation, targetRotation, false, reusable_hit_result,
                    false)

                SetMeshVisibility({ actor.Mesh }, true)

                WeaponTable.Model = actor.Mesh
                WeaponTable.FakeModel = fakeModel
                WeaponTable.Slot = equippableType
                WeaponTable.Parts = parts
                WeaponTable.Name = equippableName
                WeaponTable.Family = stripSuffix(equippableData.Family.TagName:to_string())
                WeaponTable.Config = WeaponFamiliesConfig[WeaponTable.Family] or ""
                WeaponTable.MagazineState.Model = parts[ModularMag or RegularMag]

                for name, _ in pairs(WeaponTable.Config.CyclingMode) do
                    actor.Mesh:HideBoneByName(uevrUtils.fname_from_string(name))
                    fakeModel:UnHideBoneByName(uevrUtils.fname_from_string(name))
                end
            end
        end
    end

    local throwableActors = uevrUtils.getAllActorsOfClass("Class /Script/Starbreeze.SBZThrowable")
    for _, actor in pairs(throwableActors) do
        if actor then
            local class = actor:get_class():get_fname():to_string()
            print(class)
            if ThrowableFamiliesConfig[class] then
                Experimental.Throwables["Throwable"].Config = ThrowableFamiliesConfig[class]
                Experimental.Throwables["Throwable"].Name = actor:get_fname():to_string()
                Experimental.Throwables["Throwable"].Model = actor.StaticMesh
                Experimental.Throwables["Throwable"].Lever = actor.Lever
                Experimental.Throwables["Throwable"].Actor = actor
            end
        end
    end

    --Name contains: Frag,Throwable,Smoke,Shock,Flash
end

local HolstersInitialized = false
local function initializeHolsters(isUpdate)
    -- Initiate physical slots
    if isUpdate then
        VRState.HolsterSlots.Pouch:K2_DetachFromComponent(0)
        VRState.HolsterSlots.Pouch:K2_DestroyComponent()
        for i, v in pairs(VRState.HolsterSlots) do
            v:K2_DetachFromComponent(0)
            v:K2_DestroyComponent()
            HolstersInitialized = false
        end
    end
    if not HolstersInitialized then
        local current                  = weaponsTable.Current
        local secondaryWeapon          = weaponsTable["Secondary"]
        local weaponMesh               = secondaryWeapon.FakeModel
        local phoneMesh                = pawn.PrimaryTool.Mesh
        local magMesh                  = current and current.MagazineState.Model or secondaryWeapon.MagazineState.Model
        local secondarySlotMesh        = VRState.HolsterSlots.Secondary or
            uevrUtils.createPoseableMeshFromSkeletalMesh(weaponMesh, { parent = pawn })
        
        -- source throwable directly from experimental.Throwables since the replicatedthrowablearray can be nil when throwables run out
        local throwableSlotMesh        = uevrUtils.createStaticMeshComponent(
        Experimental.Throwables["Throwable"].Model.StaticMesh, { parent = pawn })

        local pouchSlotMesh            = uevrUtils.createPoseableMeshFromSkeletalMesh(magMesh, { parent = pawn })
        local phoneSlotMesh            = uevrUtils.createPoseableMeshFromSkeletalMesh(phoneMesh, { parent = pawn })

        local handedString             = PrimaryHandName == "RightHand" and "Right" or "Left"
        local oppositeHandedString     = PrimaryHandName == "RightHand" and "Left" or "Right"
         
        SetMeshVisibility({phoneMesh},false)
        VRState.HolsterSlots.Secondary = secondarySlotMesh
        VRState.HolsterSlots.Pouch     = pouchSlotMesh
        VRState.HolsterSlots.Phone     = phoneSlotMesh
        VRState.HolsterSlots.Throwable = throwableSlotMesh
        QueueForGC(VRState.HolsterSlots)
        SetMeshVisibility(VRState.HolsterSlots, true)
        BindMeshVisibilityToParent(secondaryWeapon.Model, { secondarySlotMesh }, { reverse = true })
        local lastIteration  = 0
        local itemsInBetween = 0
        -- Start at 1, if there's no end then the second one will be the end
        -- If theres a start and an end, take the first and offset
        local InvertYOffset  = VRState.IsLeftHanded and -1 or 1
        local OrderedSlots   = {}
        for n in pairs(VRState.HolsterSlots) do table.insert(OrderedSlots, n) end
        table.sort(OrderedSlots)
        for _, name in ipairs(OrderedSlots) do
            local mesh        = VRState.HolsterSlots[name]
            lastIteration     = lastIteration + 1
            local isSecondary = name == "Secondary"
            --  local lastSavedLocation = PD3UserConfig.Settings["Slots"][i] or nil

            mesh:K2_SetWorldRotation(
                kismet_math_library:MakeRotFromX(
                    uevrUtils.vector_3f(0, 0, -1)
                ),
                false,
                reusable_hit_result,
                false
            )

            local side = isSecondary and handedString .. "UpLeg" or oppositeHandedString .. "UpLeg"
            local loc = VRState.BaseModel:GetSocketLocation(uevrUtils.fname_from_string(side))
            local yOffset = isSecondary and 25.0 * InvertYOffset or -25.0 * InvertYOffset

            -- Static positions, Left and right, anything inbetween gets inserted from the pouch and depending on how many stuff
            if (isSecondary or name == "Pouch") then
                mesh:K2_DetachFromComponent(0)
                mesh:K2_AttachToComponent(VRState.BaseModel, uevrUtils.fname_from_string(side), 2, 2, 2, true)
                mesh:K2_SetRelativeRotation(uevrUtils.rotator(0, 90, 180), false, reusable_hit_result, false)
                mesh:K2_SetRelativeLocation(
                    uevrUtils.vector_3f(-yOffset / 2, yOffset / 2, yOffset),
                    false, reusable_hit_result, false
                )



                --   if lastSavedLocation and not (lastSavedLocation.x == 0 and lastSavedLocation.y == 0 and lastSavedLocation.z == 0) then
                --  v:K2_SetRelativeLocation(vector_3(lastSavedLocation.x,lastSavedLocation.y,lastSavedLocation.z), false, reusable_hit_result, false)
            else
                print(name, "bam")
                print(mesh)
                itemsInBetween = itemsInBetween + 1
                -- if itemsInBetween ==   1 then offset = -2  else offset = InvertYOffset*InvertYOffset end
                mesh:K2_AttachToComponent(VRState.BaseModel, uevrUtils.fname_from_string(side), 2, 2, 2, true)
                mesh:K2_SetRelativeRotation(uevrUtils.rotator(0, 0, 0), false, reusable_hit_result, false)
                mesh:K2_SetRelativeLocation(
                    uevrUtils.vector_3f(-yOffset / 2 * (1 - (0.5 * (itemsInBetween == 1 and itemsInBetween * 4.5 or 2))),
                        yOffset / 2, yOffset),
                    false, reusable_hit_result, false
                )
            end

            -- uevrutils.setcomponentoffset instead better
        end
        HolstersInitialized = true
    end
end


function InitializeStates(weaponModel)
    if pawn and pawn.Mesh1P then
        local EquippableIndex = pawn.CurrentEquippableIndex
        local slot = EquippableIndex == 0 and "Primary" or EquippableIndex == 1 and "Secondary" or "Overkill"
        local weaponTable = weaponsTable[slot]
        print(slot, weaponsTable[slot])
        local equippableConfig = pawn.CurrentEquippableConfig
        local heisterName = pawn:get_fname():to_string():match("CH_(%a+)_")
        local weaponModel = weaponModel or weaponsTable.Current and weaponsTable.Current.Model
        print(slot, EquippableIndex)
        if weaponsTable[slot].Model == nil then -- First initiation or last initiation failed
            -- Cache weapons, restrict abilities like firing etc and init animations
            local primaryWeapon, secondaryWeapon = weaponsTable["Primary"], weaponsTable["Secondary"]

            cacheEquippables()
            --  Only Restrict abilities when the mask is on to avoid a bug where weapons don't fire



             SetMeshVisibility({ primaryWeapon.Model, secondaryWeapon.Model }, false)
            initializeHolsters()

            WeaponAnimController.Init(VRState, PrimaryHandName, SecondaryHandName, primaryWeapon.Name,
                secondaryWeapon.Name, Experimental.Throwables["Throwable"].Name)

            -- else spawn them at the player's hand or gun position because then its always infront
            -- Bind meshes so that when SetMeshVisibility is called on the parent the children follow
            for weaponTable, v in pairs(weaponsTable) do
                if v.Model then
                    BindMeshVisibilityToParent(v.Model, v.Parts)
                end
            end
        else
        end

        if not VRState.SuitModel then
            local allMeshes = uevrUtils.find_all_of("Class /Script/Engine.SkeletalMeshComponent", false) -- THERE IS A SUIT, just invisible because we are in First person
            for i, v in pairs(allMeshes) do
                if v and v.SkeletalMesh then
                    local SkeletalName = v.SkeletalMesh:get_full_name()
                    --  Set  Suit's visibility


                    if SkeletalName:find("Suit") and SkeletalName:find("_" .. heisterName .. "_") and not SkeletalName:find("FPP") then
                        -- Create a poseable of the actual mesh so we can manipulate bone visibility
                        -- and hide hands, I really tried to avoid this method but its just not possible as far as I know

                        VRState.SuitModel = uevrUtils.createPoseableMeshFromSkeletalMesh(v, { parent = pawn })
                        QueueForGC(VRState.SuitModel)
                        SetMeshVisibility({ VRState.SuitModel }, PD3UserConfig.Settings["BodyVisibility"])
                        -- needs to be attached to both to work

                        VRState.SuitModel:K2_AttachToComponent(VRState.BaseModel, "", 2, 2, 2, true)
                        VRState.SuitModel:HideBoneByName(uevrUtils.fname_from_string("Neck1"), 0)
                        VRState.SuitModel:HideBoneByName(uevrUtils.fname_from_string("Neck"), 0)
                        -- hide hand bones incase the suit model has seperate hands
                        for _, boneName in ipairs(animation.getBoneNames(VRState.SuitModel)) do
                            if boneName:find("Hand") or boneName:find("Arm") or boneName:find("ForeArm") or boneName:find("Elbow") then
                                VRState.SuitModel:HideBoneByName(boneName)
                            end
                        end


                        local isVisible, updated = nil, nil
                        -- sync the suit's location to the VR basemodel so crouching syncs
                        uevr.sdk.callbacks.on_post_engine_tick(function(engine, delta)
                            if VRState.BaseModel and uevrUtils.getValid(pawn) and uevrUtils.getValid(v) then
                                if updated ~= PD3UserConfig.Settings["BodyVisibility"] then
                                    SetMeshVisibility({ VRState.SuitModel }, PD3UserConfig.Settings["BodyVisibility"])
                                    updated = PD3UserConfig.Settings["BodyVisibility"]
                                end
                            end
                        end)
                    end
                end
            end
        end
        if weaponModel then
            currentMagazine = weaponTable.MagazineState
            weaponsTable.Current = weaponsTable[slot]
            Actions:Equip(weaponsTable.Current, PrimaryHandState, VRState.HandModel, VRState
                .PrimaryHandIndex,
                { Pose = "GripPose" })
            print("Current", weaponsTable.Current)
            initializeHolsters(true)
        end
    end
end

function Experimental.ActivateExperimentalMode(pawn)
    -- Pass context to other scripts to avoid circular requiring


    local weapon = pawn.CurrentEquippable
    local attrSet = pawn.PlayerAttributeSet


    Actions.Init(Experimental)
    gestures.Init(Experimental)
    -- reset gesture holding states
    handsAnimation.setHoldingAttachment(VRState.PrimaryHandIndex, false)
    handsAnimation.setHoldingAttachment(VRState.SecondaryHandIndex, false)

    local RightGripBone
    local LeftGripBone
    local Glove, Body, Base


    ik.registerOnMeshCreatedCallback(function(meshComponentList, ikInstance)
        if uevrUtils.getValid(pawn) and pawn.Mesh1P then
            SetMeshVisibility({ pawn.Mesh1P, pawn.Mesh1PBody, pawn.Mesh1PGloves, pawn.Mesh1PSuit }, false)
            SetMeshVisibility(meshComponentList, true)

            -- Extract needed IK models like base,body,glove
            for i, v in ipairs(meshComponentList) do
                local mat = v:GetMaterial(i)


                if mat then
                    v:ShowMaterialSection(i, 0, true, 0)
                    for i, v2 in pairs(animation.getBoneNames(v)) do
                        local fname = uevrUtils.fname_from_string(v2)
                        v:UnHideBoneByName(fname, 0)
                    end
                end
                if v.SkeletalMesh:get_full_name():find("Glove") then
                    VRState.HandModel = v
                elseif v.SkeletalMesh:get_full_name():find("Suit") then
                    -- This mesh contains the arms mostly, ithas only a lowerbody
                    -- which is useless to me, can't even show the upper one
                    -- Potentially could be in Glove or base
                    -- need to later dynamically find out
                    for i = 0, v:GetNumMaterials() - 1 do
                        local mat = v:GetMaterial(i)
                        local matName = mat and mat:get_fname():to_string():lower()
                        local shouldMatShow = not (matName and matName:find("lowerbody", 1, true) or
                            matName:find("low", 1, true))
                        v:ShowMaterialSection(i, 0, shouldMatShow, 0)
                    end
                    for i, v2 in pairs(animation.getBoneNames(v)) do
                        local fname = uevrUtils.fname_from_string(v2)
                        v:UnHideBoneByName(fname, 0)
                    end
                elseif v.SkeletalMesh:get_full_name():find("Base") then
                    VRState.BaseModel = v
                end
            end
            ik.init(true)
            InitializeStates()
            local mesh = ExperimentalModule.VRState.BaseModel
            -- counteract special cases where these actions would momentarily break VR or degrade the experience

            RegisterGASActivation("GA_Equip_C", "After", false, function()
                local CurrentEquippableIndex = pawn.CurrentEquippableIndex
                if CurrentEquippableIndex == 2 then -- Equipping an overkill weapon
                    print(pawn.CurrentEquippable.Mesh:get_full_name(), "fullname")
                    InitializeStates(pawn.CurrentEquippable.Mesh)

                    if not WeaponAnimController.FindPoseInConfig(weaponsTable.Current.Name) then
                        WeaponAnimController.calibrateHandAnimation(VRState.HandModel, "Overkill", PrimaryHandName,
                            SecondaryHandName, weaponsTable.Current.Name,
                            function()
                            end)
                    end
                else
                    if weaponsTable["Overkill"].Model then
                        weaponsTable["Overkill"].Model = nil
                    end
                end
            end)
            RegisterGASActivation("GA_Downed", "On", false, function()
                --   SetMeshVisibility({ pawn.CurrentEquippable.Mesh }, true)
                -- If a weapon is equipped, equip the secondary because that's what pd3 does
                if weaponsTable.Current.Slot == "Primary" then
                    InitializeStates(weaponsTable.Current.Model)
                end
            end)

            --  Only Restrict abilities when the mask is on to avoid a bug where weapons don't fire
            VRState.IsMasked = pawn.SBZPlayerState.bIsMaskOn
            local lastMontage
            local animInstance = pawn.Mesh1P:GetAnimInstance()
            if not VRState.IsMasked then
                loopUntil("RestrictAfterEquip", 100, function()
                    local montage = animInstance:GetCurrentActiveMontage()
                    if montage then
                        local name = montage:get_full_name()
                        if name:find("Equip") and name:find("Gun") then
                            if not lastMontage then lastMontage = montage end
                        end
                    end
                    if lastMontage and not animInstance:Montage_IsPlaying(lastMontage) then
                        VRState.IsMasked = true
                        RestrictAbilities(true)
                        return false
                    end
                end)
            else -- already masked on
                VRState.IsMasked = true
                RestrictAbilities(true)
            end
            -- On actiavtion, disable input, after disabling, disable override
            RegisterGASActivation("SBZPlayerViewTargetAbility", "On", false, function()
                inputEnabledOverride = false
            end)
            RegisterGASActivation("SBZPlayerViewTargetAbility", "After", false, function()
                inputEnabledOverride = nil
            end)
            RegisterGASActivation("GA_HumanShieldInstigator_C", "On", false, function()
                loopUntil("WaitForCarryActor", 200, function()
                    if pawn.CurrentCarryActor then
                        SetMeshVisibility({ pawn.CurrentCarryActor.Mesh }, true)
                        return false
                    end
                end)
            end)


            RightGripBone = PD3UserConfig.PreferredHandTypes[1] .. "Weapon"
            LeftGripBone = PD3UserConfig.PreferredHandTypes[0] .. "Weapon"

            attachments.registerOnGripUpdateCallback(function()
                if uevrUtils.validate_object(pawn) and pawn.Mesh1P then
                    return PrimaryHandState.CurrentItem, VRState.BaseModel, PrimaryHandName .. "Weapon"
                end
            end)
        end
    end)

    ik.init(true)
end

-- Gestures,Input, etc handling

-- Detection stuff should be here, execution should be in Actions.lua
-- special detection like punch/swipe


local function HandleWeaponEquip(WeaponSlot, handIndex, State)
    if VRState.IsMasked then
        -- cancel if any previous
        local Slot = WeaponSlot == "Primary" and 0 or 1
        if weaponsTable.Current and weaponsTable.Current.Slot ~= Slot then
            SetMeshVisibility(
                { pawn.CurrentEquippable.Mesh }, false)
        end
        uevr.api:dispatch_custom_event("ActivateAbility", "GA_Equip" .. WeaponSlot .. "Weapon")
        uevrUtils.destroyDeferral("HasFinishedEquip")



        local CachedMesh = weaponsTable[WeaponSlot].Model

        local LastEquippableIndex = pawn.CurrentEquippableIndex
        loopUntil("HasFinishedEquip", 32, function()
            if (pawn.CurrentEquippableIndex ~= LastEquippableIndex or pawn.CurrentEquippableIndex == Slot) then
                -- Should replicate to other parts like scope/mag

                local customBinding = nil

                -- Lua silently errors on [currentMagazine.Model] = true so that's that
                InitializeStates(weaponsTable[WeaponSlot].Model)
                customBinding = { [currentMagazine.State == ""] = currentMagazine.Model }
                --   SetMeshVisibility({ pawn.CurrentEquippable.Mesh }, true, customBinding)

                return false
            end
        end)
    end
end


local function DetectMelee(hand, hasPunched, strength)
    if weaponsTable.Current and hand == VRState.PrimaryHandIndex or hasPunched then
        if (strength >= punchStrength and hasPunched) or strength >= assistedPunch and isSwiping then
            Actions:Melee()
            isSwiping = false
        end
    end
end

local function detectSwipes(strength, hand)
    if strength >= swipeStrength and hand == VRState.PrimaryHandIndex then
        isSwiping = true
        DetectMelee(hand, false, swipeStrength)
    elseif strength <= swipeStrength then
        isSwiping = false
    end
end


local currentboltBone = ""
local lastButtonPress = nil
local isPhoneActive = false -- Port to VRState, I just forgot to do this and I'm minutes away from release
uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    if PD3UserConfig.Settings["HandCoupling"] == "Experimental" and pawn and pawn.Mesh1P and VRState.BaseModel then
        local primaryHandPosition = VRState.BaseModel:GetSocketLocation(PrimaryHandName, 0)
        local secondaryHandPosition = VRState.BaseModel:GetSocketLocation(SecondaryHandName, 0)
        -- Equipping Primary/Secondary

        if gestures.detectGestureWithState(gestures.Gesture.UNHOLSTER, state, VRState.PrimaryHandIndex) then
            HandleWeaponEquip("Secondary", VRState.SecondaryHandIndex)
        end

        if gestures.detectGestureWithState(gestures.Gesture.UNHOLSTER_BACKOFHEAD, state, VRState.PrimaryHandIndex) then
            HandleWeaponEquip("Primary", VRState.PrimaryHandIndex)
        end


        -- Equip a magazine from the pouch if any
        if weaponsTable.Current and currentMagazine.Model and IsButtonRecentlyPressed(SecondaryHandName .. "Shoulder") then
            if IsWithinRange(secondaryHandPosition, VRState.HolsterSlots.Pouch:K2_GetComponentLocation(), 0, 0.1) then
                if not PD3UserConfig.Settings["AutoReload"] and SecondaryHandState.CurrentAction == "" then
                    Actions:Equip(weaponsTable.Current, SecondaryHandState, VRState.BaseModel,
                        VRState.SecondaryHandIndex,
                        { Pose = "ReloadPose", Prop = currentMagazine.Model })

                    SecondaryHandState.CurrentAction = "HoldingMag"
                    --   elseif weaponsTable.Current and weaponsTable.Current.Model then
                    --     -- Shotguns, grab bullets immediately and attach
                end
            end
        end

        -- Grabbing a  mag from the gun OR Inserting a new one
        if gestures.detectGestureWithState(gestures.Gesture.RELOAD, state, VRState.PrimaryHandIndex) or SecondaryHandState.CurrentAction == "HoldingMag" then -- Gripping preferred hand
            -- He has a mag and wants to insert it

            if not PD3UserConfig.Settings["AutoReload"] then
                local MagPos
                if currentMagazine.Model then MagPos = currentMagazine.Model:K2_GetComponentLocation() end

                if SecondaryHandState.CurrentAction == "HoldingMag" and (currentMagazine.State == "Grabbed" or currentMagazine.State == "Dropped") then
                    -- Check distance of mag to the actual mag + check if it direction is somewhat matching
                    local magwellPos      = weaponsTable.Current.Model:GetSocketLocation(
                        uevrUtils.fname_from_string("Mag"), 0)
                    local PropMagPos      = SecondaryHandState.CurrentItem:K2_GetComponentLocation()

                    local PropMagUpVector = kismet_math_library:GetUpVector(SecondaryHandState.CurrentItem
                        :K2_GetComponentRotation())
                    local MagUpVector     = kismet_math_library:GetUpVector(currentMagazine.Model
                        :K2_GetComponentRotation())

                    local delta           = kismet_math_library:Dot_VectorVector(MagUpVector, PropMagUpVector)

                    if delta >= 0.5 and IsWithinRange(PropMagPos, magwellPos, 0, magGrabDistance) then
                        if currentMagazine.LastGrabbedMag and os.clock() - currentMagazine.LastGrabbedMag >= 2 then
                            Actions:Reload(SecondaryHandState, VRState.HandModel, weaponsTable.Current,
                                VRState.SecondaryHandIndex,
                                "Manual")
                        end
                    end

                    --- They want to grab/grip the mag from the weapon itself
                elseif weaponsTable.Current and weaponsTable.Current.Model and SecondaryHandState.CurrentAction ~= "HoldingMag" and currentMagazine.State == "" then
                    if weaponsTable.Current.Config and weaponsTable.Current.Config.IsMagazineGrabbable and not PD3UserConfig.Settings["AutoReload"] then
                        if IsWithinRange(secondaryHandPosition, MagPos, 0, 0.2) then
                            -- Mag bones are placed ontop of the actual mags
                            -- and I've tried but did not find mags that
                            -- have a bone at the middle of it
                            -- so I attach to the bone ontop of the mag
                            -- then I offset to its origin (middle I suppose)
                            local socketTransform =
                                currentMagazine.Model:GetSocketTransform(uevrUtils.fname_from_string("Mag"), 0)

                            local socketLoc =
                                currentMagazine.Model:GetSocketLocation(uevrUtils.fname_from_string("Mag"))

                            local bounds =
                                currentMagazine.Model:GetSkeletalMeshAsset():GetImportedBounds()

                            local worldMiddle =
                                kismet_math_library:TransformLocation(
                                    currentMagazine.Model:K2_GetComponentToWorld(),
                                    bounds.Origin
                                )
                            local deltaLocal =
                                kismet_math_library:InverseTransformDirection(
                                    socketTransform,
                                    worldMiddle - socketLoc
                                )

                            local offset = {
                                0,
                                0,
                                deltaLocal.Z / 2
                            }
                            AttachHandAccurate(
                                VRState.SecondaryHandIndex,
                                ExperimentalModule.VRState.BaseModel,
                                currentMagazine.Model,
                                "Mag",
                                { 0, 0, 0 },
                                offset,
                                SecondaryHandName,
                                "PalmSurface"
                            )
                            handsAnimation.setHoldingAttachment(VRState.SecondaryHandIndex, true)
         
                            SecondaryHandState.IsAttached = true
                            SecondaryHandState.CurrentAction = "HoldingMag"
                            currentMagazine.LastGrabbedMag = os.clock()
                            currentMagazine.State = "Gripped"
                            WeaponAnimController.ApplyHandPose(VRState.BaseModel, SecondaryHandName, "ReloadPose",
                                weaponsTable.Current.Name)
                        end
                    end
                end
            end
        end
        -- Hand is attached to the mag, awaiting disconnection
        if SecondaryHandState.CurrentAction == "HoldingMag" and currentMagazine.State == "Gripped" then
            local ControllerPos = controllers.getControllerLocation(VRState.SecondaryHandIndex)
            local MagPos = currentMagazine.Model:GetSocketLocation(
                uevrUtils.fname_from_string("Body"), 0)
            if not IsWithinRange(ControllerPos, MagPos, 0, magDisconnectionDistance) and weaponsTable.Current then
                currentMagazine.LastMagazineGrabbedCapacity = pawn.CurrentEquippable.AmmoLoaded
                Actions:Reload(SecondaryHandState, VRState.BaseModel, weaponsTable.Current,
                    VRState.SecondaryHandIndex, "Manual")
            end
        end

        ---- Phone equipping/unequipping
        if IsButtonRecentlyPressed(SecondaryHandName .. "Shoulder") then
            if SecondaryHandState.CurrentAction == "" then
                local phone = VRState.HolsterSlots.Phone
                if IsWithinRange(secondaryHandPosition, phone:K2_GetComponentLocation(), 0, 0.1) then
                    -- Equip actual model for screen animations
                    --  SetMeshVisibility({ pawn.PrimaryTool.Mesh }, true)
                    Actions:Equip(nil, SecondaryHandState, VRState.BaseModel,
                        VRState.SecondaryHandIndex,
                        { Pose = "PhoneGripPose",PropName = "PhoneGripPose" , Prop = phone, KeepRotation = true })
                    SecondaryHandState.CurrentItem:K2_SetRelativeRotation(uevrUtils.rotator(0, 90, -20), false,
                        reusable_hit_result, false)
                    SecondaryHandState.CurrentAction = "HoldingPhone"
                end
            end
        elseif uevrUtils.isButtonNotPressed(state, Buttons["Grip" .. SecondaryHandName]) and SecondaryHandState.CurrentAction == "HoldingPhone" then -- Not pressed and holding phone
            Actions:Unequip(SecondaryHandState, nil, VRState.BaseModel, VRState
                .SecondaryHandIndex, { CollisionEnabled = false, DestroyCurrentItem = true,Pose = "OriginalPose" })
            print("uneqeuipping")
        end
                 -- Phone activation (temporary)
            if SecondaryHandState.CurrentAction ==   "HoldingPhone" then
                if uevrUtils.isButtonPressed(state,XINPUT_GAMEPAD_Y) then
                    if not lastButtonPress then lastButtonPress = os.clock() end
                    local lastPressed =  os.clock() - lastButtonPress
                    if lastPressed >= 0.5 and lastPressed <= 1 and not isPhoneActive then
                        isPhoneActive = true
                        Actions:ActivatePhone("ActivateTool")
                    elseif lastPressed >= 1  and not isPhoneActive then
                          isPhoneActive = true
                        Actions:ActivatePhone("RequestOVKWeapon")
                    end
                end
            else
            lastButtonPress = nil 
            isPhoneActive = false
            end
        -- Throwables
        if IsButtonRecentlyPressed(SecondaryHandName .. "Shoulder") then
            if SecondaryHandState.CurrentAction == "" then
                local throwable = Experimental.Throwables["Throwable"]
                if IsWithinRange(secondaryHandPosition, VRState.HolsterSlots.Throwable:K2_GetComponentLocation(), 0, 0.1) then
                    -- Equip actual model for screen animations
                    --  SetMeshVisibility({ pawn.PrimaryTool.Mesh }, true)
                    Actions:Equip(nil, SecondaryHandState, VRState.BaseModel,
                        VRState.SecondaryHandIndex,
                        { Prop = VRState.HolsterSlots.Throwable,PropName = throwable.Name })

                    -- SecondaryHandState.CurrentItem:K2_SetRelativeRotation(uevrUtils.rotator(0, 90, -20), false, reusable_hit_result, false)
                    SecondaryHandState.CurrentAction = "HoldingThrowable"
                end
            end
        elseif uevrUtils.isButtonNotPressed(state, Buttons["Grip" .. SecondaryHandName]) and SecondaryHandState.CurrentAction == "HoldingThrowable" then -- Not pressed and holding phone
            local throwable = Experimental.Throwables["Throwable"]
            if not ThrowableFamiliesConfig[throwable.Name].IsPin then
                Actions:ActivateThrowable(ThrowableFamiliesConfig[throwable.Name], throwable.Actor)
            end
        end
        -- Grab objects with the secondary hand (port tbh the other one here too cause yes)
        --- Raycast, if hit barrel then attach the hand,
        -- also ensure that the button was previously UNPRESSED, and not pressed already
        if IsButtonRecentlyPressed(SecondaryHandName .. "Shoulder") and SecondaryHandState.CurrentAction == "" then
            -- print(weaponsTable.Current and weaponsTable.Current.Model)
            if weaponsTable.Current and weaponsTable.Current.Model then
                local weaponModel = weaponsTable.Current.Model
                local isLeftHanded = VRState.IsLeftHanded
                local SecondaryGripBone = weaponsTable.Current.Config.SecondaryGripBone

                local fallbackBone =weaponsTable.Current.Config.FallbackBone

                local boneExists =weaponModel:DoesSocketExist(uevrUtils.fname_from_string(SecondaryGripBone))

                -- fallback if it doesnt exist
                if not boneExists and fallbackBone then   SecondaryGripBone = fallbackBone  end

                local socketPos = weaponModel:GetSocketLocation(uevrUtils.fname_from_string(SecondaryGripBone))

                if IsWithinRange(socketPos, secondaryHandPosition, 0, 0.2) then
                    local preset =  WeaponGripPresets[ SecondaryGripBone == "Weapon" and "Side"  or SecondaryGripBone] 
                    or  WeaponGripPresets.Horizontal
                    AttachHandAccurate(
                        VRState.SecondaryHandIndex,
                        VRState.BaseModel,
                        weaponsTable.Current.FakeModel,
                        SecondaryGripBone,
                        preset.rot,
                        nil,
                        SecondaryHandName,
                        preset.boneA,
                        preset.boneB,
                        preset.blend
                    )
                    handsAnimation.setHoldingAttachment(VRState.SecondaryHandIndex, true)
                    SecondaryHandState.IsAttached = true
                    SecondaryHandState.CurrentAction = "HoldingWeapon"
                    uevr.api:dispatch_custom_event("ActivateAbility", "PlayerTarget")

                    WeaponAnimController.ApplyHandPose(VRState.HandModel, SecondaryHandName, "GripPose",
                        weaponsTable.Current
                        .Name, false)
                end
            end
        end

        -- Automatic mag ejection
        if uevrUtils.isButtonPressed(state, XINPUT_GAMEPAD_X) and PrimaryHandState.CurrentAction == "HoldingWeapon" and currentMagazine.State ~= "Dropped" then
            if currentMagazine.State ~= "Gripped" then -- is not interacting with widgets
                Actions:Reload(SecondaryHandState, VRState.HandModel, weaponsTable.Current,
                    VRState.PrimaryHandIndex,
                    "AutomaticEjection")
            end
        end
        -- Manual Bolting
        if not PD3UserConfig.Settings["AutoChamber"] and weaponsTable.Current and weaponsTable.Current.Model then
            if IsButtonRecentlyPressed(SecondaryHandName .. "Trigger") and SecondaryHandState.CurrentAction == "" then
                -- boltcatch is almost always on the opposite side of an AR
                for boltName, _ in pairs(weaponsTable.Current.Config.CyclingMode) do
                    local boltLocation = weaponsTable.Current.Model:GetSocketLocation(uevrUtils.fname_from_string(
                    boltName))
                    if IsWithinRange(secondaryHandPosition, boltLocation, 0, 0.2) then
                        Actions:BoltWeapon(SecondaryHandState, weaponsTable.Current, VRState.BaseModel,
                            VRState.SecondaryHandIndex,
                            "Grab", boltName, "Manual")
                        currentboltBone = boltName
                    end
                end
            elseif not isDigitalButtonPressed(SecondaryHandName .. "Trigger") and SecondaryHandState.CurrentAction == "HoldingBolt" then
                Actions:BoltWeapon(SecondaryHandState, weaponsTable.Current, VRState.BaseModel,
                    VRState.SecondaryHandIndex,
                    "Drop", currentboltBone)
            end
        end

        -- Unequip Secondary on Primary Hand
        if gestures.detectGestureWithState(gestures.Gesture.HOLSTER, state, VRState.PrimaryHandIndex) and IsButtonRecentlyPressed(PrimaryHandName .. "Shoulder") and PrimaryHandState.CurrentItem then
            if weaponsTable.Current then
                Actions:Unequip(PrimaryHandState, weaponsTable.Current, VRState.HandModel, VRState
                    .PrimaryHandIndex)
            end
        end
        -- unequip Primary on Primary Hand
        if gestures.detectGestureWithState(gestures.Gesture.UNHOLSTER_BACKOFHEAD, state, VRState.PrimaryHandIndex) and IsButtonRecentlyPressed(PrimaryHandName .. "Shoulder") and PrimaryHandState.CurrentItem then
            if weaponsTable.Current then
                Actions:Unequip(PrimaryHandState, weaponsTable.Current, VRState.HandModel, VRState
                    .PrimaryHandIndex)
            end
        end

        -- Letting go of things on SecondaryHand (Mags)
        if uevrUtils.isButtonNotPressed(state, Buttons["Grip" .. SecondaryHandName]) and (SecondaryHandState.CurrentItem or SecondaryHandState.CurrentAction == "HoldingWeapon") then
            if (not weaponsTable.Current or not weaponsTable.Current.Model) and SecondaryHandState.CurrentAction ~= "HoldingThrowable" then return end
            if SecondaryHandState.CurrentAction == "HoldingWeapon" then
                GetLastState().Gamepad.bLeftTrigger = 255
                uevrUtils.delay(1000, function() GetLastState().Gamepad.bLeftTrigger = 0 end)
            end
            if SecondaryHandState.CurrentAction == "HoldingMag" and SecondaryHandState.CurrentItem then currentMagazine.LastMagazineGrabbedCapacity = 0 end
            Actions:Unequip(SecondaryHandState, weaponsTable.Current, VRState.BaseModel, VRState
                .SecondaryHandIndex,
                {
                    CollisionEnabled = SecondaryHandState.CurrentAction == "HoldingMag",
                    DestroyCurrentItem = SecondaryHandState.CurrentAction == "HoldingThrowable",
                    PropName = SecondaryHandState.CurrentAction == "HoldingThrowable" and Experimental.Throwables["Throwable"].Name
               })

            end
        -- Modifying holster locations
        if PD3UserConfig.Settings["IsCalibrating"] then
            for i, v in pairs(VRState.HolsterSlots) do
                for _, handed in pairs({ 1, 0 }) do
                    local handedStr = HandedIndexToString(handed)
                    local grabbedHandState = handStates[handedStr .. "State"]
                    local oppositeSlot = i == "Secondary" and "Pouch" or "Secondary"
                    if uevrUtils.isButtonPressed(state, Buttons["Grip" .. handedStr]) then
                        if IsWithinRange(controllers.getControllerLocation(handed), v:K2_GetComponentLocation(), 0, 0.15) then
                            if grabbedHandState.CurrentAction ~= "ConfiguringSlot" then
                                -- unequip everything, stop animating hands
                                --   Actions:Unequip(PrimaryHandState, weaponsTable.Current, VRState.BaseModel, HandState
                                --      .PrimaryHandIndex)
                                --     Actions:Unequip(SecondaryHandState, weaponsTable.Current, VRState.BaseModel, HandState
                                --         .SecondaryHandIndex, true)
                                handsAnimation.setAutoHandleInput(false)
                                grabbedHandState.CurrentAction = "ConfiguringSlot"
                                Actions:GrabSlots(grabbedHandState, v, VRState.HolsterSlots[oppositeSlot], handed, true)
                            end
                        end
                    elseif uevrUtils.isButtonNotPressed(state, Buttons["Grip" .. handedStr]) and grabbedHandState.CurrentAction == "ConfiguringSlot" then
                        Actions:GrabSlots(handStates, v, VRState.HolsterSlots[oppositeSlot], handed, false)
                        grabbedHandState.CurrentAction = ""
                    end
                end
            end
        end
    end
end)




local function cleanup()
    Actions:Unequip(PrimaryHandState, weaponsTable.Current, VRState.HandModel, VRState.PrimaryHandIndex)
    Actions:Unequip(SecondaryHandState, weaponsTable.Current, VRState.HandModel, VRState.SecondaryHandIndex)


    ResetBindedMeshes() -- reset any  visibility binds between objects
    DestroyGCQueue()    -- destroy any created meshes so that we don't interrupt world loading/unloading
end

uevr.sdk.callbacks.on_script_reset(cleanup)

local FiredCountLevel = 0
uevrUtils.registerPreLevelChangeCallback(function(levelName)
    FiredCountLevel = FiredCountLevel + 1
    if FiredCountLevel > 1 then
        cleanup()
    end
end)
local inputEnabledOverride = nil
-- Force input states
uevr.sdk.callbacks.on_post_engine_tick(function()
    if inputEnabledOverride ~= nil then
        input.setDisabled(inputEnabledOverride)
        return
    end


        if vr.is_hmd_active() then
                if not isVRActivated then
            isVRActivated = true
            --  vr.recenter_horizon()
            uevrUtils.delay(1000, function()
                input.setDisabled(false)
                vr.recenter_view()
            end)
        end
        else
            input.setDisabled(true)
            isVRActivated = false
        end
end)





--
local Handed = Handed.Right == VRState.PrimaryHandIndex or Handed.Left

gestures.registerSwipeDownCallback(detectSwipes, Handed)
gestures.registerSwipeLeftCallback(detectSwipes, Handed)
gestures.registerSwipeRightCallback(detectSwipes, Handed)
gestures.registerPunchCallback(DetectMelee, Handed)
return Experimental
