local uevrUtils      = require("libs/uevr_utils")
local controllers    = require("libs/controllers")
local input          = require("libs/input")
local handsAnimation = require("libs/hands_animation")

local SettingsModule = {

}


local function getSBZUserSettings()
  return uevrUtils.find_first_of("SBZGameUserSettings /Engine/Transient.SBZGameUserSettings")
end
local vr                                         = uevr.params.vr

local fileName                                   = "Payday3Config.json"
-- TODO: make those tables readonly
SettingsModule.PreferredAimModeTypes             = {
  [input.AimMethod.UEVR] = "Game",
  [input.AimMethod.HEAD] = "Head/HMD",
  [input.AimMethod.RIGHT_CONTROLLER] = "Right Controller",
  [input.AimMethod.LEFT_CONTROLLER] = "Left Controller",
  [input.AimMethod.RIGHT_WEAPON] = "RightWeapon",
  [input.AimMethod.LEFT_WEAPON] = "LeftWeapon",
}
SettingsModule.PreferredHandTypes                = {
  [1] = "RightHand",
  [0] = "LeftHand"
}
SettingsModule.PreferredMovementOrientationTypes = {
  [1] = "UEVR",
  [2] = "Head/HMD",
  [3] = "Right Controller",
  [4] = "Left Controller",
}
SettingsModule.HandCouplingTypes                 = {
  ["Native"]       = "Native",
  ["Experimental"] = "Experimental"
}
SettingsModule.Settings                          = {
  ["PreferredHand"] = 1,                -- 1 is right, 0 is left
  ["PreferredAimMode"] = 0,             -- Head
  ["PreferredMovementOrientation"] = 2, -- Head
  ["AutoReload"] = false,
  ["AutoChamber"] = false,
  ["BodyVisibility"] = true,
  ["HandCoupling"] = "Native",
  ["isCalibrating"] = false,
  ["DistanceBetweenSlots"] = 5,
  -- Primary is static at the back of the head
  ["Slots"] = {
    ["Secondary"] = { x = 0, y = 0, z = 0 },
    ["Pouch"] = { x = 0, y = 0, z = 0 },
  }
}

local calibrationText  = "Calibrate Slots"
local isCalibrating    = false
local SettingsChanges  = {}
local currentAimMode
SettingsModule.IsInitiated   = false

SettingsModule.Init  = function()
  SettingsModule.IsInitiated = true
  

  uevr.lua.add_script_panel("Payday 3 VR", function()
    SettingsChanges["PreferredHand"] = table.pack(imgui.combo("Preferred Hand", SettingsModule.Settings["PreferredHand"],
      SettingsModule.PreferredHandTypes))
    SettingsChanges["PreferredAimMode"] = table.pack(imgui.combo("Preferred Aim Mode",
      SettingsModule.Settings["PreferredAimMode"], SettingsModule.PreferredAimModeTypes))
    SettingsChanges["PreferredMovementOrientation"] = table.pack(imgui.combo("Preferred Movement Orientation",
      SettingsModule.Settings["PreferredMovementOrientation"], SettingsModule.PreferredMovementOrientationTypes))
    imgui.text_colored(
      "\n \n Native: Uses the actual player's hands. \n It locks both of your hands together but its comfy for those \n who don't feel like doing many actions such as: reloading,gripping,bolting,etc.\n \n Experimental: a fully independent semi IK rig that has free hands \n instead of both hands being locked to grip one weapon \n \n Experimental settings below:",
      0xFF0000FF)
    SettingsChanges["HandCoupling"] = table.pack(imgui.combo("Hand Coupling", SettingsModule.Settings["HandCoupling"],
      SettingsModule.HandCouplingTypes))

    SettingsChanges["AutoReload"] = table.pack(imgui.checkbox("Auto Reload", SettingsModule.Settings["AutoReload"]))
    SettingsChanges["AutoChamber"] = table.pack(imgui.checkbox("Auto Chamber", SettingsModule.Settings["AutoChamber"]))
    SettingsChanges["BodyVisibility"] = table.pack(imgui.checkbox("Body Visiblity",
      SettingsModule.Settings["BodyVisibility"]))
    -- SettingsChanges["IsCalibrating"] = table.pack(imgui.button(calibrationText.."###13", { 150, 30 }),{})
    --SettingsChanges["DistanceBetweenSlots"] = table.pack(imgui.slider_float("Distance between slots"
    --,SettingsModule.Settings["DistanceBetweenSlots"],4.8,10))
    local hasChanged
    for settingName, SettingValues in pairs(SettingsChanges) do
      hasChanged = SettingValues[1]
      if hasChanged then -- changed
        local newValue = SettingValues[2]

        SettingsModule.Settings[settingName] = newValue


        if settingName == "DistanceBetweenSlots" then
          for _, slotObject in pairs(ExperimentalModule.VRState.HolsterSlots) do
            --local yOffset = i == "Secondary" and 15.0 or -15.0

            -- slotObject:K2_SetRelativeLocation(
            --     uevrUtils.vector_3f(yOffset, -yOffset / 2, -yOffset) + uevrUtils.vector_3f(-v[2],0,0),
            --   false, reusable_hit_result, false)
          end
        end
        if settingName == "IsCalibrating" then
          isCalibrating = not isCalibrating
          calibrationText = isCalibrating and "Stop Calibrating" or "Calibrate Slots"
          PD3UserConfig.Settings["IsCalibrating"] = isCalibrating
          if isCalibrating then handsAnimation.setAutoHandleInput(true) end
        end

        if settingName == "AutoChamber" and newValue then
          if ExperimentalModule.VRState.Current and ExperimentalModule.VRState.Current.Model then
            -- Reset last mag's capacity so it doesnt affect actual reloads later
            ExperimentalModule.VRState.Current.MagazineState.LastMagazineGrabbedCapacity = 0
          end
        end

        if settingName == "AutoReload" then
          --update restrictabilities to include or disinclude GA_Reload
          RestrictAbilities(AreAbilitiesRestricted()) 
          return
        end


        SaveConfig() -- could defer this until the game is closed
      end
    end
  end)
