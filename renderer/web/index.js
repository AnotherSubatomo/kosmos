import { LuauState } from 'https://cdn.jsdelivr.net/gh/xNasuni/luau-web@main/dist/luauweb.min.js';

const state = await LuauState.createAsync({
	// Quick-n-dirty fake require function
	require: async function (path) {
		path = path.replace("../", "").replace("./", "")

		if (path == "kosmos") {
			path = "../../src/init.luau"
		} else if (path == "demo") {
			path = "../../demo/init.luau"
		} else {
			path = "../../" + path + ".luau"
		}

		const source = await fetch(path).then(r => r.text())
		const main = state.loadstring(source, path, true)
		const result = await main()

		return result
	}
});

const demo_source = await fetch('./init.luau').then(r => r.text())
const demo_main = state.loadstring(demo_source, "kosmos-demo", true)
const program = await demo_main()

const width = program[0]
const height = program[1]
const frame = program[2]

canvas.width = width
canvas.height = height

canvas.style.width = "100vw"
canvas.style.height = "100vh"
canvas.style.objectFit = "contain"

const ctx = canvas.getContext("2d")
const image_data = ctx.createImageData(width, height)
const pixels = new Uint8ClampedArray(width * height * 4)

let last_time = 0

async function loop(time) {
	let dt = (time - last_time) / 1000
	last_time = time

	let image_string = (await frame(dt))[0]

	for (let i = 0; i < pixels.length; i++) {
		pixels[i] = image_string.charCodeAt(i)
	}

	image_data.data.set(pixels)
	ctx.putImageData(image_data, 0, 0)

	requestAnimationFrame(loop)
}

requestAnimationFrame(loop)