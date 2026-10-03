-- Global functions so no OOP needed
local uevrUtils     = require("libs/uevr_utils")
local animation     = require("libs/animation")
local controllers   = require('libs/controllers')
local PD3UserConfig = require('libs/config/PD3UserConfig')

-- traverses both regular and nested  arrays
--uverutils.IndexOf?
function FindInArray(array, value)
    for i, v in pairs(array) do
        if v == value then
            return i
        elseif (type(v)) == "table" then
            local result = FindInArray(array, value)
            if result then return result end
        end
    end
end

function SetMeshCollision(mesh, bool)
    local meshProxy

    -- Static meshes are usually stripped of their physics, create a sphere to act on its behalf
    if mesh and mesh:get_class():get_fname():to_string():find("Static") then
        local sphereMesh = uevr.api:find_uobject("StaticMesh /Engine/BasicShapes/Sphere.Sphere")
        meshProxy = uevrUtils.createStaticMeshComponent(sphereMesh)
        QueueForGC(meshProxy)
        meshProxy:SetWorldScale3D(uevrUtils.vector_3f(0.03, 0.03, 0.03))
        meshProxy:K2_SetWorldLocation(mesh:K2_GetComponentLocation(), false, reusable_hit_result, false)
        SetMeshVisibility({ meshProxy }, false)
    end
    local finalMesh = meshProxy or mesh
    local collisionEnabled = bool == true and 2 or 0
    finalMesh:SetSimulatePhysics(bool)
    finalMesh:SetEnableGravity(bool)
    finalMesh:SetCollisionEnabled(collisionEnabled)
    if meshProxy then mesh:K2_AttachToComponent(meshProxy, "", 1, 1, 1, false) print("attached") end


    return meshProxy or nil
end

-- GAS Stuff
-- i have to create a whole function to detect gameplayability activations because I cant detecta defeat status SMH
local GASclass = uevrUtils.get_class("Class /Script/GameplayAbilities.GameplayAbility")

local connections = {}
local isActive = {}
local cachedAbilities = {}
local objects
  local attrSet = pawn.PlayerAttributeSet
local function DetectGASActivation(updateCache)
    if next(connections) == nil or objects == nil then return end
    if updateCache then
        for i, obj in ipairs(objects) do
            if uevrUtils.getValid(obj) then
                local name = obj:get_full_name()
                if not name:find("Default__") and name:find("PersistentLevel") and name:find("BP_PlayerState") then
                    if obj:get_outer().PawnPrivate == pawn then -- ensure we only access the VR player's abilities
                        for requestedGASName, callbackTable in pairs(connections) do
                            if name:find(requestedGASName) and not FindInArray(cachedAbilities, obj) then
                                table.insert(cachedAbilities, obj)
                            end
                        end
                    end
                end
            end
        end
    end
    for i, obj in ipairs(cachedAbilities) do
        if uevrUtils.getValid(obj) then
            local name = obj:get_full_name()
            for requestedGASName, callbackTable in pairs(connections) do
                if name:find(requestedGASName) then
                    if obj.bIsActive then
                        for GASName, entry in pairs(callbackTable) do
                            if entry.Type == "On" and not callbackTable[GASName].wasCalled then
                                entry.Callback()
                                callbackTable[GASName].wasCalled = true
                                if callbackTable[GASName].isOnce then callbackTable[GASName] = nil end
                            end
                        end
                        isActive[obj] = true
                    else
                        -- reset callback's wasCalled when the GAS ability turns off
                        if isActive[obj] == true then
                            for GASName, _ in pairs(callbackTable) do
                                if callbackTable[GASName] and callbackTable[GASName].wasCalled then
                                    callbackTable[GASName].wasCalled = false
                                end
                            end
                        end

                        -- Handle Type "After", when the ability turns off
                        if isActive[obj] == true then
                            isActive[obj] = false
                            for GASName, entry in pairs(callbackTable) do
                                if entry.Type == "After" and callbackTable[GASName] and not callbackTable[GASName].wasCalled then
                                    entry.Callback()
                                    callbackTable[GASName].wasCalled = true
                                    if callbackTable[GASName].isOnce then callbackTable[GASName] = nil end
                                end
                            end
                            -- Reset was called
                        elseif isActive[obj] == false then
                            for GASName, entry in pairs(callbackTable) do
                                if entry.Type == "After" and callbackTable[GASName] and callbackTable[GASName].wasCalled then
                                    callbackTable[GASName].wasCalled = false
                                    
                                    if callbackTable[GASName].isOnce then callbackTable[GASName] = nil end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
  end


