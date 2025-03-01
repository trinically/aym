--!nocheck

--[[ 
                  ___       ___           ___                       ___           ___           ___           ___           ___     
      ___        /\__\     /\__\         /\__\          ___        /\__\         /\  \         /\__\         /\  \         /\  \    
     /\  \      /:/  /    /:/  /        /::|  |        /\  \      /::|  |       /::\  \       /::|  |       /::\  \       /::\  \   
     \:\  \    /:/  /    /:/  /        /:|:|  |        \:\  \    /:|:|  |      /:/\:\  \     /:|:|  |      /:/\:\  \     /:/\:\  \  
     /::\__\  /:/  /    /:/  /  ___   /:/|:|__|__      /::\__\  /:/|:|  |__   /::\~\:\  \   /:/|:|  |__   /:/  \:\  \   /::\~\:\  \ 
  __/:/\/__/ /:/__/    /:/__/  /\__\ /:/ |::::\__\  __/:/\/__/ /:/ |:| /\__\ /:/\:\ \:\__\ /:/ |:| /\__\ /:/__/ \:\__\ /:/\:\ \:\__\
 /\/:/  /    \:\  \    \:\  \ /:/  / \/__/~~/:/  / /\/:/  /    \/__|:|/:/  / \/__\:\/:/  / \/__|:|/:/  / \:\  \  \/__/ \:\~\:\ \/__/
 \::/__/      \:\  \    \:\  /:/  /        /:/  /  \::/__/         |:/:/  /       \::/  /      |:/:/  /   \:\  \        \:\ \:\__\  
  \:\__\       \:\  \    \:\/:/  /        /:/  /    \:\__\         |::/  /        /:/  /       |::/  /     \:\  \        \:\ \/__/  
   \/__/        \:\__\    \::/  /        /:/  /      \/__/         /:/  /        /:/  /        /:/  /       \:\__\        \:\__\    
                 \/__/     \/__/         \/__/                     \/__/         \/__/         \/__/         \/__/         \/__/  
--]]

local Players              = game:GetService("Players")
local UserInputService     = game:GetService("UserInputService")
local RunService           = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")

local clonedPlayers              = cloneref(Players)
local clonedUserInputService     = cloneref(UserInputService)
local clonedRunService           = cloneref(RunService)
local clonedContextActionService = cloneref(ContextActionService)
local clonedReplicatedStorage    = cloneref(ReplicatedStorage)

local CONFIG = {
	DETECTION_DISTANCE    = 1000,
	AIM_SPEED             = 8,
	AIM_ACCURACY          = 100,
	ACTIVE                = true,
	TELEPORT_MODE         = false, 
	WALL_DETECTION        = true,
	EXCLUDE_NPCS          = false,
	EXCLUDE_PLAYERS       = false,
	EXCLUDE_TEAMMATES     = false,
	TOGGLE_KEY            = Enum.KeyCode.F,
	TELEPORT_TOGGLE_KEY   = Enum.KeyCode.Q,
	VERSION               = "v1.3 Gamesense fixed",
	ACTION_NAME           = "ToggleAimston",
	RETARGET_INTERVAL     = 5,
	ZIGZAG_FREQUENCY      = 7,
	ZIGZAG_AMPLITUDE      = 3,
	JUMP_COOLDOWN         = 0.1,
	TARGET_DISTANCE       = 5,
	MAX_VERTICAL_DISTANCE = 20,
	CLICK_RANGE           = 32,
	CPS                   = 50,
	CPS_VARIATION         = 2,
	TELEPORT_ACTION_NAME  = "ToggleTeleportMode",
	TELEPORT_PATTERN      = {
		AWAY_DISTANCE     = 100,
		RETURN_DISTANCE   = 2,
		COOLDOWN          = 0.2,
	},
}

local LocalPlayer = cloneref(clonedPlayers.LocalPlayer)
local Character   = cloneref(LocalPlayer.Character)
local camera      = workspace.CurrentCamera
local target, lastRetarget = nil, 0
local lastTargetY = nil
local bridging = false
local lastHealth = nil
local performActionLast = 0
local lastDestination = nil

local function getToolBySlot(slot)
	local tools = {}
	for _, tool in ipairs(Character and Character:GetChildren() or {}) do
		if tool:IsA("Tool") then
			table.insert(tools, tool)
		end
	end
	for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
		if tool:IsA("Tool") then
			table.insert(tools, tool)
		end
	end
	return tools[slot]
end

local function isLineOfSightClear(startPos, endPos, ignoreList)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = ignoreList or {}
	local rayResult = workspace:Raycast(startPos, (endPos - startPos), rayParams)
	return (rayResult == nil)
end

