--[[Variables]]--

-- Services

local ReplicatedStorage = game:GetService('ReplicatedStorage')
local UserInputService = game:GetService('UserInputService')
local ContextActionService = game:GetService('ContextActionService')
local TweenService = game:GetService('TweenService')
local PlayersService = game:GetService('Players')
local RunService = game:GetService('RunService')

-- Objects

local Data = ReplicatedStorage:WaitForChild('Data')
local Player = PlayersService.LocalPlayer
local Mouse = Player:GetMouse()

local PlayerGui = script.Parent.Parent.Parent
local ShipGuiFolder = script.Parent.Parent
local ShipGui = ShipGuiFolder:WaitForChild('ShipGui')
local ChatGui = PlayerGui:WaitForChild('Chat')
local ChatInstances = ChatGui:GetDescendants()
local ChatBar

for _, Gui in pairs(ChatInstances) do
	if Gui.Name ~= "ChatBar" then continue else
		ChatBar = Gui
		break
	end
end

local Remotes = ReplicatedStorage:WaitForChild('Remotes')
local ShipRemotes = Remotes:WaitForChild('Ship')

local UpdateSpeed = ShipRemotes:WaitForChild('UpdateSpeed')
local UpdatePitch = ShipRemotes:WaitForChild('UpdatePitch')
local UpdateYaw = ShipRemotes:WaitForChild('UpdateYaw')

local Modules = ReplicatedStorage:WaitForChild('Modules')
local InfoModules = Modules:WaitForChild('Info')

-- Data

local RenderPriority = require(InfoModules:WaitForChild('RenderPriority'))
local FormattedItems = require(InfoModules:WaitForChild('FormattedItems'))
local ShipControls = require(Data:WaitForChild('ShipControls')) -- These are a list of features for other scripts to use

local KeyCodes = Enum.KeyCode

local CameraModule = require(ReplicatedStorage:WaitForChild('CameraModule'))

local MinimumZoom = 0.5
local MaximumZoom = 12.0

local PlayerModule = require(Player.PlayerScripts:WaitForChild("PlayerModule"))
local PlayerControls = PlayerModule:GetControls()

local Camera = workspace.CurrentCamera

local Infinity = math.huge
local fullRad = math.pi -- A full 3 radian or 180 degrees

local Dividen = 2 -- The value that the stats that are distance based are divided by

local CameraOffset: Vector3Value = ShipControls.CameraOffset -- A vector3 value used to offest the camera by the set amount (Used for camerashake in this case)
local CameraLockedValue: BoolValue = ShipControls.CameraLocked -- A bool value allowing other scripts to forcibly lock & unlock the camera turning and centres camera to the front of the ship
local CameraZoomValue: NumberValue = ShipControls.CameraZoom -- Sets the Camera Zoom to a certain value
local MovementDisabled: BoolValue = ShipControls.MovementDisabled -- Disabling player control over ship
local StopShip: BindableFunction = ShipControls.StopShip -- Allows other scripts to initiate a stopShip event, this will be cancelled if the player tries to move so use with value above
local CameraMovementLocked: BoolValue = ShipControls.CameraMovementLocked -- a bool value simply disabling camera movement
local CameraZoomLocked: BoolValue = ShipControls.CameraZoomLocked -- Disables zooming for the player (Used with CameraZoomValue)
local InWarp: BoolValue = ShipControls.InWarp -- Used for engine VFX when in warp
local IsCharging: BoolValue = ShipControls.IsCharging -- Safety Check for engine VFX for warping
local CurrentSpeed: NumberValue = ShipControls.CurrentSpeed -- Current Speed, a value set from this script for other scripts to use for stuff like VFX.
local WarpTime: NumberValue = ShipControls.WarpTime -- How long has it been since the warp started (Used for engine VFX)
local WarpTimeLeft: NumberValue = ShipControls.WarpTimeLeft -- How long until the warp ends (Used for engine VFX)

local EngineAttachments = {
	EndAttachment1 = 4.56,
	EndAttachment2 = 3.39,
	EndAttachment3 = 1.74,
	EndAttachment4 = 0.97,
	StartAttachment = 0
} -- A bunch of values used to position the engine attachments for the engine VFX  (multiplied by engine width so the engine VFX is to size) 