-- types: "On" (on activation), "After" (after the ability activates and disables itself)
function RegisterGASActivation(GASName, type, isOnce, callback)
    if not objects then objects = GASclass:get_objects_matching(false) end
   if not connections[GASName] then connections[GASName] = {} end
    table.insert(connections[GASName], { Type = type, isOnce = isOnce, Callback = callback, wasCalled = false })
    DetectGASActivation(true)
end

function clearGASConnections()
    cachedAbilities, isActive, connections, objects = {}, {}, {}, nil
end

-- Visibility stuff
local ParentVisibility = {}
function BindMeshVisibilityToParent(parent, meshes, options)
    if not ParentVisibility[parent] then ParentVisibility[parent] = {} end
    for i, v in pairs(meshes) do
        table.insert(ParentVisibility[parent], {
            mesh    = v,
            reverse = options and options.reverse == true or false,
        })
    end
    return true
end

function ResetBindedMeshes()
    ParentVisibility = {}
end

-- Custom binding is when you want X binded meshes to follow the parent's but also need to set another mesh to be the opposite
-- for example, if I binded a weapon to a scope and a mag, the player ejected a mag
-- then unequipped his weapon, and equipped it, I want to exclude the mag this time but keep the scope
-- {Mesh = true}
function SetMeshVisibility(Meshes, isVisible, CustomBinding,test,a)
    -- // SetRenderInTop pass is the main one that makes an object visible in  PD3 VR
    -- hence why most first attempts at getting this game to show the model didn't work I guess
    local originalVisibility = isVisible
    for _, Mesh in pairs(Meshes) do
        -- set original hide if we set hide previously for a custom binding
        if isVisible ~= originalVisibility then isVisible = originalVisibility end
        if CustomBinding then
            for customBind, v in pairs(CustomBinding) do
                SetMeshVisibility({ v }, customBind)
            end
        end
        if type(Mesh) == "table" and Mesh.mesh then
            if Mesh.reverse then print(isVisible) end
            if Mesh.reverse then isVisible = not isVisible end
            if Mesh.reverse then print("ay we found reverse", Mesh.mesh, Mesh.reverse, isVisible) end
            Mesh = Mesh.mesh
        end
        if Mesh.SetHiddenInGame then Mesh:SetHiddenInGame(isVisible ~= true, true)   end
        if Mesh.SetVisibility then Mesh:SetVisibility(isVisible == true, true) end
        if Mesh.SetOwnerNoSee then Mesh:SetOwnerNoSee(false) end
        if Mesh.SetRenderInTopPass then Mesh:SetRenderInTopPass(isVisible ~= true) end
        if Mesh.SetRenderInMainPass then Mesh:SetRenderInMainPass(isVisible == true) end

        --Mesh.bNeverDistanceCull = true
        -- infinite loop when the parent visibility tbl has a reference to itself
        -- oh wait..
        local RegisteredChildren = ParentVisibility[Mesh]
        if RegisteredChildren then
            SetMeshVisibility(RegisteredChildren, isVisible or false)
            --  elseif  FindInArray(ParentVisibility)
        end
    end
end

