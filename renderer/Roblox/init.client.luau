
--!strict
--!optimize 2
--!native

local program = require(script.program)
local frame = program.frame

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

	local AspectRatio = New 'UIAspectRatioConstraint'
	AspectRatio.AspectRatio = program.width / program.height
	AspectRatio.Parent = Viewport

	local Image = Asset:CreateEditableImage { Size = program.size }
	local ImageContent = Content.fromObject(Image)

	Run.PreRender:Connect(function(delta: number)
		local ImageBuffer = frame(delta)
		Image:WritePixelsBuffer(Vector2.zero, program.size, ImageBuffer)
	end)

	Viewport.ImageContent = ImageContent
	Viewport.Parent = UI
	UI.Parent = Client.PlayerGui
end

main()