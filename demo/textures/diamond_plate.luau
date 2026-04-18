
--!strict
--!optimize 2
--!native

if _G.ROBLOX then
	local Asset = game:GetService 'AssetService'
	local TextureContent = Content.fromAssetId(14210706279)

	local Image = Asset:CreateEditableImageAsync(TextureContent)
	local ImageSize = Image.Size
	local ImageData = Image:ReadPixelsBuffer(Vector2.zero, ImageSize)

	return {
		width = ImageSize.x,
		height = ImageSize.y,
		data = ImageData
	}
else
	return require('./default')
end