-- VR pose getting, mostly for optimization
local devices = {
    [0] = "get_right_controller_index",
    [1] = "get_left_controller_index",
    [2] = "get_hmd_index"
}
local reusables = {}
-- **This function needs a reasonable collection time so please be considerable**
--
--  **first parameter is: 0 is RightController, 1 is LeftController, 2 is HMD**
--
-- **Second parameter is a string ID you give this call so that  UEVR_Vector3f, UEVR_Quaternionf can be reused and not put weight on GC**
--
-- ** third parameter can be get_pose,get_standing_origin**
--
-- **fourth parameter can  be a table consisting of what data you want: {"Position"} or {"Rotation"} or both**
function getDevicePose(type, reusableID, method, ...)
    local deviceIndexFunction = devices[type]
    local dataRequested = ...
    local device_position, device_rotation, device_index
    local isPositionRequested = FindInArray(dataRequested, "Position")
    local isRotationRequested = FindInArray(dataRequested, "Rotation")
    if deviceIndexFunction then
        if reusables[reusableID] then
            device_position, device_rotation, device_index = reusables[reusableID][1], reusables[reusableID][2],
                reusables[reusableID][3]
        elseif reusableID and not reusables[reusableID] or not reusableID then
            -- nil them out early so we don't make useless copies of unused values like if rotation isn't requested throughout
            -- nevermind, maybe later but now get pose requests them both
            device_position = UEVR_Vector3f.new()
            device_rotation = UEVR_Quaternionf.new()
            device_index = uevr.params.vr[deviceIndexFunction]()
            -- store if requested
            if reusableID then reusables[reusableID] = { device_position, device_rotation, device_index } end
        end

        if method == "get_standing_origin" then
            uevr.params.vr.get_standing_origin(device_position)                     -- fills in the previous variables
        elseif method == "get_pose" then
            uevr.params.vr.get_pose(device_index, device_position, device_rotation) -- fills in the previous variables
        end
        if not isPositionRequested then device_position = nil elseif not isRotationRequested then device_rotation = nil end

        return { Position = device_position, Rotation = device_rotation }
    else
        print("Device does not exist/ is not supported")
        return nil
    end
end

-- useful functions

function loopUntil(name, timeout, callback)
    uevrUtils.createDeferral(name, timeout, function()
        local returnValue = callback()
        if returnValue == false then uevrUtils.destroyDeferral(name) end
        uevrUtils.updateDeferral(name)
    end)
    uevrUtils.updateDeferral(name)
end

function IsWithinRange(pos1, pos2, min, max)
    -- // mostly Unreal engine positions that need / 100 to be normalized to values like 1 or 3 etc
    local distance = uevrUtils.distanceBetween(pos1, pos2) / 100

    if distance >= min and distance <= max then
        return true
    else
        return false
    end
end
local lastRestriction
function AreAbilitiesRestricted()
    return lastRestriction or false
end

function RestrictAbilities(bool, customAbilities)
    local autoReload = PD3UserConfig.Settings["AutoReload"]
    local abilities = customAbilities and customAbilities or
        not autoReload and {
            "GA_Reload",
            "GA_Melee",
        --    "GA_PlayerEndCycleReload",
            "GA_EquipPlacableAbility",
            "SBZEquipAutoAbility",
            "GA_PlayerEmote_C",
            "SBZEquipConsumableAbility",
            "SBZEquipNextGadgetAbility",
            "GA_EquipPlacableAbility_C",
            "GA_ThrowItem_C" }
        or {
            "GA_Melee"
            , "GA_EquipPlacableAbility",
            "SBZEquipAutoAbility",
            "GA_PlayerEmote_C",
            "SBZEquipConsumableAbility",
        --    "SBZEquipNextGadgetAbility",
            "GA_EquipPlacableAbility_C" }
    
            -- Certain stuff should be disconnected from the restrictions because they're user choice
    uevr.api:dispatch_custom_event("Restrict", serializeTable({"GA_Reload"}),autoReload)
    uevr.api:dispatch_custom_event("Restrict", serializeTable(abilities, bool or lastRestriction))
    lastRestriction = bool
end

-- Methods can be: None,Visibility,Scale
-- None would immediately destroy it after
-- Visibility method  makes it invisibleand despawns it after X time (unimplmented)
-- scale would slowly shrink the object (unimplemented)
function ScheduleActorDespawn(Actor, time, Method)
    if Method == "None" then
         uevrUtils.delay(time*1000, function()
        uevrUtils.destroy_actor(Actor)
         end)
    end
    if Method == "Visibility" then

    end
end

-- type can be gamepad or keyboard
function GetUserActionKeybind(actionName,type)
if type == "Keyboard" then
    local SBZUserSettings = uevrUtils.find_first_of("SBZGameUserSettings /Engine/Transient.SBZGameUserSettings")
    return SBZUserSettings:GetPrimaryKeyboardBinding("ToolEquip", 1.0).KeyName:to_string()
