local Actions              = {}
local WeaponAnimController = require("libs/WeaponAnimationController")
local attachments          = require("libs/attachments")
local uevrUtils            = require("libs/uevr_utils")
local controllers          = require('libs/controllers')
local animation            = require("libs/animation")
local PD3UserConfig        = require("libs/config/PD3UserConfig")
local handsAnimation       = require("libs/hands_animation")
local pawn
local attributeSet


-- needed to avoid circularly requiring other modules, until I get a third party script or something I'll stick to this
function Actions.Init(experimentalModule)
    pawn = uevrUtils:get_local_pawn()
    attributeSet = pawn.PlayerAttributeSet
    ExperimentalModule = experimentalModule
end

local function resetEmptyCycle()
    -- Secondaries require this dispatch, how it works is a headache that I don't even want to wrap my head around
    -- but in all basicality from what I understood, in secondaries whilst GA_Reload is restricted,
    -- a bool called bisemptycycleneeded is stuck to 1
    -- you can never do anything, even if you set it back to 0
    -- the game waits for a specific sequence or transition to return the gun back to normal (0x0B)

    uevr.api:dispatch_custom_event("ResetReloadCycleNative", "")
    pawn.CurrentEquippable.bIsEmpty = false
    pawn.CurrentEquippable.bIsReloading = false
    pawn.ReplicatedReloadState.Array.bIsEmptyCycleNeeded = false
    pawn.ReplicatedReloadState.Array.bIsCycleNeeded = false
end
-- Handles both inserting a mag (first if clause) and grabbing mag out of the well