end

setInterval(500, function()
  SeekChanges()
end)

-- overrides changes made to the aim mode when the user is swapping weapons or put his VR headset back on
-- UEVR forces it to switch back to game when the headset is off


local isreticleDisabled
local SBZGameUserSettings
function SeekChanges()
  -- Aiming
  local lastAimMode = input.GetAimMethod()
  if not uevrUtils.getValid(SBZGameUserSettings) then SBZGameUserSettings = getSBZUserSettings() end
  local currentAimMode = SettingsModule.Settings["PreferredAimMode"]

  if currentAimMode ~= lastAimMode then
    if vr.is_hmd_active() then     -- Important, without this the user will crash
      input.setAimMethod(currentAimMode)
      lastAimMode = currentAimMode
    end
  end

  -- reticle disabling
  local lastReticleState = currentAimMode == 1 or currentAimMode == 2

  if isreticleDisabled ~= lastReticleState and SBZGameUserSettings then
    SBZGameUserSettings.bUseReticle = lastReticleState
    isreticleDisabled = lastReticleState
  end



  -- Movement Orientation
  local currentorientationMode = SettingsModule.Settings["PreferredMovementOrientation"]

  -- uevr.params.vr.get_movement_orientation() works too
  local lastorientationMode = input.getMovementOrientationMethod()
  local isControllerOrientation = SettingsModule.PreferredMovementOrientationTypes[currentorientationMode]:find(
  "Controller")
  if currentorientationMode ~= lastorientationMode then
    if vr.is_hmd_active() then -- Important, without this the user will crash
      input.setMovementOrientationMethod(currentorientationMode)

      lastorientationMode = input.getMovementOrientationMethod()
    end
  end



  -- borientrotationtomovement+busecontorllerdesired rotation
  -- and body orientation is HMD+ right controller on the game
  -- Game body orientation set to ga
  if not vr.is_hmd_active() then -- Important, without this the user will crash
    -- Restore when the user exits VR to avoid crashing incase
    if input.getMovementOrientationMethod() ~= 0 then
      input.setMovementOrientationMethod(0)
    end
    if input.GetAimMethod() ~= 1 then
      --  vr.set_mod_value("VR_MovementOrientation", 0)
    end
  end
end

-- Consider using configui, saves and loads config files
function SaveConfig()
  json.dump_file(fileName, SettingsModule.Settings, 4)
end

function LoadConfig()
  if json.load_file(fileName) then
    SettingsModule.Settings = json.load_file(fileName)
    print("set to!")
  else
    SaveConfig()
    -- else just keep default settings
  end
end
LoadConfig()
return SettingsModule