end
--SBZGamepadBindingsManager /Engine/Transient.SBZGameEngine.PD3_GameInstance_C.SBZGamepadBindingsManager
--SBZUserSettings:GetPrimaryKeyboardBinding("ToolEquip", 1.0)
end
-- Get binded
--[[function RecordCurrentHandRotations()
    register_key_bind("F6", function()
        local BonesToRecord = { "Index", "Thumb", "Pinky", "Middle", "Ring", "Flexor", "Extensor" }
        local MappedBones = {}
        local OriginalGloves = pawn.Mesh1PGloves
        local VRHandModelBones = animation.getCachedBoneNames(VRHandModel)
        for i, ModelBoneName in ipairs(VRHandModelBones) do
            for _, ModifiableBone in pairs(BonesToRecord) do
                if ModelBoneName:find(ModifiableBone) and (Handed and ModelBoneName:find(Handed)) then
                    local OriginalBoneName = animation.findBoneFName(OriginalGloves, ModelBoneName)

                    local parentBoneName = animation.FindBoneParentFromCache(OriginalGloves, OriginalBoneName)

                    local parentRotAtCapture = OriginalGloves:GetSocketRotation(parentBoneName)
                    local fingerRotAtCapture = OriginalGloves:GetSocketRotation(OriginalBoneName)

                    local parentQuat = quatFromRotatorVec(parentRotAtCapture)
                    local fingerQuat = quatFromRotatorVec(fingerRotAtCapture)
                    local deltaQuat = quatMultiply(quatConjugate(parentQuat), fingerQuat)

                    MappedBones[animation.findBoneFName(VRHandModel, ModelBoneName)] = { parentBoneName, deltaQuat }
                end
            end
        end

        for i, v in MappedBones do
            print(i, v[1], v[2])
        end
    end)
end
]]

-- Queues an object for cleanup on script reset or level change
local GCQueue = {}
function QueueForGC(queue)
    if type(queue) == "table" then
        for i, v in pairs(queue) do
            table.insert(GCQueue, v)
        end
    else
        table.insert(GCQueue, queue)
    end
end

function DestroyGCQueue()
    for i, v in pairs(GCQueue) do
        if v and uevrUtils.validate_object(v) then
            className = v:get_class():get_full_name()
            if className:find("Component") then
                uevrUtils.detachAndDestroyComponent(v, false)
            elseif className:find("Actor") then
                uevrUtils.destroy_actor(v)
            end
        else -- already invalid, remove
            table.remove(GCQueue, i)
        end
    end
    GCQueue = {}
end

function DumpObjClass(obj)
    local struct = obj:get_class()
    print(struct)
    local field = obj.get_children and obj:get_children()
    for i = 0, 100, 1 do
        local field_name = field and field:get_fname() or nil
        field = field and field:get_next() or nil
        print(field_name)
    end
end

function HandedIndexToString(handed)
    if handed == 0 then return "LeftHand" else return "RightHand" end
end
-- Has keybind been pressed recently rather than already pressed to avoid false positives?

local ButtonStates = {
    ["RightHandShoulder"] = {
        ButtonIndex = XINPUT_GAMEPAD_RIGHT_SHOULDER,

        IsPressed = false,
        LastPressed = 0
    },
    ["LeftHandShoulder"] = {
        ButtonIndex = XINPUT_GAMEPAD_LEFT_SHOULDER,
        IsPressed = false,
        LastPressed = 0
    },
    ["LeftHandTrigger"] = {
        ButtonIndex = "bLeftTrigger",
        CurrentThreshold = 0,
        Threshold = 100,
        IsPressed = false,
        LastPressed = 0
    },
    ["RightHandTrigger"] = {
        ButtonIndex = "bRightTrigger",
        CurrentThreshold = 0,
        Threshold = 100,
        IsPressed = false,
        LastPressed = 0
    },
}

local isVRActive
local function trackButtonPress(XInputState)
    isVRActive = uevr.params.vr.is_hmd_active()
    if isVRActive then
        for _, State in pairs(ButtonStates) do
            if type(State.ButtonIndex) == "string" then
            
                State.CurrentThreshold = XInputState.Gamepad[State.ButtonIndex]
                currentState = State.CurrentThreshold > State.Threshold and true or false
            else
                currentState = uevrUtils.isButtonPressed(XInputState, State.ButtonIndex)
            end
            if currentState ~= State.IsPressed then
                State.IsPressed = currentState
                if State.IsPressed then State.LastPressed = os.clock() end
            end
        end
    else
        return false
    end
end
function isDigitalButtonPressed(button, customTime)
    local buttonState = ButtonStates[button]
    if buttonState then
        if buttonState.IsPressed then
            return true
        else
            return false
        end
    else
        print("button invalid/unregistered")
        return nil
    end