function Actions:Reload(HandState, HandModel, WeaponState, Handed, ReloadType)
    local MagazineState = WeaponState.MagazineState
    local setWeaponLoadedAmmo = attributeSet["Multicast_Set" .. WeaponState.Slot .. "EquippableAmmoLoaded"]
    local setWeaponInventoryAmmo = attributeSet["Multicast_Set" .. WeaponState.Slot .. "EquippableAmmoInventory"]
    --if not PD3UserConfig.Settings["IsCalibrating"]  then
    if ReloadType == "Manual" then
        if HandState.CurrentAction == "HoldingMag" and HandState.CurrentItem and (MagazineState.State == "Grabbed" or MagazineState.State == "Dropped") then     -- Reload logic
            HandedString = Handed == 0 and "Left" or "Right"

            -- check mag distance from actual mag
            -- if close enough and orienting mostly the same as the other mag, ,unattach the prop mag,destroy it, show the actual mag
            -- don't rely on starbreeze's reloading system, do it yourself

            local EquippableConfigData = pawn.CurrentEquippableConfig.EquippableData
            local MaxLoaded = EquippableConfigData.FireData.AmmoLoadedMax     -- total in loaded
            local ReserveTotal = attributeSet[WeaponState.Slot .. "EquippableAmmoInventory"].CurrentValue
            local currentInMag = attributeSet[WeaponState.Slot .. "EquippableAmmoLoaded"].CurrentValue
            local TotalInMag = MagazineState.LastMagazineGrabbedCapacity ~= 0 and
                MagazineState.LastMagazineGrabbedCapacity
                or 0
            local newMagTotal = math.min(MaxLoaded,
                MagazineState.LastMagazineGrabbedCapacity ~= 0 and MagazineState.LastMagazineGrabbedCapacity or
                TotalInMag + ReserveTotal)

            local newReserve = math.max(0, ReserveTotal - (newMagTotal - TotalInMag))

            attachments.detach(HandState.CurrentItem, nil, nil, nil, true, true)
            SetMeshVisibility({ HandState.CurrentItem }, false)
            SetMeshVisibility({ MagazineState.Model }, true)
            Actions:Unequip(HandState, WeaponState, HandModel, Handed,
                { CollisionEnabled = false, DestroyCurrentItem = true })
            local isMagEmpty = currentInMag <= 0
            local isMagGrabbedEmpty = MagazineState.LastMagazineGrabbedCapacity <= 0

            if isMagEmpty and isMagGrabbedEmpty and not PD3UserConfig.Settings["AutoChamber"] then
                setWeaponInventoryAmmo(attributeSet, newReserve)
                MagazineState.LastMagazineGrabbedCapacity = newMagTotal
                WeaponState.State = "Unloaded"
            elseif isMagEmpty and isMagGrabbedEmpty and PD3UserConfig.Settings["AutoChamber"] then
                resetEmptyCycle()
                setWeaponLoadedAmmo(attributeSet, newMagTotal)
                setWeaponInventoryAmmo(attributeSet, newReserve)
            elseif not (isMagEmpty and isMagGrabbedEmpty) or PD3UserConfig.Settings["AutoChamber"] then
                --cause emptycycle is initiated automatically and the VR player can't replicate it
                print("last")
                resetEmptyCycle()
                -- attributeSet:Multicast_SetEquippableAmmoInventoryLoaded(1, WeaponState.MagazineState.LastMagazineGrabbedCapacity, attributeSet.SecondaryEquippableAmmoInventory.CurrentValue)
                setWeaponLoadedAmmo(attributeSet, newMagTotal)
                setWeaponInventoryAmmo(attributeSet, newReserve)
                WeaponState.State = "Chambered"
            end

            resetEmptyCycle()
            MagazineState.LastGrabbedMag = 0
            print(newMagTotal, newReserve)
            MagazineState.State = ""
            WeaponAnimController.ApplyHandPose(HandModel, HandedString, "OriginalPose", WeaponState.Name)
        else
            -- Grab mag out of magwell

            if WeaponState.Model and MagazineState.Model then
                --    uevr.api:dispatch_custom_event("Restrict",serializeTable({ "GA_Fire", "GA_Reload", "SBZPlayerRunExitAbility" }, { true }))


                if MagazineState.State == "Gripped" then
                    attachments.detach(MagazineState.Model)
                    uevrUtils.executeUEVRCallbacks("on_accessory_detach", Handed)
                    HandState.IsAttached = false
                    handsAnimation.resetHandAnimations(Handed)
                    handsAnimation.setHoldingAttachment(Handed, false)

                end

                SetMeshVisibility({ MagazineState.Model }, false)

                Actions:Equip(WeaponState, HandState, HandModel, Handed,
                    { Pose = "ReloadPose", Prop = MagazineState.Model })

                -- Equip the PropMag
                WeaponState.State = "Unloaded"
                MagazineState.State = "Grabbed"
                HandState.CurrentAction = "HoldingMag"
                MagazineState.LastMagazineGrabbedCapacity = math.max(0,
                    attributeSet[WeaponState.Slot .. "EquippableAmmoLoaded"].CurrentValue)

                print('ammoloaded', pawn.CurrentEquippable.AmmoLoaded)
                if pawn.CurrentEquippable.AmmoLoaded > 0 then setWeaponLoadedAmmo(attributeSet, 1.0) end
            else     -- shotguns will need straight up a slug grab and an insert, Dynamic grab system?

            end
        end
    elseif ReloadType == "AutomaticEjection" then
        local PropMag = uevrUtils.createSkeletalMeshComponent(MagazineState.Model.SkeletalMesh, {
            parent = pawn,
            useDefaultPose = false
        })
        QueueForGC(PropMag)
        -- attrSet["Multicast_Set"..WeaponState.Slot.."EquippableAmmoLoaded"](1.0)

        SetMeshVisibility({ MagazineState.Model }, false)
        SetMeshVisibility({ PropMag }, true)
        PropMag:K2_SetWorldLocationAndRotation(MagazineState.Model:K2_GetComponentLocation(),
            MagazineState.Model:K2_GetComponentRotation(), false, reusable_hit_result, false)

        local downDir = kismet_math_library:NegateVector(kismet_math_library:GetUpVector(PropMag:K2_GetComponentRotation()))

        SetMeshCollision(PropMag, true)


        PropMag:AddImpulse(downDir * 300, uevrUtils.fname_from_string(""), true)
        MagazineState.State = "Dropped"
        WeaponState.State = "Unloaded"

        if pawn.CurrentEquippable.AmmoLoaded > 0 then
            setWeaponLoadedAmmo(attributeSet, 1.0)
        else
            print("set to 0")
            setWeaponLoadedAmmo(attributeSet, 0.0)
        end
        -- later stop it?
        -- after lerping it to said position
    end
    --end
end