local function getTarget()
	if not LocalPlayer or not Character or not Character.PrimaryPart then
		warn("getTarget: Invalid LocalPlayer or Character")
		return nil
	end
	local closest = nil
	local maxDist = CONFIG.DETECTION_DISTANCE or 100
	local playerPosition = Character.PrimaryPart.Position
	for _, model in pairs(workspace:GetDescendants()) do
		if not model:IsA("Model") or not model:FindFirstChildOfClass("Humanoid") or model == Character then
			continue
		end
		local part = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		if not part then continue end
		local d = (part.Position - playerPosition).Magnitude
		local verticalDifference = math.abs(part.Position.Y - playerPosition.Y)
		if d > maxDist or verticalDifference > CONFIG.MAX_VERTICAL_DISTANCE then continue end
		local plr = Players:GetPlayerFromCharacter(model)
		local skipTarget = (plr and CONFIG.EXCLUDE_PLAYERS) or (not plr and CONFIG.EXCLUDE_NPCS) or (plr and CONFIG.EXCLUDE_TEAMMATES and plr.Team == LocalPlayer.Team)
		if skipTarget then continue end
		if not closest or d < maxDist then
			closest, maxDist = model, d
		end
	end
	return closest
end

local function getAimPart(target)
	if not target or not target:FindFirstChild("Humanoid") then return nil end
	return target:FindFirstChild("Head") or target.PrimaryPart
end

local function aimlock()
	if not CONFIG.ACTIVE then return end
	if target and target.PrimaryPart and Character and Character.PrimaryPart then
		local part = getAimPart(target)
		if part then
			local aimPos = part.Position
			local cf = CFrame.new(camera.CFrame.Position, aimPos)
			camera.CFrame = camera.CFrame:Lerp(cf, CONFIG.AIM_SPEED / 10)
		end
	else
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function performAction()
	local now = workspace.DistributedGameTime
	local actualCPS = CONFIG.CPS + math.random(-CONFIG.CPS_VARIATION, CONFIG.CPS_VARIATION)
	local actionInterval = 1 / actualCPS
	if now - performActionLast < actionInterval then
		return
	end
	local isBuilding = false
	if target and target.PrimaryPart then
		local currentTargetY = target.PrimaryPart.Position.Y
		if lastTargetY and (currentTargetY - lastTargetY) > 5 then
			isBuilding = true
		end
		lastTargetY = currentTargetY
	end
	local tool
	if isBuilding then
		tool = getToolBySlot(3)
	else
		tool = getToolBySlot(1)
	end
	if tool then
		if not tool.Parent or tool.Parent ~= Character then
			Character.Humanoid:EquipTool(tool)
		end
		tool:Activate()
		performActionLast = now
	end
end

local function TellyBridge(target)
	bridging = true
	local currentPos = Character.PrimaryPart.Position
	local targetPos = target.PrimaryPart.Position
	local horizontalDiff = Vector3.new(targetPos.X - currentPos.X, 0, targetPos.Z - currentPos.Z)
	local humanoid = Character:FindFirstChild("Humanoid")
	local backwardDir
	if horizontalDiff.Magnitude < 2 then
		backwardDir = Vector3.new(0, 0, 0)
	else
		backwardDir = (currentPos - targetPos).Unit
	end
	local desiredPosition = currentPos
	if backwardDir.Magnitude > 0 then
		desiredPosition = currentPos + backwardDir * 3
	end
	desiredPosition = Vector3.new(desiredPosition.X, targetPos.Y + 3.5, desiredPosition.Z)
	if humanoid then
		humanoid:MoveTo(desiredPosition)
		humanoid.Jump = true
	end
	local camPos = camera.CFrame.Position
	local lookPoint
	if horizontalDiff.Magnitude < 2 then
		lookPoint = camPos + Vector3.new(0, -1, 0)
	else
		local horizontalComponent = (currentPos - targetPos).Unit
		lookPoint = camPos + horizontalComponent + Vector3.new(0, -1, 0)
	end
	local desiredCFrame = CFrame.new(camPos, lookPoint)
	camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.2)
	local tool = getToolBySlot(3)
	if tool then
		if not tool.Parent or tool.Parent ~= Character then
			Character.Humanoid:EquipTool(tool)
		end
		tool:Activate()
	end
end

local function TeleportTo(target)
	if not Character or not Character.PrimaryPart or not target or not target.PrimaryPart then
		return
	end
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not CONFIG.TELEPORT_MODE then
			connection:Disconnect()
			return
		end
		local behindDirection = -target.PrimaryPart.CFrame.LookVector
		local behindPosition = target.PrimaryPart.Position + behindDirection * 4
		Character:SetPrimaryPartCFrame(CFrame.new(behindPosition, target.PrimaryPart.Position))
	end)
	return connection