end

function GetButtonLastPressed(button)
    local buttonState = ButtonStates[button]
    return buttonState.LastPressed
end

function IsButtonRecentlyPressed(button, customTime, customPrediction)
    local buttonState = ButtonStates[button]
    if buttonState then
        if buttonState.LastPressed and buttonState.IsPressed then
            local isRecentlyPressed = customTime and os.clock() - buttonState.LastPressed <= customTime or
                (os.clock() - buttonState.LastPressed <= 0.5)
            if isRecentlyPressed then
                return true
            elseif customPrediction and buttonState.CurrentThreshold >= customPrediction then
                return true
            else
                return false
            end
        else
            return false
        end
    else
        print("button invalid/unregistered")
        return nil
    end
end

-- Calculate controller velocity
local controllersVelocity = {
    [Handed.Left] = {
        Velocity = nil,
        LastRecordedPos = nil,
    },
    [Handed.Right] = {
        Velocity = nil,
        LastRecordedPos = nil,
    }

}
function GetControllerVelocity(handed)
    return controllersVelocity[handed].Velocity
end

local function trackVelocity(delta)
    for i, v in pairs(controllersVelocity) do
        local pos = controllers.getControllerLocation(i)
        if pos and math.abs(pos.X + pos.Y + pos.Z) >= 0 then
            if v.LastRecordedPos then
                local PosDelta = kismet_math_library:Subtract_VectorVector(pos, v.LastRecordedPos)
                local currentVelocity = kismet_math_library:Divide_VectorFloat(PosDelta, delta)
                local magnitude = math.min(
                    (math.abs(currentVelocity.X) + math.abs(currentVelocity.Y) + math.abs(currentVelocity.Z)) / 10, 1.2)
                v.Velocity = kismet_math_library:Multiply_VectorInt(currentVelocity, magnitude)
            end
            v.LastRecordedPos = pos
        end
    end
end
lastState = nil
-- convienent when you don't want to do a whole loop to get a one time state
function GetLastState()
    return lastState
end

-- leave it as functions incase more detections need to go in here

uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    trackVelocity(delta)
    DetectGASActivation()
end)
uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
    trackButtonPress(state)
    lastState = state
end, 0)

-- serializes a table, used for  lua to C++ communication
function serializeTable(LuaTable, additionalParam)
    local str = table.concat(LuaTable, ",")
    if type(additionalParam) == "table" then
        for i, v in pairs(additionalParam or {}) do
            str = str .. "|" .. tostring(v)
        end
    elseif type(additionalParam) == "boolean" then
        str = str .. "|" .. tostring(additionalParam)
    end
    return str
end

function degToRad(d) return d * math.pi / 180 end

function radToDeg(r) return r * 180 / math.pi end

function quatFromRotatorVec(rot)
    -- print(rot.x,rot.X,rot.Pitch,"bom")
    local pitch, yaw, roll = degToRad(rot.Pitch or rot.x or 0), degToRad(rot.Yaw or rot.y or 0),
        degToRad(rot.Roll or rot.z or 0)

    local cr, sr = math.cos(roll * 0.5), math.sin(roll * 0.5)
    local cp, sp = math.cos(pitch * 0.5), math.sin(pitch * 0.5)
    local cy, sy = math.cos(yaw * 0.5), math.sin(yaw * 0.5)
    return {
        x = sr * cp * cy - cr * sp * sy,
        y = cr * sp * cy + sr * cp * sy,
        z = cr * cp * sy - sr * sp * cy,
        w = cr * cp * cy + sr * sp * sy,
    }
end

function quatMultiply(a, b)
    return {
        w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y = a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z = a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
    }
end

function quatConjugate(q) return { x = -q.x, y = -q.y, z = -q.z, w = q.w } end

function quatToRotatorVec(q)
    local roll = math.atan(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y))
    local sinp = 2 * (q.w * q.y - q.z * q.x)
    local pitch = math.abs(sinp) >= 1 and (sinp >= 0 and math.pi / 2 or -math.pi / 2) or math.asin(sinp)
    local yaw = math.atan(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))
    return uevrUtils.rotator(radToDeg(pitch), radToDeg(yaw), radToDeg(roll))
end

