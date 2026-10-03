local uevrUtils = require("libs/uevr_utils")
local attachments = require("libs/attachments")
local animation = require("libs/animation")

local M = {}

local holdingAttachment = {}
local inputHandlerAnimID = {}
local activeComponents = {}
local autoHandleInput = true
local disableAnimations = false --used during hand configuration to prevent loaded animation from interfering


local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
	if logLevel == nil then logLevel = LogLevel.Debug end
	if logLevel <= currentLogLevel then
		uevrUtils.print("[hands_animation] " .. text, logLevel)
	end
end

local function getAnimIDSuffix(animID)
	local arr = uevrUtils.splitStr(animID, "_")
	return #arr > 0 and arr[#arr] or nil
end


-- This needs to be called externally
function M.createAnimationHandler(animID, component, handAnimations)
    if component == nil then return end
    local suffix = getAnimIDSuffix(animID)

    if suffix ~= nil then inputHandlerAnimID[animID] = suffix end
    activeComponents[component] = animID
    animation.add(animID, component, handAnimations)
    animation.initialize(animID, component)
end

function M.destroyAnimationHandler(component)
    local animID = activeComponents[component]
    if animID ~= nil then
        inputHandlerAnimID[animID] = nil
    end
end

function M.reset()
	autoHandleInput = true
    disableAnimations = false
	inputHandlerAnimID = {}
    holdingAttachment = {}
    activeComponents = {}
	attachmentStateInitialized = false
end

function M.exists()
    return next(inputHandlerAnimID) ~= nil
end
local attachmentStateInitialized = false -- prevents it from running early and causing a ruckus, wesam

local createInputHandler = doOnce(function()
	attachments.registerOnGripAnimationCallback(function(gripAnimation, gripHand)
		 if autoHandleInput and M.exists() and attachmentStateInitialized then
		M.print("Grip animation changed to " .. (gripAnimation and tostring(gripAnimation) or "None") .. " for " .. (gripHand == Handed.Left and "Left" or "Right") .. " hand", LogLevel.Debug)
		--print("Grip animation changed to ", gripAnimation, gripHand)
	--	M.updateAnimationState(gripHand)
		 end
	end)

	uevrUtils.registerOnPreInputGetStateCallback(function(retval, user_index, state)
	-- print("callback: exists=" .. tostring(M.exists()) .. " initialized=" .. tostring(attachmentStateInitialized) .. " autoHandle=" .. tostring(autoHandleInput))
		 if autoHandleInput and M.exists() and attachmentStateInitialized then
			
			local rightAttachment = holdingAttachment[Handed.Right] or attachments.getCurrentGripAnimation(Handed.Right)
			local leftAttachment = holdingAttachment[Handed.Left] or attachments.getCurrentGripAnimation(Handed.Left)
			--M.handleInput(state, attachment, Handed.Right, nil, true)
			M.handleInputForHands(state, rightAttachment, leftAttachment, nil, true)
		end
	end, 10) --high priority to intercept messages before possible remapper
end, Once.EVER)
createInputHandler()

local function getAttachmentStateAndExtension(attachment)
	local isHoldingAttachment = false
	local attachmentExtension = ""
	if type(attachment) == "boolean" then
		isHoldingAttachment = attachment
	elseif type(attachment) == "string" and attachment ~= "attachment_none" then
		isHoldingAttachment = true
		if attachment ~= "" then
			attachmentExtension = "_" .. attachment
		end
	end
	return isHoldingAttachment, attachmentExtension
end

function M.setAutoHandleInput(val)
	autoHandleInput = val
end

function M.disableAnimations(value)
	disableAnimations = value
end

function M.setHoldingAttachment(hand, val)
	holdingAttachment[hand] = val
	M.updateAnimationState(hand)
	attachmentStateInitialized = true
end
function M.getHoldingAttachment(hand)
return holdingAttachment[hand] 
end

 local Holding = {}
function M.updateAnimationState(hand)
	if M.exists() then
		local attachment = holdingAttachment[hand]
		if attachment == nil then
			attachment = attachments.getCurrentGripAnimation(hand)
		end
	
		local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
		
		if isHoldingAttachment then

			for id, target in pairs(inputHandlerAnimID) do
				local handStr = hand == Handed.Left and "left" or "right"
				animation.resetAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, true) --forces an update regardless of current state
			--	animation.resetAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, true) --forces an update regardless of current state
				animation.pose(handStr .. "_" .. target, "grip_" .. handStr .. "_weapon" .. attachmentExtension)
			end
		else

			for id, target in pairs(inputHandlerAnimID) do
				local handStr = hand == Handed.Left and "left" or "right"
				animation.pose(handStr .. "_" .. target, "open_" .. handStr)
			end
		end
	end
end

function M.handleInputForHands(state, rightAttachment, leftAttachment, overrideTrigger, allowAutoHandle,overrideCurrentAnimation)

	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInputForHands")
		return true
	end

	if overrideTrigger == nil then overrideTrigger = false end

	local animDuration = 0.1
	--("inputHandlerAnimID count:", next(inputHandlerAnimID))
	for id, target in pairs(inputHandlerAnimID) do
		for hand = Handed.Left, Handed.Right do -- bug!!
			local handStr = hand == Handed.Right and "right" or "left"
			--do not use ternary operators like this. If right attachment is nil then it will always pick leftAttachment for Handed.Right == true
			--local attachment = hand == Handed.Right and rightAttachment or leftAttachment
			local attachment = nil
			if hand == Handed.Right then attachment = rightAttachment else attachment = leftAttachment end
			local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)
			--print("Handling input for " .. handStr .. " hand, attachment: " .. (type(attachment) == "string" and attachment or tostring(attachment)) .. ", isHoldingAttachment: " .. tostring(isHoldingAttachment) .. ", attachmentExtension: " .. attachmentExtension)
