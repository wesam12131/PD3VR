print("------------------")



local function resetEmptyCycle()
    
    pawn.CurrentEquippable.bIsEmpty = false
    pawn.CurrentEquippable.bIsReloading = false
    pawn.ReplicatedReloadState.Array.bIsEmptyCycleNeeded = false
    pawn.ReplicatedReloadState.Array.bIsCycleNeeded = false
end

-- last bugs to fixed
--reticle  aiming disappear on hmd aim

local uevrUtils = require("libs/uevr_utils")
local controllers = require('libs/controllers')
local attachments = require("libs/attachments")
local interaction = require("libs/interaction")
local uevrLib = require("libs/core/uevr_lib")
local animation = require('libs/animation')
local hands = require('libs/hands')
local input = require("libs/input")
local remap = require("libs/remap")
local pawnModule = require("libs/pawn")
local IKConfig = require("libs/config/ik_config_dev")

local NativeModule = require("PD3GameplayModes/Native")
local ExperimentalModule = require("PD3GameplayModes/Experimental")
local PD3UserSettings = require("libs/config/PD3UserConfig")
local WeaponAnimController = require("libs/WeaponAnimationController")






local isrestricted = false
local isDeveloperMode = true
local function InitVR(pawn)
    print("RigHandler.lua loaded")
    -------------------------------------
    uevrUtils.setDeveloperMode(true)

    --- Set debug
    uevrUtils.setLogLevel(LogLevel.Debug)
    interaction.setLogLevel(LogLevel.Debug)
    pawnModule.setLogLevel(LogLevel.Debug)
    attachments.setLogLevel(LogLevel.Debug)
    hands.setLogLevel(LogLevel.Debug)
    input.setLogLevel(LogLevel.Debug)
    ---- Init modules
    PD3UserSettings.Init()
    interaction.init(isDeveloperMode)
    attachments.init(isDeveloperMode)
    pawnModule.init(isDeveloperMode)
    input.init(isDeveloperMode)
    remap.init(isDeveloperMode)


input.setOverridePawnRotationMode(input.PawnRotationMode.ADVANCED)

input.setPlayerControllerRotationFollowsBody(true)
input.setBodyYawWritesSuppressed(false)
input.setRotationModeRotationDisabled(false)

hands.setAutoHandleInput(true)
hands.setAutoCreateHands(false)
hands.enableConfigurationTool()

    local currentMode = PD3UserSettings.Settings["HandCoupling"]
  







    pawn.CharacterMovement.bOrientRotationToMovement = false
    pawn.bUseControllerRotationYaw = false
    loopUntil("WaitforEssentials",50, function()
        if not uevrUtils.validate_object(pawn) then pawn = uevrUtils.get_local_pawn() end
        if uevrUtils.validate_object(pawn.CurrentEquippable.Mesh) and uevrUtils.validate_object(pawn) then

            if currentMode == "Native" then
                NativeModule.ActivateNativeMode(pawn)
            elseif currentMode == "Experimental" then
                hands.setAutoHandleInput(true)

                ExperimentalModule.ActivateExperimentalMode(pawn)
            end
            return false
        end
    end)
end

uevrUtils.initUEVR(uevr, function()
    local playerController = uevrUtils.get_player_controller()
    if stripSuffix(playerController.StateName:to_string()) == "Playing" and playerController.AcknowledgedPawn.Mesh1P then
        InitVR(uevrUtils.get_local_pawn())
    else
        if not PD3UserSettings.IsInitiated then PD3UserSettings.Init() end
    end
end)




-- for now just keep checking maskState until you find a good hook to hook on event
-- C++ cleanup, important otherwise a crash might happen
-- firedcount is here cause this function is called when the script is restarted, so skip it and look for real level change callbacks
-- the reason I use numbers to track if it fired is because
-- the events fire when the script resets, so I add one when the script resets and if it fires again without being reset I know it is a real level change
local FiredCountPreLevel = 0
local FiredCountLevel = 0

uevr.sdk.callbacks.on_script_reset(function()
    RestrictAbilities(false)
    unregister_key_bind("Gamepad_RightTrigger")
    unregister_key_bind("LeftMouseButton")
    uevr.api:dispatch_custom_event("Restrict", serializeTable({ "GA_Reload", "GA_PlayerEndCycleReload", "GA_Melee" },
        false))    -- restore real handle
    uevr.api:dispatch_custom_event("Cleanup")  -- wipe stale map entries
    clearGASConnections()
    uevrUtils.destroyDeferral("BoltTest")
end)

uevrUtils.registerLevelChangeCallback(function(levelName)
    FiredCountLevel = FiredCountLevel + 1
    if FiredCountLevel > 1 then
        loopUntil("PawnAwait", 200, function()
            local pawn = uevrUtils.get_local_pawn()
            local playerController = uevrUtils.get_player_controller()
            if stripSuffix(playerController.StateName:to_string()) == "Playing" and playerController.AcknowledgedPawn.Mesh1P then
                InitVR(pawn)

                return false
            end
        end)
    end
end)
uevrUtils.registerPreLevelChangeCallback(function()
    -- the C++ table that keeps the restrictedabilities original numbers will reset on script reset, hence reset the restricted to their
    --default numbers so that they don't get lost forever

    FiredCountPreLevel = FiredCountPreLevel + 1
    if FiredCountPreLevel > 1 then
        print("printing yah")
        uevr.api:dispatch_custom_event("Restrict",
            serializeTable({ "GA_Reload", "GA_PlayerEndCycleReload", "GA_Melee" }, false))    -- restore real handle
        RestrictAbilities(false)
        clearGASConnections()
        uevr.api:dispatch_custom_event("Cleanup")
        uevrUtils.destroyDeferral("BoltTest")
        FiredCountPreLevel = 0
    end
end)
