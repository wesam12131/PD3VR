WeaponAnimationController = {}

local uevrUtils = require("libs/uevr_utils")
local animation = require('libs/animation')
local PD3Utility = require("PD3Utility")

local DefaultHandsTable = {
    ["PrimaryHand"] = {
        CurrentObjectName = "", -- in the json file, this wraps all of the table, then in lua it is unpacked to DefaultHandsTable's form
        Animations = {
            ["GripPose"] = {},
            ["ReloadPose"] = {},
            ["FirePose"] = {},
            ["OriginalPose"] = {},
        },
        ActivePose = "",
        CustomLocations = nil,
        IsPoseRecorded = false,
        IsActive = false -- ehh why do is active if activepose could be "" or OriginalPose

    },
    ["SecondaryHand"] = {
        CurrentObjectName = "",
        Animations = {
            ["GripPose"] = {},
            ["ReloadPose"] = {},
            ["FirePose"] = {},
            ["OriginalPose"] = {},
        },

        ActivePose = "",
        CustomLocations = nil,
        IsPoseRecorded = false,
        IsActive = false -- ehh why do is active if activepose could be "" or OriginalPose
    },
    GeneralAnimations = {

        ["PhoneGripPose"] = {},
    }
}

local isdevMode = false -- turn on to disable reading from a file, writing is unaffected but easily changeable

local HandAnimations = uevrUtils.deepCopyTable(DefaultHandsTable)
local pawn = uevrUtils.get_local_pawn()

local VRState = nil
local VRHandModel = nil
local OriginalHandModel = nil
local VRHandModelBones = nil

local hands = { "PrimaryHand", "SecondaryHand" }
local configfileName = "PD3AnimationInfo.json"
-- I do not know how to take an animation from the actual gloves mesh so I just copy movement once after experiment activation and apply it, boom
-- should probably try to record gunfire rotations and apply it dynamically as your setting to not have the user wait 1 shot before the hands animate the trigger
--[[
        The following function  does:
        -- Checks if we have a previous config containing weaponName and under it would be animation data
        -- If not, then:
        -- Initiate an intial reload so we can record its rotations
        -- check pawn.ReplicatedReloadState for Assault rifles cause pistols are handled differently
        -- it gives off an approximate animation which I'm fine with instead of hand animating tons of weapons
        -- record it then and store it in the config, the config is seperate from the HandAnimation table
        -- HandAnimation only takes the .Animation and other minor stuff from the Config
        -- Config's layout is {"Pistol_SE5" = DefaultHandsTable }

        ]]
-- TBD: Add exclusion for shotguns or record the bulletgrabs
-- there are SBZPostAKNotifies like SBZPostAKEventNotify /Game/DLCs/00080-DLC0004/Gameplay/Animations/Animation/Player/FP/Pistols/JKSE/Animations/AM_PLR_Cbt_JKSE_Std_Reload_FP_01.AM_PLR_Cbt_JKSE_Std_Reload_FP_01:SBZPostAKEventNotify_1
-- that contain actual data, use them instead of reload and merge both reload paths into one
-- to be done later
local function loadConfig(objectName)
    loadedConfig = json.load_file(configfileName) or nil
    if loadedConfig and loadedConfig[objectName] then
        -- Insert general animations into their table AND copy their poses into the hand animations
        --  it is intended that these are only inserted on runtime to hands and removed on save
        for _, hand in ipairs(hands) do
            for i, _ in pairs(HandAnimations[hand].Animations) do
                if not loadedConfig[objectName][hand].Animations then loadedConfig[objectName][hand].Animations = {} end
                if not loadedConfig[objectName][hand].Animations[i] or loadedConfig[objectName][hand].Animations[i] == "Empty" then
                    loadedConfig[objectName][hand].Animations[i] = {}
                end
            end

            HandAnimations[hand].Animations = loadedConfig[objectName][hand].Animations

            HandAnimations[hand].CurrentObjectName = objectName
        end
        if loadedConfig["GeneralAnimations"] then
            for i, _ in pairs(HandAnimations.GeneralAnimations) do
                if not loadedConfig["GeneralAnimations"][i] or loadedConfig["GeneralAnimations"][i] == "Empty" then
                    loadedConfig["GeneralAnimations"][i] = {}
                end
            end
            for i, v in pairs(loadedConfig["GeneralAnimations"]) do
                HandAnimations.GeneralAnimations[i] = v
                HandAnimations["SecondaryHand"].Animations[i] = v
            end
        end

        return true
    end
