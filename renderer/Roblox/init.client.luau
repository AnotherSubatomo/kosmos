
--!strict
--!optimize 2
--!native

local program = require("./kosmos-renderer/demo")
local frame = program.frame

local view_size = Vector2.new(program.width, program.height)

local function main()
	local New = Instance.new
	local Players = game:GetService 'Players'
	local Asset = game:GetService 'AssetService'
	local Run = game:GetService 'RunService'

	local Client = Players.LocalPlayer

	local UI = New 'ScreenGui'
	UI.ResetOnSpawn = false
	UI.IgnoreGuiInset = false
	UI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

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
		local ImageBuffer = frame(delta)
		Image:WritePixelsBuffer(Vector2.zero, view_size, ImageBuffer)
	end)

	Viewport.ImageContent = ImageContent
	Viewport.Parent = UI
	UI.Parent = Client.PlayerGui
end

main()