function Actions:BoltWeapon(HandState, WeaponState, HandModel, HandedIndex, currentState, boltBone, boltType)
    local MagazineState = WeaponState.MagazineState
    if boltType == "Manual" and currentState == "Grab" then
        AttachHandAccurate(
            HandedIndex,
            ExperimentalModule.VRState.BaseModel,
            WeaponState.FakeModel,
            boltBone,
            { 0, 0, 0 },
            HandedIndexToString(HandedIndex),
            "PalmSurface"
        )
        handsAnimation.setAutoHandleInput(false)
        handsAnimation.handleInputForHands(GetLastState(), handsAnimation.getHoldingAttachment(Handed.Right),
            handsAnimation.getHoldingAttachment(HandedIndex),
            HandedIndex, false, true)

        handsAnimation.setHoldingAttachment(HandedIndex, true)

        HandState.IsAttached = true
        HandState.CurrentAction = "HoldingBolt"

        local forward = WeaponState.Model:GetForwardVector()
        local handleWorld = WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string(boltBone))
        local bodyWorld = WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string("Body"))
        local forward = WeaponState.Model:GetForwardVector()
        local handleLocal = (handleWorld.X * forward.X) + (handleWorld.Y * forward.Y) + (handleWorld.Z * forward.Z)
        local bodyLocal = (bodyWorld.X * forward.X) + (bodyWorld.Y * forward.Y) + (bodyWorld.Z * forward.Z)
        local travel = math.abs(handleLocal - bodyLocal)
        local maxX = handleWorld.X
        local minX = handleWorld.X - travel

        WeaponState.FakeModel:SetBoneLocationByName(uevrUtils.fname_from_string( boltBone),
            WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string(boltBone)))
        WeaponState.FakeModel:UnHideBoneByName(uevrUtils.fname_from_string(boltBone))
        local lastControllerPos = controllers.getControllerLocation(HandedIndex)

        SlidBackFully = false
        loopUntil("BoltTest", 80, function()
            local currentInMag = attributeSet[WeaponState.Slot .. "EquippableAmmoLoaded"].CurrentValue
            local controllerPos = controllers.getControllerLocation(HandedIndex)
            if lastControllerPos then
                local forward = WeaponState.Model:GetForwardVector()
                local worldDeltaX = controllerPos.X - lastControllerPos.X
                local worldDeltaY = controllerPos.Y - lastControllerPos.Y
                local worldDeltaZ = controllerPos.Z - lastControllerPos.Z
                local delta = (worldDeltaX * forward.X) + (worldDeltaY * forward.Y) + (worldDeltaZ * forward.Z)

                -- recalculate bounds every tick so moving the weapon doesn't drift the bolt
                local handleWorld = WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string(boltBone))
                local bodyWorld = WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string("Body"))
                local handleLocal = (handleWorld.X * forward.X) + (handleWorld.Y * forward.Y) +
                    (handleWorld.Z * forward.Z)
                local bodyLocal = (bodyWorld.X * forward.X) + (bodyWorld.Y * forward.Y) + (bodyWorld.Z * forward.Z)
                local travel = math.abs(handleLocal - bodyLocal)
                local position = WeaponState.FakeModel:GetSocketLocation(uevrUtils.fname_from_string(boltBone))
                local posLocal = (position.X * forward.X) + (position.Y * forward.Y) + (position.Z * forward.Z)
                local newLocal = math.max(handleLocal - travel, math.min(handleLocal, posLocal + delta))
                local diff = newLocal - posLocal
                local boltProgress = math.max(0, math.min(1, (handleLocal - posLocal) / travel))
                if boltProgress >= 0.9 then
                    SlidBackFully = true
                end

                if boltProgress <= 0 and (WeaponState.State == "Unloaded" and currentInMag == 0 or currentInMag == 0) and SlidBackFully then
                    resetEmptyCycle()
                    attributeSet["Multicast_Set" .. WeaponState.Slot .. "EquippableAmmoLoaded"](attributeSet,
                        WeaponState.MagazineState.LastMagazineGrabbedCapacity)
                    MagazineState.LastMagazineGrabbedCapacity = 0
                    print("bolt thing")
                    WeaponState.State = "Loaded"
                elseif boltProgress <= 0 and currentInMag >= 0 and SlidBackFully then
                    WeaponState.State = "Loaded"
                elseif boltProgress >= 0.8 and WeaponState.State ~= "Unloaded" and currentInMag >= 1 then
                    WeaponState.State = "Unloaded"
                    SlidBackFully = true
                    for i, v in pairs(WeaponState.Parts) do
                        if v and v:get_full_name():find("Ammo") then
                            local newBullet = uevrUtils.createStaticMeshComponent(v)
                            local shellLoc = WeaponState.Model:GetSocketLocation(uevrUtils.fname_from_string("L_Shell"))
                            local shellRot = WeaponState.Model:GetSocketRotation(uevrUtils.fname_from_string("L_Shell"))
                            local meshProxy = SetMeshCollision(newBullet, true)

                            newBullet:K2_SetWorldLocation(shellLoc, false, reusable_hit_result, false)
                            meshProxy:AddImpulse(uevrUtils.getForwardVector(shellRot) * 250, "", true)

                            QueueForGC(newBullet)
                            ScheduleActorDespawn(meshProxy, 15, "None")
                            attributeSet["Multicast_Set" .. WeaponState.Slot .. "EquippableAmmoLoaded"]
                            (attributeSet, currentInMag - 1 == 0 and 0 or currentInMag - 1)
                        end
                    end
                end
                ---------
                WeaponState.FakeModel:SetBoneLocationByName(
                    uevrUtils.fname_from_string(boltBone),
                    uevrUtils.vector_3f(
                        position.X + forward.X * diff,
                        position.Y + forward.Y * diff,
                        position.Z + forward.Z * diff))
            end
            -- Set offset of the connection so that it updates fast
            lastControllerPos = controllers.getControllerLocation(HandedIndex)
        end)
    elseif currentState == "Drop" then
        if SlidBackFully then
            if WeaponState.State == "Unloaded" and MagazineState.LastMagazineGrabbedCapacity > 0 then
                resetEmptyCycle()
                print("unbolting?")
                attributeSet["Multicast_Set" .. WeaponState.Slot .. "EquippableAmmoLoaded"](attributeSet,
                    MagazineState.LastMagazineGrabbedCapacity)
                MagazineState.LastMagazineGrabbedCapacity = 0
                WeaponState.State = "Loaded"
            else
                WeaponState.State = "Loaded"
            end
        end
        SlidBackFully = false
        WeaponState.FakeModel:UnHideBoneByName(uevrUtils.fname_from_string(boltBone))
        WeaponState.FakeModel:SetBoneLocationByName(
            uevrUtils.fname_from_string(boltBone),
            WeaponState.Model:GetSocketLocation(
                uevrUtils.fname_from_string(boltBone)))
        uevrUtils.destroyDeferral("BoltTest")

        Actions:Unequip(HandState, WeaponState, HandModel, HandedIndex)

        handsAnimation.setAutoHandleInput(true)
        handsAnimation.setHoldingAttachment(HandedIndex, false)
        
    end