local function GetPalmSurfacePoint(mesh, handPrefix)
    local weapon = mesh:GetSocketLocation(
        uevrUtils.fname_from_string(handPrefix .. "HandWeapon")
    )

    local middle

    if handPrefix == "Right" then
        middle = mesh:GetSocketLocation(
            uevrUtils.fname_from_string("RightHandMiddle1")
        )
    else
        middle = mesh:GetSocketLocation(
            uevrUtils.fname_from_string("LeftInHandMiddle")
        )
    end

    local extensor = mesh:GetSocketLocation(
        uevrUtils.fname_from_string(handPrefix .. "HandExtensor")
    )

    local flexor = mesh:GetSocketLocation(
        uevrUtils.fname_from_string(handPrefix .. "HandFlexor")
    )

    local center = weapon + (middle - weapon) * 0.5

    local palmDir = flexor - extensor
    local thickness = palmDir:length()

    if thickness <= 0.001 then
        return center
    end

    palmDir = kismet_math_library:Divide_VectorFloat(
        palmDir,
        thickness
    )

    local surfaceOffset = kismet_math_library:Multiply_VectorFloat(
        palmDir,
        thickness * 0.5
    )

    return center + surfaceOffset
end


local function GetHandContactPoint(mesh,handed, boneA, boneB, blend)
    if boneA == "PalmSurface" then
        return GetPalmSurfacePoint(mesh, handed)
    end

    if not boneA or boneA == "" then return nil end

    local a = mesh:GetSocketLocation(uevrUtils.fname_from_string(boneA))

    if not boneB or boneB == "" then return a end

    local b = mesh:GetSocketLocation(uevrUtils.fname_from_string(boneB))

    blend = blend or 0.5

    return a + (b - a) * blend
end
local function CalculateDynamicHandOffset(
    mesh,
    handed,
    parentAttachment,
    socketName,
    handBoneName,
    contactBoneA,
    contactBoneB,
    blend
)
    if not mesh or not parentAttachment then
        return {0, 0, 0}
    end

    local contactLoc = GetHandContactPoint(
        mesh,
        handed,
        contactBoneA,
        contactBoneB,
        blend
    )

    if not contactLoc then
        return {0, 0, 0}
    end

    local socket = uevrUtils.fname_from_string(socketName)
    local hand = uevrUtils.fname_from_string(handBoneName)

    local socketTransform =
        parentAttachment:GetSocketTransform(socket, 0)

    local handLoc =
        mesh:GetSocketLocation(hand)

    local handToContactWS =
        contactLoc - handLoc

    local contactVectorInSocket =
        kismet_math_library:InverseTransformDirection(
            socketTransform,
            handToContactWS
        )

    return {
        -contactVectorInSocket.X,
        -contactVectorInSocket.Y,
        -contactVectorInSocket.Z
    }
end

function AttachHandAccurate(handed, mesh, parentAttachment, socketName, rot,pos, handBoneName, contactBoneA, contactBoneB,
                            blend)
    if not mesh or not parentAttachment then return end

    -- Normalize rotation back to 0 cause IK has to rotate both hands to fit each hand (ikconfig)
    --, right hand is {} left hand is
    rot = rot or  handed == 0 and { 0, 90, 0 } or {180,-90,0}
    pos = pos or {0,0,0}
    handBoneName = handBoneName or "LeftHand"

    uevrUtils.executeUEVRCallbacks(
        "on_accessory_attach",
        handed,
        parentAttachment,
        socketName,
        2,
        pos,
        rot
    )

    -- No contact bone = wrist directly on target
    if not contactBoneA or contactBoneA == "" then return end

    uevrUtils.delay(100, function()
        if not mesh or not parentAttachment then return end

        local offset = CalculateDynamicHandOffset(
            mesh,
            HandedIndexToString(handed):find("Right") and "Right" or "Left",
            parentAttachment,
            socketName,
            handBoneName,
            contactBoneA,
            contactBoneB,
            blend
        )
   for i,v in pairs(offset) do offset[i] = offset[i] + pos[i] end

        uevrUtils.executeUEVRCallbacks(
            "on_accessory_attach",
            handed,
            parentAttachment,
            socketName,
            2,
            offset,
            rot
        )
    end)
end