end

function WeaponAnimationController.FindPoseInConfig(name)
    loadedConfig = json.load_file(configfileName)

    if loadedConfig and loadedConfig["GeneralAnimations"] and loadedConfig["GeneralAnimations"][name] and loadedConfig["GeneralAnimations"][name] ~= "Empty" and next(loadedConfig["GeneralAnimations"][name]) ~= nil then return true end
    if loadedConfig and loadedConfig[name] and loadedConfig[name] ~= "Empty" then return true else return false end
end

function WeaponAnimationController.calibrateHandAnimation(HandModel, Slot, PreferredHandName, SecondaryHandName,
                                                          ObjectName, callback)
    print("PreferredHandName:", PreferredHandName, "SecondaryHandName:", SecondaryHandName)
    -- Speed up regular animations
    --[[    uevr.sdk.callbacks.on_pre_engine_tick(function()
            local current = pawn.CurrentEquippableIndex
            if current ~= lastEquippableIndex then
                lastEquippableIndex = current
                local montage = pawn:GetCurrentMontage()
                if montage and (montage:get_full_name():find("Equip") or montage:get_full_name():find("Reload")) then
                    montage:SetPlayRate(100.0)
                end
            end
        end)]]

    if uevrUtils.getValid(pawn) then -- else retry
        local AnimInstance  = pawn.Mesh1P:GetAnimInstance()
        local isCheckActive = true

        -- revolvers and other weapons that don't track using this are for now unsupported
        local meshes        = {
            -- pawn.CurrentEquippable.Mesh,
            pawn.Mesh1P
        }

        -- calibrate holding animations for both hands for the
        if Slot == "Secondary" then -- temp
            -- Save grip poses
            WeaponAnimationController.ApplyHandPose(HandModel, PreferredHandName, "GripPose", ObjectName, true)
            WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName, "GripPose", ObjectName, true)
            local isfound = false
            local animInstance, montage
            uevr.sdk.callbacks.on_post_engine_tick(function()
                if not pawn.CurrentEquippable then return end

                animInstance = pawn.Mesh1P:GetAnimInstance()
                if animInstance then
                    montage = animInstance:GetCurrentActiveMontage()

                    if montage and montage.get_full_name and montage:get_full_name():find("Reload") and not isfound then
                        if animInstance:Montage_GetCurrentSection():to_string():find("Insert") then
                            WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName, "ReloadPose",
                                ObjectName, true)
                            isfound = true
                        end
                    end
                end
            end)
        elseif Slot == "Primary" or Slot == "Overkill" then
            WeaponAnimationController.ApplyHandPose(HandModel, PreferredHandName, "GripPose", ObjectName, true)
            WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName, "GripPose", ObjectName, true)
            local reloadArray = (pawn.ReplicatedReloadState and pawn.ReplicatedReloadState.Array and pawn.ReplicatedReloadState.Array.State) and
                pawn.ReplicatedReloadState.Array or nil
            local function trackReload()
                --uevr.api:dispatch_custom_event("GetInsertMagTime", "Reload|Insert Ammo")
                if isCheckActive then
                    -- if family is like an AR or non pistol/non revolver/ non shotgun
                    if (reloadArray.State == 2 or reloadArray.State == 3) and HandModel then -- RemoveMagazine
                        WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName,
                            "ReloadPose", ObjectName, true)
                        callback()
                        isCheckActive = false
                        -- uevr.api:dispatch_custom_event("ActivateAbility", "GA_Reload_Cancel")
                    end
                else
                    return -- check isn't active
                end
            end

            if Slot ~= "Overkill" then uevr.sdk.callbacks.on_post_engine_tick(trackReload) else return true end -- use post until you investigate on_pre_engine_tick
        elseif Slot == "Phone" then
            local isEquipped = false
            local animInstance = pawn.Mesh1P:GetAnimInstance()
            local phoneEquipMontage
            loopUntil("RestrictAfterEquip2", 100, function()
                local montage = animInstance:GetCurrentActiveMontage()
                if montage then
                    local name = montage:get_full_name()

                    if name:find("Phone") and name:find("Unequip") and not phoneEquipMontage then
                        phoneEquipMontage =
                            montage
                    end

                    if phoneEquipMontage and not animInstance:Montage_IsPlaying(phoneEquipMontage) then
                        print("phone montahe finshied")
                        WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName,
                            "PhoneGripPose", ObjectName, true)
                        print("calibrated!")
                        callback()
                        return false
                    end
                end
            end)
            uevr.api:dispatch_custom_event("PhoneWidgetTap", "")
        elseif Slot == "Throwable" then
            local animInstance = pawn.Mesh1P:GetAnimInstance()
            local throwableEquipMontage
            loopUntil("RestrictAfterEquip32", 100, function()
                local montage = animInstance:GetCurrentActiveMontage()


                if throwableEquipMontage and not animInstance:Montage_IsPlaying(throwableEquipMontage) then
                    WeaponAnimationController.ApplyHandPose(HandModel, SecondaryHandName,
                        "GripPose", ObjectName, true)
                          uevr.api:dispatch_custom_event("CancelAbility", "GA_ThrowItem_C")
                    callback()
                    return false
                end
                if montage then
                    local name = montage:get_full_name()
                    print(name)
                    -- don't ask me why starbreeze named it like this, I wanted it to be automated but can't risk
                    -- equip animation for gun being a literal gun, maybe later if i am sure that
                    -- only X animation runs at once
                    -- Animation for throwing knives is  ThrowingKnifeEquip
                    -- Spherical_Std_Equip_ for grenades
                    -- CylinderS_Std_Equip for flashbangs
                    -- Cylinder_Std_Equip for shockwave
                    if (name:find("Spherical") or name:find("Cylinder") or name:find("ThrowingKnife")) and name:find("Equip") and not throwableEquipMontage then
                        throwableEquipMontage = montage
                    end
                end
            end)
            uevr.api:dispatch_custom_event("ActivateAbility", "GA_ThrowItem_C")
        end


        -- If we are calibrating weapons, initiate their reloads so functions above can catch the animation
        if Slot == "Secondary" or Slot == "Primary" then uevr.api:dispatch_custom_event("ActivateAbility", "GA_Reload_C") end
    end