end

-- Handles equipping a  weapon or  a prop
function Actions:Equip(WeaponState, HandState, HandModel, Handed, settings)
    settings               = settings or {}
    WeaponState =             WeaponState or {}
    local Prop             = settings.Prop
    local PropName =         settings.PropName
    local Pose             = settings.Pose or "GripPose"
    local CollisionEnabled = settings.CollisionEnabled or false
    local KeepRotation     = settings.KeepRotation and 1 or 2
    local useOriginalProp  = settings.UseOriginalProp or false
    -- if not  PD3UserConfig.Settings["isCalibrating"] then
    newProp                = nil
    local MagazineState    = WeaponState and WeaponState.MagazineState
    local HandedName       = HandedIndexToString(Handed)
    resetEmptyCycle()
    if not Prop then     -- Weapon meshs hould already be attached
        WeaponAnimController.ApplyHandPose(HandModel, HandedName, Pose, WeaponState.Name)
        HandState.CurrentAction = "HoldingWeapon"
        SetMeshVisibility({ pawn.CurrentEquippable.Mesh }, true)
        WeaponState.MagazineState.LastMagazineGrabbedCapacity = 0
        RestrictAbilities(true)
        -- Switch to secondary/primary
    elseif Prop then
        if not useOriginalProp then
          local propType = Prop:get_class():get_fname():to_string()
          print(propType)
          if propType:find("StaticMeshComponent") then
            local mesh
            local IsAsset = Prop.StaticMesh:get_class():get_fname():to_string() == "StaticMesh"
            if IsAsset then mesh =  Prop.StaticMesh  else mesh = Prop.StaticMesh.StaticMesh end
              newProp = uevrUtils.createStaticMeshComponent(mesh, {
                parent = pawn,
                useDefaultPose = false
            })
            
          elseif propType:find("SkeletalMeshComponent") or propType:find("PoseableMeshComponent")  then
 
              newProp = uevrUtils.createSkeletalMeshComponent(Prop.SkeletalMesh, {
                parent = pawn,
                useDefaultPose = false
            })
                    newProp:K2_SetWorldLocationAndRotation(Prop:K2_GetComponentLocation(),
            Prop:K2_GetComponentRotation(), false, reusable_hit_result, false)
          end
        else
            newProp = Prop
        end
        QueueForGC(newProp)


        if CollisionEnabled then SetMeshCollision(newProp, true) end

        -- lefthandweapon bone already flips the mag up so all we need is to get the depth of the palm and correct the relative Y offset
        SetMeshVisibility({ newProp }, true)
      --  newProp:K2_DetachFromComponent(0)
        newProp:K2_AttachToComponent(
            HandModel,
            uevrUtils.fname_from_string(HandedName .. "Weapon"),
            2,
            KeepRotation,
            1,
            true
        )

        -- as a last resort, put it in lefthandinmiddle, calculate delta from prop pos to the other hand thats in the calcpalm equation and bom
        -- just give mags nudges I really don't care at this point I've tried every feasible solution, unkless theres some FOV offset
        -- Temporary until I have time to create AttachToHandAccurate
        -- this pushes it forward because elfthandweapon is buried
        --newProp.RelativeLocation.Y = 3
        if PD3UserConfig.Settings["PreferredHand"] == 0 then
            newProp.RelativeLocation.Y = -3
            newProp.RelativeLocation.Z = -3
        else
            newProp.RelativeLocation.Z = 3
            newProp.RelativeLocation.Y = 2
        end

        
    end

    handsAnimation.setHoldingAttachment(Handed, true)
    WeaponAnimController.ApplyHandPose(HandModel, HandedName, Pose, WeaponState and WeaponState.Name or PropName)
    HandState.CurrentItem = newProp or WeaponState.Model
    -- print("set to ", HandState.CurrentItem, newProp, WeaponState.Model)
    -- end