local Windth1 = 0.194

local EngineBeams = {
	Beam1 = 0.80,
	Beam2 = 0.61,
	Beam3 = 0.41,
	Beam4 = 0.22,
} -- A bunch of values that determine the beams width (multiplied by engine width so the engine VFX is to size) 

local EngineBeamsTransparency = {
	Beam1 = .5,
	Beam2 = .75,
	Beam3 = .7,
	Beam4 = .7,
} -- The start transparency of every beam (the end is always 1) used to lerp their transparency

local DefaultEngineColor = Color3.fromRGB(2, 33, 48)
local FullEngineColor = Color3.fromRGB(7, 110, 165)

local WarpEngineColor = Color3.fromRGB(255, 15, 159)

local CustomControlsList = {KeyCodes.X, KeyCodes.C, KeyCodes.B, KeyCodes.LeftShift, KeyCodes.RightShift, KeyCodes.LeftAlt}

-- Functions

local function lerp(a, b, t) -- simple linear interpolation used here for VFX
	return a + (b - a) * t
end

local TInsert = table.insert -- this function has been used alot so decided to set it to a variable

--[[Script]]--

RunService:BindToRenderStep("MouseLock",Enum.RenderPriority.Last.Value+1,function()
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
end)

ShipControls.IsMouseLocked:GetPropertyChangedSignal('Value'):Connect(function()
	if ShipControls.IsMouseLocked.Value >= 1 then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		RunService:UnbindFromRenderStep("MouseLock")
	else
		RunService:BindToRenderStep("MouseLock",Enum.RenderPriority.Last.Value+1,function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end)
	end
end)

local Pilot = {}