end

-- Dominant hand, Secondary hand, Primary weapon name, secondary weapon name, throwable
function WeaponAnimationController.Init(state, PreferredHandName, SecondaryHandName, PrimaryName, SecondaryName,
                                        ThrowableName)
    VRState = state

    local HandModel = VRState.HandModel
    -- checks and loads at the same time
    local isPrimaryCalibrated = not isdevMode and WeaponAnimationController.FindPoseInConfig(PrimaryName)
    local isSecondaryCalibrated = not isdevMode and WeaponAnimationController.FindPoseInConfig(SecondaryName)
    local isPhoneCalibrated = not isdevMode and WeaponAnimationController.FindPoseInConfig("PhoneGripPose")
    local isThrowableCalibrated = not isdevMode and WeaponAnimationController.FindPoseInConfig(ThrowableName)
    local isPrimaryCalibrating = false
local namesTable = {PrimaryName, SecondaryName, "PhoneGripPose", ThrowableName}
local calibrationTable = {isPrimaryCalibrated, isSecondaryCalibrated, isPhoneCalibrated, isThrowableCalibrated}


    

for index, name in ipairs(namesTable) do
local isCalibrated =  calibrationTable[index]
    if not isCalibrated then
        local isSecondaryOnly = name == "PhoneGripPose" or name == ThrowableName
        for _, handName in pairs({PreferredHandName, SecondaryHandName}) do
            if handName == SecondaryHandName and isSecondaryOnly then
                 -- Only secondary hand needs original pose here 
                 WeaponAnimationController.ApplyHandPose(HandModel, handName, "OriginalPose", name, true, HandModel)
            elseif  not isSecondaryOnly then
            WeaponAnimationController.ApplyHandPose(HandModel, handName, "OriginalPose", name, true, HandModel)
            end
        end
    end

