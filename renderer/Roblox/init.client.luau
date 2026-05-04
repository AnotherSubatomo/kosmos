
--!strict
--!optimize 2
--!native

_G.ROBLOX = true

local program = require("./kosmos-renderer/demo")
local frame = program.frame
local input = program.input
local get_frame_budget_consumed = program.get_frame_budget_consumed

local view_size = Vector2.new(program.width, program.height)

local W, S, A, D, E, Q = 119, 115, 97, 100, 101, 113

local function GetMoveDirection(keys: {InputObject}): (vector)
	local forward, back = false, false
	local left, right = false, false
	local up, down = false, false

	for _, key in keys do
		local code = key.KeyCode.Value
		if code == W then forward = true
		elseif code == S then back = true
		elseif code == A then left = true
		elseif code == D then right = true
		elseif code == E then up = true
		elseif code == Q then down = true
		end
	end

	local right_move, up_move, forward_move = 0, 0, 0
	
	if forward then forward_move += 1
	elseif back then forward_move -= 1
	elseif left then right_move += 1
	elseif right then right_move -= 1
	elseif up then up_move += 1
	elseif down then up_move -= 1
	end

	return vector.create(right_move, up_move, forward_move)
end

local function main()
	local New = Instance.new
	local Players = game:GetService 'Players'
	local Asset = game:GetService 'AssetService'
	local Run = game:GetService 'RunService'
	local UserInput = game:GetService 'UserInputService'

	local Client = Players.LocalPlayer

	local UI = New 'ScreenGui'
	UI.ResetOnSpawn = false
	UI.IgnoreGuiInset = true
	UI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local FrameBudgetDebug = New 'TextLabel'
	FrameBudgetDebug.AutomaticSize = Enum.AutomaticSize.XY
	FrameBudgetDebug.BackgroundColor3 = Color3.fromHex '000000'
	FrameBudgetDebug.BorderColor3 = Color3.fromHex '000000'
	FrameBudgetDebug.BorderSizePixel = 2
	FrameBudgetDebug.AnchorPoint = Vector2.new(1, 0)
	FrameBudgetDebug.Position = UDim2.new(1, -20, 0, 20)
	FrameBudgetDebug.Size = UDim2.fromScale(0, 0)
	FrameBudgetDebug.ZIndex = 1
	FrameBudgetDebug.FontFace = Font.fromName 'RobotoMono'
	FrameBudgetDebug.TextColor3 = Color3.fromHex 'c86809'
	FrameBudgetDebug.TextSize = 12

	local Backdrop = New 'Frame'
	Backdrop.Size = UDim2.fromScale(1, 1)
	Backdrop.BackgroundColor3 = Color3.fromHex '000000'
	Backdrop.ZIndex = -1

	local Viewport = New 'ImageLabel'
	Viewport.Size = UDim2.fromScale(1, 1)
	Viewport.Position = UDim2.fromScale(0.5, 0.5)
	Viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	Viewport.BackgroundTransparency = 1
	Viewport.ResampleMode = Enum.ResamplerMode.Pixelated

	local AspectRatio = New 'UIAspectRatioConstraint'
	AspectRatio.AspectRatio = view_size.x / view_size.y
	AspectRatio.Parent = Viewport

	local Image = Asset:CreateEditableImage { Size = view_size }
	local ImageContent = Content.fromObject(Image)

	Run.PreRender:Connect(function(delta: number)
		local mouse_delta = (UserInput:GetMouseDelta() :: any) :: vector
		local move_direction = GetMoveDirection(UserInput:GetKeysPressed())
		input(mouse_delta, move_direction)

		local ImageBuffer = frame(delta)
		Image:WritePixelsBuffer(Vector2.zero, view_size, ImageBuffer)

		local budget = get_frame_budget_consumed() * 1000 // 1 / 1000
		FrameBudgetDebug.Text = `Frame budget consumed: {budget}%`
	end)

	Viewport.ImageContent = ImageContent
	Viewport.Parent = UI
	Backdrop.Parent = UI
	FrameBudgetDebug.Parent = UI
	UI.Parent = Client.PlayerGui
end

main()