if not isHoldingAttachment then

       Holding[hand] = false	
				local weaponHandTriggerValue = ((hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger)
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", overrideCurrentAnimation or weaponHandTriggerValue > 100, {duration=animDuration})
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip",  overrideCurrentAnimation or uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})

				local weaponhandController = uevr.params.vr.get_right_joystick_source()
				if not (hand == Handed.Right) then weaponhandController = uevr.params.vr.get_left_joystick_source() end
				local weaponhandRest = uevr.params.vr.get_action_handle(hand == Handed.Right and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
				
				animation.updateAnimation(handStr.."_"..target, handStr.."_thumb",overrideCurrentAnimation or  uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
elseif not  Holding[hand] then


	  Holding[hand] = true
    M.updateAnimationState(hand)
--[[				local weaponHandTriggerValue = (hand == Handed.Right or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
				animation.updateAnimation(handStr.."_"..target, handStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
				local isButtonPressed = uevrUtils.isButtonPressed(state, hand == Handed.Right and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER)
				animation.updateAnimation(handStr.."_"..target, handStr.."_grip_weapon" .. attachmentExtension, isButtonPressed, {duration=animDuration})]]
				end

		end
	end
end
function M.resetHandAnimations(hand)
    local handStr = hand == Handed.Right and "right" or "left"
    local animDuration = 0.1
    for id, target in pairs(inputHandlerAnimID) do
        animation.resetAnimation(handStr.."_"..target, handStr.."_grip", true)  -- force state to true so updateAnimation will fire off
        animation.resetAnimation(handStr.."_"..target, handStr.."_trigger", true)
        animation.resetAnimation(handStr.."_"..target, handStr.."_thumb", true)
        animation.updateAnimation(handStr.."_"..target, handStr.."_grip", false, {duration=animDuration})
        animation.updateAnimation(handStr.."_"..target, handStr.."_trigger", false, {duration=animDuration})
        animation.updateAnimation(handStr.."_"..target, handStr.."_thumb", false, {duration=animDuration})
    end
end
--deprecated
function M.handleInput(state, attachment, hand, overrideTrigger, allowAutoHandle)
	--print("called with,",state, attachment, hand, overrideTrigger, allowAutoHandle)
	if allowAutoHandle ~= true then
		autoHandleInput = false --if something else is calling this then dont auto handle input
	end
	if disableAnimations then
		--print("Animations are disabled, skipping handleInput")
		return true
	end

	local isHoldingAttachment, attachmentExtension = getAttachmentStateAndExtension(attachment)

	if hand == nil then hand = Handed.Right end
	if overrideTrigger == nil then overrideTrigger = false end
	local isRightHanded = hand == Handed.Right
	local weaponHandStr = isRightHanded and "right" or "left"
	local offHandStr = isRightHanded and "left" or "right"
	local animDuration = 0.1
	for id, target in pairs(inputHandlerAnimID) do
	--	print(id,target,"tar+id")
		local offhandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bLeftTrigger or state.Gamepad.bRightTrigger
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_trigger", offhandTriggerValue > 100, {duration=animDuration})

		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_LEFT_SHOULDER or XINPUT_GAMEPAD_RIGHT_SHOULDER), {duration=animDuration})

		local offhandController = uevr.params.vr.get_left_joystick_source()
		if not isRightHanded then offhandController = uevr.params.vr.get_right_joystick_source() end
		local offhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchLeft" or "/actions/default/in/ThumbrestTouchRight")
		animation.updateAnimation(offHandStr.."_"..target, offHandStr.."_thumb", uevr.params.vr.is_action_active(offhandRest, offhandController), {duration=animDuration})

		if not isHoldingAttachment then
		--	print("not holding")
			local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger", weaponHandTriggerValue > 100, {duration=animDuration})

			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip", uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER), {duration=animDuration})
--print("here3")
			local weaponhandController = uevr.params.vr.get_right_joystick_source()
			if not isRightHanded then weaponhandController = uevr.params.vr.get_left_joystick_source() end
			local weaponhandRest = uevr.params.vr.get_action_handle(isRightHanded and "/actions/default/in/ThumbrestTouchRight" or "/actions/default/in/ThumbrestTouchLeft")
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_thumb", uevr.params.vr.is_action_active(weaponhandRest, weaponhandController), {duration=animDuration})
		else
	
			--print("holding attachment")
	--[[		local weaponHandTriggerValue = (isRightHanded or overrideTrigger) and state.Gamepad.bRightTrigger or state.Gamepad.bLeftTrigger
			animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_trigger_weapon" .. attachmentExtension, weaponHandTriggerValue > 100, {duration=animDuration})
			if uevrUtils.isButtonPressed(state, isRightHanded and XINPUT_GAMEPAD_RIGHT_SHOULDER or XINPUT_GAMEPAD_LEFT_SHOULDER) then
				animation.resetAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, false) --forces an update regardless of current state
--print("Here",weaponHandStr.."_"..target,weaponHandStr.."_grip_weapon" .. attachmentExtension)
				animation.updateAnimation(weaponHandStr.."_"..target, weaponHandStr.."_grip_weapon" .. attachmentExtension, true, {duration=animDuration})
			end]]
		end
	end
end

uevrUtils.registerUEVRCallback("on_module_montage_change", function(montageObject, montageName, label, animInstance)
	if montageName == nil or montageName == "" then
		--M.updateAnimationState(Handed.Left)
	--	M.updateAnimationState(Handed.Right)
	end
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.reset()
end)

uevrUtils.registerPreLevelChangeCallback(function(level)
	M.reset()
end)

return M