end
    if not isThrowableCalibrated then
        -- Activate the throwing ability but switch to primary after calibration to immediately cancel it
        print("calibrating throwable")
        WeaponAnimationController.calibrateHandAnimation(HandModel, "Throwable", PreferredHandName, SecondaryHandName,
            ThrowableName, function()
                print("calibrated throwable")
            end)
    
    end
    -- To avoid calling Equip secondary weapon the same time as Equip  primary, create a deferral
    if not isPhoneCalibrated then
        WeaponAnimationController.calibrateHandAnimation(HandModel, "Phone", PreferredHandName, SecondaryHandName,
            "PhoneGripPose", function()
                print("calibrated phone")
            end)
    end
    if not isPrimaryCalibrated or isdevMode then
        isPrimaryCalibrating = true
        uevr.api:dispatch_custom_event("ActivateAbility", "GA_EquipPrimaryWeapon")
        uevrUtils.delay(2000, function()
            WeaponAnimationController.calibrateHandAnimation(HandModel, "Primary", PreferredHandName, SecondaryHandName,
                PrimaryName, function()
                end)
            uevrUtils.delay(2000, function()
                isPrimaryCalibrating = false
                uevrUtils.updateDeferral("ObjectCalibration")
            end)
        end)
    else
        loadConfig(PrimaryName)
    end


    uevrUtils.createDeferral("ObjectCalibration", 200, function()
        if not isPrimaryCalibrating then
            if not isSecondaryCalibrated or isdevMode then
                uevr.api:dispatch_custom_event("ActivateAbility", "GA_EquipSecondaryWeapon")
                uevrUtils.delay(2000, function()
                    local isDone = WeaponAnimationController.calibrateHandAnimation(HandModel, "Secondary",
                        PreferredHandName,
                        SecondaryHandName, SecondaryName)
                    if isDone then uevrUtils.destroyDeferral("ObjectCalibration") end
                end)
            else
                loadConfig(SecondaryName)
            end
        end
    end)
    if not isPrimaryCalibrating then uevrUtils.updateDeferral("ObjectCalibration") end
end

