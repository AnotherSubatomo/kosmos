
--!strict
--!optimize 2
--!native

local program = require('../demo')

-- All this ugly, hacky, bullshiit is done to circumvent the data proxy
-- bullshit LuauWeb does. I absolutely cannot wrap my head around why this
-- is the case; I do not get JS safety, and frankly, the web is a fucking joke.
-- No hate to the LuauWeb author, they're probably just trying their best to
-- make it secure, but oh my lord is this such a pain in the ass. I have spent
-- an ungodly amount of time trying to figure this bullshit out so I feel like
-- I have every right to write this block of angry text.

local frame = program.frame
local function luau_web_compatible_frame(delta: number): (string)
	return buffer.tostring(frame(delta))
end

return program.width, program.height, luau_web_compatible_frame