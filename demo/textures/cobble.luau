
--!strict
--!optimize 2
--!native

if _G.ROBLOX then
	local Asset = game:GetService 'AssetService'
	local TextureContent = Content.fromAssetId(11916675674)

	local Image = Asset:CreateEditableImageAsync(TextureContent)
	local ImageSize = Image.Size
	local ImageData = Image:ReadPixelsBuffer(Vector2.zero, ImageSize)
	Image:Destroy()

	return {
		width = ImageSize.x,
		height = ImageSize.y,
		data = ImageData
	}
else
	return require('./default')
end