-- TODO: Overhaul this to play the anims on the actual mesh then stop at X keyframe,  animInstance:Montage_SetPlayRate(montage, 100.0)
-- TBD: Transform this function to include leg bones and generalize the function
--  M.updateAnimationFromMesh_Native exists smh, suppose this serves as extended functionality
-- mostly storage, custom locations, recording it  for later cause
-- the equip anim needs a bit to stand stable
-- Handmodel is the VR basemodel, (Required)
--
-- Pose is so that the function can apply a pre existing stored pose (Optional)
--
-- objectName is a string that defines data for animation config for X weapon like Pistol_SE5 = {RightHand = {Animations = {GripPose = {}},LeftHand = ...}}
--
-- RecordOnly is to pre record stuff so record not apply
--
--Handed is the side of the hand (left/right) (Optional, reverts to both hands if none)
--
-- CustomPoseBones is if you need to only modify specific bones (Optional)
--
-- CustomLocations are locations for the CustomPoseBones (must be set in order so if ABC bone is first, CustomLocation's first index should refer to ABC bone location) (Optional)
function WeaponAnimationController.ApplyHandPose(VRHand, Handed, Pose, objectName, RecordOnly, OriginalGlove,
                                                 CustomPoseBones, CustomLocations)
    if not VRHandModel then VRHandModel = VRHand end
    if not VRHandModelBones then VRHandModelBones = animation.getCachedBoneNames(VRHandModel) end
    local OriginalHandModel = OriginalGlove or pawn.Mesh1PGloves
    local Handed = Handed:find("Right") and "Right" or "Left"
    local isObjectCalibrated = WeaponAnimationController.FindPoseInConfig(objectName)
    local handedSlot

    if HandedIndexToString(VRState.PrimaryHandIndex):find(Handed) then
        handedSlot = "PrimaryHand"
    elseif HandedIndexToString(VRState.SecondaryHandIndex):find(Handed) then
        handedSlot = "SecondaryHand"
    end
    local HandAnimTable = HandAnimations[handedSlot]
    if objectName and HandAnimTable.CurrentObjectName ~= objectName and not isdevMode and isObjectCalibrated then
        loadConfig(objectName)
    end
    print(handedSlot, Pose, objectName, HandAnimTable.CurrentObjectName)
    local PoseRecordSource = Handed
    local IsPoseRecorded = HandAnimTable.Animations[Pose] and next(HandAnimTable.Animations[Pose]) ~= nil or false
    local isOriginalRecorded = next(HandAnimTable.Animations["OriginalPose"]) ~= nil
    local BonesToModify = CustomPoseBones or { "Index", "Thumb", "Pinky", "Middle", "Ring", "Flexor", "Extensor" }
    local MappedBones = {}





    if not IsPoseRecorded then
        for i, ModelBoneName in ipairs(VRHandModelBones) do
            for _, ModifiableBone in pairs(BonesToModify) do
                if ModelBoneName:find(ModifiableBone) and (Handed and ModelBoneName:find(PoseRecordSource)) then
                    local OriginalBoneName = animation.findBoneFName(OriginalHandModel, ModelBoneName)

                    local parentBoneName = animation.FindBoneParentFromCache(OriginalHandModel, OriginalBoneName)

                    local parentRotAtCapture = OriginalHandModel:GetSocketRotation(parentBoneName)
                    local fingerRotAtCapture = OriginalHandModel:GetSocketRotation(OriginalBoneName)

                    local parentQuat = quatFromRotatorVec(parentRotAtCapture)
                    local fingerQuat = quatFromRotatorVec(fingerRotAtCapture)
                    local deltaQuat = quatMultiply(quatConjugate(parentQuat), fingerQuat)
                    --   print(ModelBoneName,OriginalBoneName,ModifiableBone, ModelBoneName:find(ModifiableBone),(Handed and ModelBoneName:find(Handed)),Handed)

                    local normalizedBoneName = stripSuffix(animation.findBoneFName(VRHandModel, ModelBoneName):to_string())
                        :gsub("^Right", ""):gsub("^Left", "")
                    local normalizedParentName = stripSuffix(parentBoneName):to_string():gsub("^Right", ""):gsub("^Left",
                        "")
                    MappedBones[normalizedBoneName] = { normalizedParentName, deltaQuat }
                end
            end
        end
    else -- pose is recorded
        MappedBones = HandAnimTable.Animations[Pose]
    end

    HandAnimTable.CustomLocations = CustomLocations
    HandAnimTable.IsPoseRecorded = IsPoseRecorded
    HandAnimTable.RecordOnly = RecordOnly
    HandAnimTable.ActivePose = Pose
    HandAnimTable.Animations[Pose] = MappedBones
    HandAnimTable.IsActive = true

    
    if objectName and not isObjectCalibrated then
        --print("SAVING POSE:", handedSlot, Pose, objectName, MappedBones)
        WeaponAnimationController.SaveCalibratedPose(handedSlot, Pose,
            objectName, MappedBones)
    end
end

uevrUtils.setInterval(200,
    function() --match the tick IK/animation.lua uses, don't desync it otherwise hands would be wobbling
        if uevrUtils.getValid(pawn) and uevrUtils.getValid(pawn.Mesh1P) and VRState then
            for name, handTable in pairs(HandAnimations) do
                if name ~= "GeneralAnimations" then
                    -- Swap them out incase primary hand is left hand


                    if VRHandModel and handTable.IsActive or handTable.CustomLocations then
                        --  print(handTable,name,next(handTable.Animations[handTable.ActivePose]))
                        --  if  handTable.IsPoseRecorded then handTable.Animations[handTable.ActivePose] = RecordedActions[handTable.ActivePose] elseif  handTable.ActivePose and not RecordedActions[handTable.ActivePose] then RecordedActions[handTable.ActivePose] = {} print("reset")  end

                        if not handTable.CustomLocations then
                            for NewBoneName, data in pairs(handTable.Animations[handTable.ActivePose]) do
                                --   if  not handTable.IsPoseRecorded  then
                                parentBoneName, deltaQuat = data[1], data[2]
                                local side
                                if name == "PrimaryHand" then
                                    side = VRState.PrimaryHandIndex == 1 and "Right" or "Left"
                                else
                                    side = VRState.PrimaryHandIndex == 1 and "Left" or "Right"
                                end

                                local resolvedBoneName = side .. NewBoneName
                                local resolvedParentName = side .. parentBoneName

                                parentRotNow = VRHandModel:GetSocketRotation(
                                    animation.findBoneFName(VRHandModel, resolvedParentName), 0)
                                parentQuatNow = quatFromRotatorVec(parentRotNow)
                                FinalRotation = quatToRotatorVec(quatMultiply(parentQuatNow, deltaQuat))

                                if not handTable.RecordOnly then -- make each one just set once instead of every interval?
                                    -- Lerp it for better animations?

                                    VRHandModel:SetBoneRotationByName(
                                        animation.findBoneFName(VRHandModel, resolvedBoneName),
                                        FinalRotation, 0)
                                end
                                -- Nil out if its a recordonly or it is an OriginalPose so that it doesn't keep trying to fight gestures
                                if next(handTable.Animations[handTable.ActivePose], NewBoneName) == nil then
                                    if (handTable.RecordOnly or handTable.ActivePose == "OriginalPose") then
                                        print("nilled out")
                                        handTable.IsActive = false
                                        handTable.ActivePose = ""
                                    end
                                end
                            end
                        else
                            for boneName, rot in ipairs(handTable.CustomLocations) do
                                for _, VRmodelBone in ipairs(handTable.VRHandModelBones) do
                                    if VRmodelBone:find(boneName) then
                                        VRHandModel:SetBoneRotationByName(
                                            animation.findBoneFName(VRHandModel, VRmodelBone),
                                            uevrUtils.rotator(rot.x, rot.y, rot.z), 0)
                                    end
                                end
                            end
                        end
                    else
                    end
                end
            end
        end
    end)


function WeaponAnimationController.SaveCalibratedPose(handed, poseName, objectName, boneRotationTable)
    local loadedConfig = json.load_file(configfileName) or {}

    local objConfig = loadedConfig[objectName]





    print("ALL DONE")
    if DefaultHandsTable.GeneralAnimations and DefaultHandsTable.GeneralAnimations[poseName] ~= nil then
        loadedConfig["GeneralAnimations"] = loadedConfig["GeneralAnimations"] or {}
        loadedConfig["GeneralAnimations"][poseName] = boneRotationTable
        json.dump_file(configfileName, loadedConfig, 4)
        print("SAVED!!!:")
        return
    end
    if not loadedConfig[objectName] then
        loadedConfig[objectName] = uevrUtils.deepCopyTable(DefaultHandsTable)
        loadedConfig[objectName].GeneralAnimations = nil
        objConfig                = loadedConfig[objectName]
    end

    if objConfig and objConfig[handed].CurrentObjectName ~= objectName then
        objConfig[handed].CurrentObjectName =
            objectName
        print("ALL DONE2")
    end
    if not objConfig[handed].Animations then objConfig[handed].Animations = {} end
    for i, _ in pairs(DefaultHandsTable.GeneralAnimations) do
        if objConfig[handed].Animations[i] then objConfig[handed].Animations[i] = {} end
    end


    if not loadedConfig[objectName] then loadedConfig[objectName] = uevrUtils.deepCopyTable(DefaultHandsTable) end
    objConfig[handed].Animations[poseName] = boneRotationTable

    for i, _ in pairs(DefaultHandsTable[handed].Animations) do
        if not objConfig[handed].Animations[i] then
            objConfig[handed].Animations[i] = "Empty"
        end
    end
    json.dump_file(configfileName, loadedConfig, 4)
end

return WeaponAnimationController