function GetGripFacingRot(mesh, weapon, gripBoneName, handBoneName, forwardFromName, forwardToName, normalFromName,
                          normalToName, ikEndRot)
    print("\n================ GetGripFacingRot ================")
    print("Grip bone:", gripBoneName)
    print("Hand bone:", handBoneName)
    print("Forward:", forwardFromName, "->", forwardToName)
    print("Normal:", normalFromName, "->", normalToName)
    print("IK end rot:", ikEndRot[1], ikEndRot[2], ikEndRot[3])

    local hand = uevrUtils.fname_from_string(handBoneName)
    local forwardFrom = uevrUtils.fname_from_string(forwardFromName)
    local forwardTo = uevrUtils.fname_from_string(forwardToName)
    local normalFrom = uevrUtils.fname_from_string(normalFromName)
    local normalTo = uevrUtils.fname_from_string(normalToName)
    local grip = uevrUtils.fname_from_string(gripBoneName)

    local handLoc = mesh:GetSocketLocation(hand)
    local forwardFromLoc = mesh:GetSocketLocation(forwardFrom)
    local forwardToLoc = mesh:GetSocketLocation(forwardTo)
    local normalFromLoc = mesh:GetSocketLocation(normalFrom)
    local normalToLoc = mesh:GetSocketLocation(normalTo)
    local gripLoc = weapon:GetSocketLocation(grip)


    local palmForward = forwardToLoc - forwardFromLoc
    local palmNormal = normalToLoc - normalFromLoc


    local palmWorldRot = kismet_math_library:MakeRotFromXZ(palmForward, palmNormal)
    local handWorldRot = mesh:GetSocketRotation(hand)
    local gripWorldRot = weapon:GetSocketRotation(grip)


    local zero = uevrUtils.vector(0, 0, 0)
    local one = uevrUtils.vector(1, 1, 1)
    local zeroRot = uevrUtils.rotator(0, 0, 0)

    local handWorldTransform = kismet_math_library:MakeTransform(zero, handWorldRot, one)
    local palmWorldTransform = kismet_math_library:MakeTransform(zero, palmWorldRot, one)

    local palmRelativeToHand = kismet_math_library:ComposeTransforms(
        palmWorldTransform,
        kismet_math_library:InvertTransform(handWorldTransform)
    )

    local palmRelativeRot = kismet_math_library:TransformRotation(palmRelativeToHand, zeroRot)


    local desiredPalmWorld = kismet_math_library:MakeTransform(zero, gripWorldRot, one)

    local desiredHandWorld = kismet_math_library:ComposeTransforms(
        kismet_math_library:InvertTransform(palmRelativeToHand),
        desiredPalmWorld
    )

    local desiredFinalHandRot = kismet_math_library:TransformRotation(desiredHandWorld, zeroRot)


    local ikEndRotation = uevrUtils.rotator(ikEndRot[1], ikEndRot[2], ikEndRot[3])


    local ikTransform = kismet_math_library:MakeTransform(zero, ikEndRotation, one)
    local inverseIKTransform = kismet_math_library:InvertTransform(ikTransform)
    local inverseIKRot = kismet_math_library:TransformRotation(inverseIKTransform, zeroRot)



    local controllerTargetWorldRot = kismet_math_library:ComposeRotators(
        inverseIKRot,
        desiredFinalHandRot
    )


    local gripTransform = weapon:GetSocketTransform(grip, 0)

    local localRot = kismet_math_library:InverseTransformRotation(
        gripTransform,
        controllerTargetWorldRot
    )


    -- Reconstruct what accessory code should turn it into.
    local reconstructedControllerWorld = kismet_math_library:ComposeRotators(
        localRot,
        gripWorldRot
    )


    -- Reconstruct what UEVRLib IK should theoretically produce.
    local compToWorld = mesh:K2_GetComponentToWorld()

    local reconstructedControllerCS = kismet_math_library:InverseTransformRotation(
        compToWorld,
        reconstructedControllerWorld
    )


    local predictedFinalHandCS = kismet_math_library:ComposeRotators(
        ikEndRotation,
        reconstructedControllerCS
    )



    local predictedFinalHandWorld = kismet_math_library:TransformRotation(
        compToWorld,
        predictedFinalHandCS
    )


    local predictionError = kismet_math_library:NormalizedDeltaRotator(
        predictedFinalHandWorld,
        desiredFinalHandRot
    )


    print("===================================================\n")

    return { localRot.Pitch, localRot.Yaw, localRot.Roll }
end