end

-- unequipping a prop/weapon and resetting weaponstate
function Actions:Unequip(HandState, WeaponState, VRHandModel, Handed, settings)
    settings                 = settings or {}
    WeaponState =             WeaponState or {}
    local CurrentPose        = settings.Pose or "GripPose"
    local propName =            settings.PropName
    local CollisionEnabled   = settings.CollisionEnabled or false
    local DestroyCurrentItem = settings.DestroyCurrentItem or false
    local HandedName         = HandedIndexToString(Handed)
    local MagazineState      = WeaponState and WeaponState.MagazineState or nil

    if WeaponState and HandState.CurrentItem == WeaponState.Model and Handed == PD3UserConfig.Settings["PreferredHand"] then
        WeaponState.State = ""
        --MagazineState.State = ""
        SetMeshVisibility({ ExperimentalModule.Weapons.Current }, false)
        if uevrUtils.getValid(VRHandModel) then
            WeaponAnimController.ApplyHandPose(VRHandModel, HandedName,
                "OriginalPose", WeaponState.Name or propName)
        end

        ExperimentalModule.Weapons.Current = nil
        RestrictAbilities(false)

        HandState.CurrentItem = nil
        HandState.IsAttached = false
        HandState.CurrentAction = ""

        uevrUtils.executeUEVRCallbacks("on_accessory_detach", Handed)
    elseif HandState.CurrentItem or HandState.IsAttached then     -- prop
        uevrUtils.executeUEVRCallbacks("on_accessory_detach", Handed)
        if DestroyCurrentItem then
            HandState.CurrentItem:K2_DetachFromComponent(0)
            HandState.CurrentItem:K2_DestroyComponent()
        end
        if HandState.CurrentItem and CollisionEnabled then
            local isProxy =  SetMeshCollision(HandState.CurrentItem, true)
            local inheritedVelocity = GetControllerVelocity(Handed)
            -- proxy gets attached to a sphere so detaching it here will freeze it in place
            if not isProxy then 
                attachments.detach(HandState.CurrentItem, nil, nil, nil, true, true) 
               HandState.CurrentItem:AddImpulse(inheritedVelocity, uevrUtils.fname_from_string(""), false)
            else
            HandState.CurrentItem.AttachParent:AddImpulse(inheritedVelocity, uevrUtils.fname_from_string(""), false)
             end
        end
        HandState.CurrentItem = nil
        HandState.IsAttached = false
        HandState.CurrentAction = ""
        WeaponAnimController.ApplyHandPose(VRHandModel, HandedName, "OriginalPose",
            WeaponState and WeaponState.Name or CurrentPose)
    end
    handsAnimation.resetHandAnimations(Handed)
    handsAnimation.setHoldingAttachment(Handed, false)
    -- hide weapon