function Pilot.new(ShipModel:Model, NavigationStats, ShipType, ShipShield:Part)
	local DefaultShipModel:Model = FormattedItems[ShipType].Model

	PlayerControls:Disable() -- Forcibly disabling player movement
	local Connections = {} -- List of connections later disconnected when pilot is destroyed

	local SpeedRange = NavigationStats.Speed -- Range of Minimum & Maximum speed
	local AccelRange = NavigationStats.Accel -- Range for Negative & Positive speed accel (Min = Negative, Max = Positive)
	SpeedRange = NumberRange.new(SpeedRange.Min / Dividen, SpeedRange.Max / Dividen) -- Dividing speed by dividen since it's distance based
	AccelRange = NumberRange.new(AccelRange.Min / Dividen, AccelRange.Max / Dividen)-- Dividing accel by dividen since it's distance based

	local Primary = ShipModel.PrimaryPart -- Seat
	local CentreAttachment = Primary.CentreAttachment -- Used to centre camera on ship
	local Angular: AngularVelocity = Primary.Angular -- Used to rotate the ship
	local Linear: LinearVelocity = Primary.Linear -- Used to move the ship
	-- The 2 velocities above are relative to CentreAttachment
	local Engines = ShipModel:WaitForChild('Structure'):WaitForChild('Engines')

	local _, ModelSize = DefaultShipModel:GetBoundingBox() -- Later used to offset camera Y

	local Controls = {
		["Strafe"] = {0, KeyCodes.T, KeyCodes.G},
		["Accel"] = {0, KeyCodes.R, KeyCodes.F},
		["Pitch"] = {0, KeyCodes.S, KeyCodes.W},
		["Roll"] = {0, KeyCodes.Q, KeyCodes.E},
		["Yaw"] = {0, KeyCodes.A, KeyCodes.D},
	} -- List of Positive and Negative controls - (Value, Positive, Negative)	First Value of each table is used in the UpdateMovement function

	local Movement = {} -- A table containing crutial components for movement including the current speed of movement

	local function CreateMovement(Name)
		local Val = Instance.new('NumberValue') -- Speed of Movement
		Val.Value = 0
		Val.Name = Name
		local BVal = Instance.new('BoolValue') -- True if tweening
		BVal.Value = false
		local BEvent = Instance.new('BindableEvent') -- Event fired when players presses control
		Movement[Name] = {Val, BVal, BEvent}
	end

	CreateMovement("Speed")

	local DirectionalMovements = {"Pitch","Roll","Yaw","Strafe"} -- Names of secondary movements
	local DirectionalRanges = {} -- Number ranges of max & min for secondary movements

	for i, MovementType in pairs(DirectionalMovements) do
		CreateMovement(MovementType)
		DirectionalRanges[MovementType] = NavigationStats[MovementType]
	end

	local DefaultDistance = CameraModule.GetFitDistance(DefaultShipModel:GetPivot().Position, DefaultShipModel, Camera) -- The zoom step in studs for this ship based on its model, used for the camera.

	local CameraAxis = Vector2.new(0,0) -- Camera axis in degrees
	local CameraZoom = 2 -- Actual camera zoom
	local CameraZoom_Current = Instance.new('NumberValue') -- Imaginary camera zoom used for tweening
	CameraZoom_Current.Value = CameraZoom

	local ZoomTween = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	ShipShield.Transparency = 1

	local ShieldTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Linear)
	
	-- Bool variables below are all just use for logic i care not explain
	local TweeningDown = false
	local TweenedDown = false
	local TweeningUp = false
	local TweenedUp = false
	local ShieldUp = ShipShield.CanQuery -- CanQuery is turned off by the server when shield goes down so might as well take advantage of it

	local ShieldTweenZoom = 1.5 -- The minimum zoom at wich the shield appears at
	
	-- Function below determines the players shields visiblity based on zoom

	local function Update()
		ShieldUp = ShipShield.CanQuery
		if ShieldUp == false then
			local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 1})
			ShieldTween:Play()
			TweenedDown = false
			TweeningDown = false
			TweeningUp = false
			TweenedUp = true
		elseif ShieldUp then
			local Current = CameraZoom_Current.Value

			if (Current <= ShieldTweenZoom) and (not TweeningDown) and (not TweenedDown) then
				TweeningDown = true
				TweenedDown = true
				TweenedUp = false
				local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 1})
				ShieldTween:Play()
				TInsert(Connections, ShieldTween.Completed:Once(function(PBS)
					TweeningDown = false
				end))
				return
			end

			if (Current > ShieldTweenZoom) and (not TweeningUp) and (not TweenedUp) then
				TweeningUp = true
				TweenedUp = true
				TweenedDown = false
				local ShieldTween = TweenService:Create(ShipShield, ShieldTweenInfo, {Transparency = 0.9})
				ShieldTween:Play()
				TInsert(Connections, ShieldTween.Completed:Once(function()
					TweeningUp = false
				end))
				return
			end
		end
	end

	TInsert(Connections, ShipShield:GetPropertyChangedSignal('Transparency'):Connect(function()
		if TweenedDown and not TweeningDown then
			ShipShield.Transparency = 1
			return
		end
		if TweenedUp and not TweeningUp then
			ShipShield.Transparency = 1
		end
	end))

	TInsert(Connections, CameraZoom_Current:GetPropertyChangedSignal('Value'):Connect(Update)) -- Updating the shield Visibility every time player zooms

	local ZoomingIn = false
	local LookingBack = false
	local CameraLocked = false
	
	local function UpdateDistance(zoom) -- Tweens Camera Zoom Value
		if zoom < MinimumZoom or zoom > MaximumZoom then return end
		CameraZoom = zoom
		if not ZoomingIn then
			local Tween = TweenService:Create(CameraZoom_Current, ZoomTween, {Value = CameraZoom})
			Tween:Play()
		end
	end

	local function ZoomCamera(start) -- Not to be confused with UpdateDistance this function zooms the camera to 0.5 and decreases FOV allowing for a fine adjustment of turret aim
		
		if start then
			ZoomingIn = true
			local FOVTweenIn = TweenService:Create(Camera, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				FieldOfView = 50
			})
			local ZoomTweenIn = TweenService:Create(CameraZoom_Current, ZoomTween, {
				Value = 0.5
			})
			ZoomTweenIn:Play()
			FOVTweenIn:Play()
		else
			ZoomingIn = false
			local FOVTweenOut = TweenService:Create(Camera, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				FieldOfView = 70
			})
			local ZoomTweenOut = TweenService:Create(CameraZoom_Current, ZoomTween, {
				Value = CameraZoom
			})
			ZoomTweenOut:Play()
			FOVTweenOut:Play()
		end
		
	end
	
	
	-- The 2 events below were explained at their values variable
	TInsert(Connections, CameraLockedValue:GetPropertyChangedSignal("Value"):Connect(function()
		if CameraLockedValue.Value == true then
			CameraLocked = true
			CameraAxis = Vector2.new(0,0)
		else
			CameraLocked = false
		end
	end))
	
	TInsert(Connections, CameraZoomValue:GetPropertyChangedSignal("Value"):Connect(function()
		UpdateDistance(CameraZoomValue.Value)
	end))

	local CustomControls = {
		[KeyCodes.X] = function(start) -- Stops the ship
			if start then
				local Tween = TweenService:Create(Movement['Speed'][1], TweenInfo.new(Movement['Speed'][1].Value/math.abs(AccelRange.Min), Enum.EasingStyle.Linear), {Value = 0})
				Tween:Play()
				TInsert(Connections, Movement['Speed'][3].Event:Once(function()
					Tween:Cancel()
				end))
				return Tween -- Returning the tween so caller can use the completed event
			end
		end,
		[KeyCodes.C] = function(start) -- Locks camera to the front
			if (start) and CameraLockedValue.Value == false then
				CameraLocked = not CameraLocked
				if CameraLocked then
					CameraAxis = Vector2.new(0,0)
				end
			end
		end,
		[KeyCodes.B] = function(start) -- Reverses the camera X angle
			LookingBack = start
		end,
		[KeyCodes.LeftShift] = ZoomCamera,
		[KeyCodes.RightShift] = ZoomCamera,
		[KeyCodes.LeftAlt] = function(start) -- Allows Player to peek while camera is locked
			if start == false and CameraLocked then
				CameraAxis = Vector2.new(0,0)
			end
		end,
	}
	
	StopShip.OnInvoke = function()
		return CustomControls[KeyCodes.X](true)
	end

	TInsert(Connections, Mouse.Move:Connect(function()
		if (CameraMovementLocked.Value == false) then
			if (CameraLocked == false) or (UserInputService:IsKeyDown(KeyCodes.LeftAlt)) then -- LeftAl allows player to peek even if the camera is locked
				local Moved = UserInputService:GetMouseDelta()/(3 * (ZoomingIn and 3 or 1)) -- Getting the amount of pixels the mouse moved
				local ResultX, ResultY = (Moved.X + CameraAxis.X) % 360, (Moved.Y + CameraAxis.Y) % 360 -- Adding it to the currentCameraAxis and making sure it's within 360 degrees
				CameraAxis = Vector2.new(ResultX, ResultY) -- Updating CameraAxis with the new degrees
			end
		end
	end))

	TInsert(Connections, Mouse.WheelForward:Connect(function()
		if CameraZoomLocked.Value then return end
		UpdateDistance(CameraZoom-0.5) -- Updating the camera zoom with the current CameraZoom minus .5
	end))

	TInsert(Connections, Mouse.WheelBackward:Connect(function()
		if CameraZoomLocked.Value then return end
		UpdateDistance(CameraZoom+0.5) -- Updating the camera zoom with the current CameraZoom plus .5
	end))
	
	-- Function below handles the extra controls for the ship system most do not have any real functions they are mostly just logic except probably the stop one
	
	ContextActionService:BindAction("CustomControls", function(_, inputState, inputObject: InputObject)
		if inputState == Enum.UserInputState.Begin then
			CustomControls[inputObject.KeyCode](true)
		elseif inputState == Enum.UserInputState.End then
			CustomControls[inputObject.KeyCode](false)
		end
	end, false, table.unpack(CustomControlsList))

	Camera.CameraType = Enum.CameraType.Scriptable

	local function UpdateControls()
		if not ChatBar:IsFocused() then -- I'am not using ContextActionService or UserInputService for *reasons* so i got the chatBar and making sure the player is not typing
			for n, t in pairs(Controls) do
				local KeyStart = UserInputService:IsKeyDown(t[2]) and 1 or 0 -- Is the positive key down
				local KeyEnd = UserInputService:IsKeyDown(t[3]) and -1 or 0 -- Is the negative key down
				local v = KeyStart + KeyEnd -- Add both values together (both down then it's gonna be 0)
				Controls[n][1] = v -- Set it in the table for the UpdateMovement function to use
			end
		end
	end
	
	
	-- VFX Zone [START]
	
	for _, Engine in Engines:GetChildren() do
		local Neon: Part = Engine.Neon
		local SizeY = Neon.Size.Y

		Neon.Color = DefaultEngineColor
		
		local StartAttachment = Neon:FindFirstChild("StartAttachment")
		local Particle = StartAttachment:FindFirstChild("Emitter")
		Particle.Size = NumberSequence.new(SizeY/3,0)

		for _, Child in Neon:GetChildren() do
			if Child:IsA("Beam") then
				Child.Width0 = EngineBeams[Child.Name] * SizeY
				if Child.Name == "Beam4" then continue end
				Child.Width1 = Windth1 * SizeY
			end
		end
	end
	
	-- VFX Zone [END]
	
	local ShipAmbience = Primary:WaitForChild('ShipAmbience') -- An ambience SFX for the ship also acts as engine SFX
	
	local function RenderEngine()
		local EngineV = math.clamp(Movement["Speed"][1].Value/SpeedRange.Max, 0, 1) -- How fast the ship is moving based on its max speed [0,1]
		
		-- There's nothing really to explain in the code below since it's pure VFX & SFX so im not gonna bother

		ShipAmbience.Volume = lerp(.25, 2, EngineV)
		ShipAmbience.PitchEffect.Octave = lerp(1,1.25, EngineV)

		for _, Engine in Engines:GetChildren() do
			local Neon: Part = Engine.Neon
			local SizeY = Neon.Size.Y

			Neon.Color = DefaultEngineColor:Lerp(FullEngineColor, EngineV)

			local StartAttachment = Neon:FindFirstChild("StartAttachment")
			local Particle: ParticleEmitter = StartAttachment:FindFirstChild("Emitter")
			Particle.Lifetime = NumberRange.new(SizeY * EngineV)
			Particle.Rate = 50 * (EngineV)
			Particle.Speed = NumberRange.new(EngineAttachments.EndAttachment1 * SizeY)
			StartAttachment.CFrame = CFrame.lookAt(StartAttachment.Position, Neon.EndAttachment1.Position)

			for _, Child in Neon:GetChildren() do
				if Child:IsA("Attachment") then
					local Length = EngineAttachments[Child.Name]
					Child.Position = Vector3.new(Length * SizeY * EngineV * 1.5, Movement["Pitch"][1].Value * EngineV * Length/3, Movement["Yaw"][1].Value * EngineV * Length/3)
				elseif Child:IsA("Beam") then
					Child.LightEmission = EngineV
					Child.LightInfluence = EngineV
					Child.Transparency = NumberSequence.new(lerp(1, EngineBeamsTransparency[Child.Name], EngineV),1)
				end
			end
		end
	end
	
	local LastUpdate = 0

	local LastPitch = 0
	local LastYaw = 0
	
	local function UpdateMovement(DeltaTime)
		LastUpdate += DeltaTime
		
		CurrentSpeed.Value = Movement['Speed'][1].Value * Dividen
		
		-- The block of code below is used to update the server on the ships speed and if the player is currently pitching or yawing used to replicate engine effects to other clients
		
		local CPitch = Movement["Pitch"][1].Value
		local CYaw = Movement["Yaw"][1].Value
		
		local NewPitch = if CPitch > 0 then 1 elseif CPitch < 0 then -1 else 0
		local NewYaw = if CYaw > 0 then 1 elseif CYaw < 0 then -1 else 0
		
		if NewPitch ~= LastPitch then -- Making sure to not send duplicate data to server wasting network
			UpdatePitch:FireServer(NewPitch) -- Updating the server on new pitch
			LastPitch = NewPitch
		end
		if NewYaw ~= LastYaw then -- Making sure to not send duplicate data to server wasting network
			UpdateYaw:FireServer(NewYaw) -- Updating the server on new yaw
			LastYaw = NewYaw
		end
		
		if LastUpdate >= .5 then -- Instead of updating every change with a cooldown i opted for this for anti-cheat reasons
			UpdateSpeed:FireServer(Movement['Speed'][1].Value) -- Updating the server on new speed
			LastUpdate = 0
		end
		
		-- VFX Zone [START]
		
		if MovementDisabled.Value then 
			-- I'am updating the velocities here since there's a return statement at the end of this scope wich wouldn't let the code below us wich includes the code to update the velocities to run
			Angular.AngularVelocity = Vector3.new(Movement["Pitch"][1].Value, Movement["Yaw"][1].Value, Movement["Roll"][1].Value)
			Linear.VectorVelocity = Vector3.new(0, Movement['Strafe'][1].Value, -Movement['Speed'][1].Value)
			
			if IsCharging.Value then return end -- Safety check
			
			if InWarp.Value == true then -- Custom engine VFX for when in warp
				
				-- There's nothing really to explain in the code below since it's pure VFX & SFX so im not gonna bother
				
				local EngineV = 2
				
				if WarpTime.Value < 1 then
					EngineV = WarpTime.Value * 2
				elseif WarpTimeLeft.Value < 2 then
					EngineV = WarpTimeLeft.Value
				end

				for _, Engine in Engines:GetChildren() do
					local Neon: Part = Engine.Neon
					local SizeY = Neon.Size.Y

					Neon.Color = DefaultEngineColor:Lerp(WarpEngineColor, math.clamp(WarpTimeLeft.Value/2, 0, 1))

					local StartAttachment = Neon:FindFirstChild("StartAttachment")
					local Particle: ParticleEmitter = StartAttachment:FindFirstChild("Emitter")
					Particle.Lifetime = NumberRange.new(SizeY * EngineV / 4)
					Particle.Rate = 50 * EngineV
					Particle.Speed = NumberRange.new(EngineAttachments.EndAttachment1 * SizeY * EngineV * 2)
					StartAttachment.CFrame = CFrame.lookAt(StartAttachment.Position, Neon.EndAttachment1.Position)

					for _, Child in Neon:GetChildren() do
						if Child:IsA("Attachment") then
							local Length = EngineAttachments[Child.Name]
							Child.Position = Vector3.new(Length * SizeY * EngineV * 1.5, Movement["Pitch"][1].Value * EngineV * Length/3, Movement["Yaw"][1].Value * EngineV * Length/3)
						elseif Child:IsA("Beam") then
							Child.LightEmission = EngineV
							Child.LightInfluence = EngineV
							Child.Transparency = NumberSequence.new(lerp(1, EngineBeamsTransparency[Child.Name], EngineV),1)
						end
					end
				end
			else RenderEngine()
			end
			
			return
		end
		
		-- VFX Zone [END]
		
		-- Ignore the weird do ends, i was going through a phase.
		
		-- Speed
		do
			local AccelHeld = Controls['Accel'][1] -- Value gotten from the UpdateControls indicating the movements value (-1 if negative is being held +1 of positive is being held and 0 if both or none are being held)
			local SpeedValue = Movement['Speed'][1].Value -- Current speed
			local AccelV =  (if AccelHeld == 1 then AccelRange.Max elseif AccelHeld == -1 then (if SpeedValue > 0 then AccelRange.Min else AccelRange.Min/3) else 0)
			local NewAccel = AccelV * DeltaTime -- Speed to be added
			if NewAccel ~= 0 then
				Movement['Speed'][3]:Fire() -- Fires event to stop that tells other part of the script that player tried to move (used for stopShip)
				local NewSpeed = math.clamp(SpeedValue + NewAccel, SpeedRange.Min, SpeedRange.Max) -- Making sure movement doesn't go over max and min
				Movement['Speed'][1].Value = NewSpeed -- Setting the new speed for later use

			elseif SpeedValue < 0 then -- Stopping the ship if player is going backwards and is not holding down any control
				local NewSpeed = SpeedValue - (AccelRange.Min * DeltaTime)/3 -- Getting the new speed, the passive stopping speed is divided by 3 to encourage players to stop manually by throttling down
				Movement['Speed'][1].Value = math.clamp(NewSpeed, -Infinity, 0) -- Setting the new speed for later use
			end
		end

		-- Pitch, Roll, Yaw
		do
			for _, MovementType in pairs(DirectionalMovements) do
				local MovementHeld = Controls[MovementType][1] -- Value gotten from the UpdateControls indicating the movements value (-1 if negative is being held +1 of positive is being held and 0 if both or none are being held)
				local MovementCur = Movement[MovementType] -- List of values important to the movement
				local MovementValueObject = MovementCur[1] -- Value used to store the speed of the movement
				local MovementValue = MovementValueObject.Value --- How fast the movement is going
				local MovementTweening = MovementCur[2] -- Value indicating if the movement value is being tweened 
				local MovementRange = DirectionalRanges[MovementType] -- Min Max range of movement
				local MovementV = (if MovementHeld == 1 then MovementRange.Max elseif MovementHeld == -1 then MovementRange.Min else 0)
				local NewMovement = (MovementV * DeltaTime) * 2 -- Acceleration of movement
				if NewMovement ~= 0 then
					MovementTweening.Value = false
					MovementCur[3]:Fire()
					local NewSpeed = math.clamp(MovementValue + NewMovement, MovementRange.Min, MovementRange.Max) -- Making sure movement doesn't go over max and min
					MovementValueObject.Value = NewSpeed
				elseif MovementTweening.Value == false then -- Resetting the movement to 0 in a tween
					MovementTweening.Value = true -- Debounce for next frame
					local Tween = TweenService:Create(MovementValueObject, TweenInfo.new(math.abs(MovementValue)/2, Enum.EasingStyle.Linear), {Value = 0})
					Tween:Play()
					TInsert(Connections, Tween.Completed:Once(function(playBackState)
						MovementTweening.Value = false
					end))
					TInsert(Connections, MovementCur[3].Event:Once(function() -- Cancelling the stop tween of movement if player tries to move again
						Tween:Cancel()
					end))
				end
			end
		end

		RenderEngine()
		
		Angular.AngularVelocity = Vector3.new(Movement["Pitch"][1].Value, Movement["Yaw"][1].Value, Movement["Roll"][1].Value) -- Using all the values gained from the block above and applying to angular velocity
		Linear.VectorVelocity = Vector3.new(0, Movement['Strafe'][1].Value, -Movement['Speed'][1].Value) -- Using all the values gained from the block above and applying to linear velocity
	end
	
	-- Function below updates the camera CFrame with all values gathered

	local function UpdateCamera()
		local CameraOffsetVal = CameraOffset.Value
		local CameraOrientation
		if LookingBack then
			CameraOrientation = CFrame.fromEulerAnglesYXZ(-math.rad(CameraAxis.Y), fullRad-math.rad(CameraAxis.X), 0) -- Reversing the camera X angle
		else
			CameraOrientation = CFrame.fromEulerAnglesYXZ(-math.rad(CameraAxis.Y), -math.rad(CameraAxis.X), 0)
		end
		Camera.CFrame = CentreAttachment.WorldCFrame * CameraOrientation * CFrame.new(0 + CameraOffsetVal.X,ModelSize.Y + CameraOffsetVal.Y, DefaultDistance * CameraZoom_Current.Value + CameraOffsetVal.Z) -- Centring the camera at the ships PrimaryPart, offsetting it by the ships Y size and zoom + Default Zoom Distance figured for this ship adding all the offsetValues and then adding the angles
	end
	
	RunService:BindToRenderStep("SHIP_CAMERA", RenderPriority.SHIP_CAMERA, UpdateCamera)
	RunService:BindToRenderStep("SHIP_INPUT", RenderPriority.SHIP_INPUT, UpdateControls)
	RunService:BindToRenderStep("SHIP_MOVEMENT", RenderPriority.SHIP_MOVEMENT, UpdateMovement)
	
	-- In the function below we are disconnecting all the connections we've made and resetting the client to its original state before this pilot was created
	-- Currently i'am not setting the camera back to the player character since that will be handled by another script

	local function Destroy()
		for _, Connection in pairs(Connections) do
			Connection:Disconnect()
		end
		RunService:UnbindFromRenderStep("SHIP_CAMERA")
		RunService:UnbindFromRenderStep("SHIP_INPUT")
		RunService:UnbindFromRenderStep("SHIP_MOVEMENT")
		PlayerControls:Enable() -- Enabling back player movement
		Linear.VectorVelocity = Vector3.new(0,0,0)
		Angular.AngularVelocity = Vector3.new(0,0,0)
	end

	return Destroy
end

return Pilot
