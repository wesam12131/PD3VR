local NativeModule = {}
local uevrUtils = require("libs/uevr_utils")
local animation = require('libs/animation')
local controllers = require('libs/controllers')
local attachments = require("libs/attachments")
local hands = require('libs/hands')
local PD3UserSettings = require("libs/config/PD3UserConfig")
local uevrLib = require("libs/core/uevr_lib")
local input = require("libs/input")
local kismet_math_library = uevrLib.find_default_instance("Class /Script/Engine.KismetMathLibrary") ---@type UKismetMathLibrary

local function updateDynamicWeaponOffset(hand, handMesh, weapon, boneSearchName)
    if handMesh == nil or weapon == nil then return end

    local boneFName = animation.findBoneFName(handMesh, boneSearchName)
    if boneFName == nil then return end

    local boneWorldPos = handMesh:GetSocketLocation(boneFName)
    local boneWorldRotRaw = handMesh:GetSocketQuaternion(boneFName)
    if boneWorldPos == nil or boneWorldRotRaw == nil then return end
    local boneWorldRot = uevrUtils.quat(boneWorldRotRaw.X, boneWorldRotRaw.Y, boneWorldRotRaw.Z, boneWorldRotRaw.W)

    local controllerIndex = (hand == Handed.Left) and 0 or 1
    local controllerPos = controllers.getControllerLocation(controllerIndex)
    local controllerRotator = controllers.getControllerRotation(controllerIndex)
    if controllerPos == nil or controllerRotator == nil then return end
    local controllerRotQuat = uevrUtils.quatFromRotator(controllerRotator.Pitch, controllerRotator.Yaw,
        controllerRotator.Roll)
    local invControllerRot = kismet_math_library:Quat_Inversed(controllerRotQuat)
    local relativePos = kismet_math_library:Quat_RotateVector(invControllerRot, boneWorldPos - controllerPos)
    local relativeRot = kismet_math_library:Multiply_QuatQuat(invControllerRot, boneWorldRot)
    local relativeRotator = kismet_math_library:Quat_Rotator(relativeRot)

    attachments.setAttachmentOffset(
        attachments.getActiveAttachmentID(hand),
        { relativePos.x, relativePos.y, relativePos.z },
        { relativeRotator.Pitch, relativeRotator.Yaw, relativeRotator.Roll }
    )
end
local function SetBodyVisibility(Body, hide)
    if Body.SetHiddenInGame then Body:SetHiddenInGame(hide or false, true) end
    --Body.bNeverDistanceCull = true
    Body:SetOnlyOwnerSee(false)
    Body:SetRenderInMainPass(true)
    Body:SetRenderInTopPass(false)
    Body:SetOwnerNoSee(false)
    if Body.SetVisibility then Body:SetVisibility(not hide or false, true) end
end

function NativeModule.ActivateNativeMode(pawn)
    local weapon = pawn.CurrentEquippable.Mesh
    SetBodyVisibility(weapon)
    SetBodyVisibility(pawn.Mesh1PGloves)
      SetBodyVisibility(pawn.Mesh1PBody)
    SetBodyVisibility(pawn.Mesh1PSuit)
     SetBodyVisibility(pawn.Mesh1P)
           local isTwoHanded = PD3UserSettings.Settings["PreferredAimMode"]
        local HandIndex =  PD3UserSettings.Settings["PreferredHand"]
             input.setBodyYawWritesSuppressed(true)
        input.setPlayerControllerRotationFollowsBody(true)
    attachments.registerOnGripUpdateCallback(function()
  
        local HandGripBone = PD3UserSettings.PreferredHandTypes[HandIndex].."Weapon"

        updateDynamicWeaponOffset(HandIndex, pawn.Mesh1P, weapon, HandGripBone)

        -- if its two handed aim mode then the mode already sets the left hand weapon to control and setting it twice makes it weird and  buggy
        -- 4 is Right controlled two handed, 5 is left controlled two handed
     
            --  1 is Right Controller,  0 is Left Controller
        if isTwoHanded == 0 or isTwoHanded == 2 or isTwoHanded == 3 then
             updateDynamicWeaponOffset(HandIndex, pawn.Mesh1P, weapon, HandGripBone)
            local oppositeHandIndex = HandIndex == Handed.Right and Handed.Left or Handed.Right
            print(oppositeHandIndex,HandIndex)
            return weapon, controllers.getController(Handed.Right),nil,weapon,controllers.getController(Handed.Left)
         --  return weapon, controllers.getController(HandIndex), nil, weapon, controllers.getController(oppositeHandIndex),
               --nil
        end
    end)
end

return NativeModule