end

local function MoveTo(target)
	if not target or not target.PrimaryPart or not Character or not Character:FindFirstChild("Humanoid") then
		return false
	end
	local humanoid = Character:FindFirstChild("Humanoid")
	local currentPos = Character.PrimaryPart.Position
	local targetPos  = target.PrimaryPart.Position
	local verticalDiff = targetPos.Y - currentPos.Y
	if verticalDiff > 3 then
		TellyBridge(target)
		return true
	end
	local direction = (targetPos - currentPos).Unit
	local timeNow = workspace.DistributedGameTime
	local strafeDir = Vector3.new(-direction.Z, 0, direction.X)
	local strafeOffset = strafeDir * (math.sin(timeNow * CONFIG.ZIGZAG_FREQUENCY + math.rad(math.random(0,360))) * CONFIG.ZIGZAG_AMPLITUDE)
	local randomOffset = Vector3.new(math.random(-1,1), 0, math.random(-1,1))
	local desiredPosition = targetPos - direction * CONFIG.TARGET_DISTANCE + strafeOffset + randomOffset
	if CONFIG.WALL_DETECTION then
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {Character, target}
		local rayResult = workspace:Raycast(currentPos, (targetPos - currentPos), rayParams)
		if rayResult then
			desiredPosition = targetPos - direction * CONFIG.TARGET_DISTANCE + strafeDir * CONFIG.ZIGZAG_AMPLITUDE
		end
	end
	if not lastDestination or (lastDestination - desiredPosition).Magnitude > 1 then
		humanoid:MoveTo(desiredPosition)
		lastDestination = desiredPosition
	end
	humanoid.WalkSpeed = 16
	local distance = (targetPos - currentPos).Magnitude
	if distance <= CONFIG.CLICK_RANGE then
		performAction()
	end
	return true
end

local function toggle(_, state)
	if state ~= Enum.UserInputState.Begin then return end
	CONFIG.ACTIVE = not CONFIG.ACTIVE
	target = nil
	if not CONFIG.ACTIVE and Character then
		local humanoid = Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:MoveTo(Character.PrimaryPart.Position)
		end
	end
	if CONFIG.ACTIVE then
		print(string.char(65,121,109,32,101,110,97,98,108,101,100))
	else
		print(string.char(65,121,109,32,100,105,115,97,98,108,101,100))
	end
end

local function toggleTeleportMode(_, state)
	if state ~= Enum.UserInputState.Begin then return end
	CONFIG.TELEPORT_MODE = not CONFIG.TELEPORT_MODE
	if CONFIG.TELEPORT_MODE then
		print(string.char(84,101,108,101,112,111,114,116,32,101,110,97,98,108,101,100))
	else
		print(string.char(84,101,108,101,112,111,114,116,32,100,105,115,97,98,108,101,100))
	end
end

ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true, CONFIG.TOGGLE_KEY, Enum.KeyCode.ButtonR3)
ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true, CONFIG.TELEPORT_TOGGLE_KEY)

if UserInputService.TouchEnabled then
	ContextActionService:BindAction(CONFIG.ACTION_NAME, toggle, true)
	ContextActionService:SetPosition(CONFIG.ACTION_NAME, UDim2.new(1, -280, 0, 10))
	ContextActionService:SetTitle(CONFIG.ACTION_NAME, "Aym")
	ContextActionService:BindAction(CONFIG.TELEPORT_ACTION_NAME, toggleTeleportMode, true)
	ContextActionService:SetPosition(CONFIG.TELEPORT_ACTION_NAME, UDim2.new(1, -280, 0, 70))
	ContextActionService:SetTitle(CONFIG.TELEPORT_ACTION_NAME, "TP")
end

print(string.char(82,117,110,110,105,110,103,32,97,121,109,32) .. CONFIG.VERSION)

RunService.Heartbeat:Connect(function()
	if not CONFIG.ACTIVE then return end
	if not Character or not Character:FindFirstChild("Humanoid") then return end
	local now = workspace.DistributedGameTime
	local shouldRetarget = now - lastRetarget >= CONFIG.RETARGET_INTERVAL or not target or not target:IsA("Model") or not target:FindFirstChildOfClass("Humanoid")
	if shouldRetarget then
		target = getTarget()
		lastRetarget = now
	end
	local currentHealth = Character.Humanoid.Health
	if lastHealth and currentHealth < lastHealth then
		bridging = false
		if target then aimlock() end
	end
	lastHealth = currentHealth
	if target then
		MoveTo(target)
		aimlock()
	else
		camera.CameraType = Enum.CameraType.Custom
	end
	if bridging and target then
		TellyBridge(target)
	end
	Character.Humanoid.Jump = true
	coroutine.wrap(aimlock)()
end)