end
function Actions:ActivatePhone(type)
    if type == "RequestOVKWeapon" then
uevr.api:dispatch_custom_event("ToolInput", "gadget")
    elseif type == "ActivateTool" then

uevr.api:dispatch_custom_event("ToolInput", "tool")

    end
end
function Actions:ActivateThrowable(throwableConfig,ASBZThrowable)
    local preferredAimMode = PD3UserConfig.Settings["PreferredAimMode"]
    local dir,inheritedVelocity
    print(preferredAimMode)
    -- If preferred aim mode is right weapon or left weapon
        if preferredAimMode == 1 then preferredAimMode = nil end -- UEVR aim mode, dont modify any direction 
    if preferredAimMode == 5 or preferredAimMode == 6 or preferredAimMode == 4 or preferredAimMode == 3 then preferredAimMode = ExperimentalModule.VRState.SecondaryHandIndex end

print(preferredAimMode,"aimmode st")
if preferredAimMode then
 dir = GetControllerVelocity(preferredAimMode)

print(dir.X,dir.Y)
--dir = uevrUtils.vector_2(math.abs(dir.X),math.abs(dir.Y))
--if ASBZThrowable and ASBZThrowable.ProjectileMovementComponent then ASBZThrowable.ProjectileMovementComponent.InitialSpeed = dir*2 else return end
end

if not throwableConfig.IsPin then
     uevr.api:dispatch_custom_event("ActivateAbility", "GA_ThrowItem_C")
uevr.api:dispatch_custom_event("ThrowReleaseNative", tostring(dir.X)..","..tostring(dir.Y)..","..tostring(dir.Z)) 
 
end

   -- ASBZThrowable.Multicast_SetThrowDirection(dir);
	--ASBZThrowable.Multicast_SetThrowState(ESBZThrowableState NewThrowState);
end
function Actions:Melee()
    uevr.api:dispatch_custom_event("ActivateAbility", "GA_Melee")
end

-- Gameplay abilities activation C++ can only crouch and not uncrouch
function Actions:SetCrouching(IsCrouching)
    pawn.CharacterMovement.bWantsToCrouch = IsCrouching
end

function Actions:Jump()
    -- two methods here, either call GAS via C++ or just call pawn:Jump()
    pawn:Jump()
end


-- WIP
--isGrabbingSlots = false
-- Does not use handstate, this is currently for slot placements but may change/adapt
--[[function Actions:GrabSlots(VRState, grabbedObject, otherObject, handed, State)
        -- Attach to controller, not hand
        isGrabbingSlots = State
        if isGrabbingSlots then
            controllers.attachComponentToController(handed, grabbedObject, "", 1, true, false)
            otherObject:K2_AttachToComponent(grabbedObject, "", 2, 1, 1, true)
            loopUntil("SlotDistance", 200, function()
                if isGrabbingSlots then
                    otherObject.RelativeLocation.X = PD3UserConfig.Settings["DistanceBetweenSlots"] * 10
                else
                    return false
                end
            end)
        else
            local handedString = handed == 0 and "Right" or "Left"
            local oppositeHandedString = handed == 0 and "Left" or "Right"
            otherObject:K2_DetachFromComponent(1) -- detach from grabbedObject while it's still in controller space
            grabbedObject:K2_DetachFromComponent(1) -- now detach grabbedObject from controller

            for i, v in pairs(VRState.HolsterSlots) do
                local side = i == "secondary" and handedString .. "UpLeg" or oppositeHandedString .. "UpLeg"
                v:K2_AttachToComponent(VRState, uevrUtils.fname_from_string(side), 2, 1, 1, true)
                local yOffset = i == "Secondary" and 15.0 or -15.0
                v:K2_SetRelativeLocation(
                    uevrUtils.vector_3f(yOffset, -yOffset / 2, 0.0),
                    false, reusable_hit_result, false
                )
            end
            otherObject.RelativeLocation.X = PD3UserConfig.Settings["DistanceBetweenSlots"] * 10
        end
    end]]

return Actions
