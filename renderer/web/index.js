import { LuauState } from 'https://cdn.jsdelivr.net/gh/xNasuni/luau-web@main/dist/luauweb.min.js';

const state = await LuauState.createAsync({
	// Quick-n-dirty fake require function
	require: async function (path) {
		path = path.replace("./", "")

		if (path == "kosmos") {
			path = "../../src/init.luau"
		} else {
			path = "../../" + path + ".luau"
		}

		const source = await fetch(path).then(r => r.text());
		const main = state.loadstring(source, path, true);
		const result = await main();

		//console.log(result)
		return result;
	}
});

const demo_source = await fetch('../../demo/init.luau').then(r => r.text());
const demo_main = state.loadstring(demo_source, "kosmos-demo", true);
const program = await demo_main();

// NOTE: Discontinued & not working as of now because of confusion
// on how the module actually works, the library author has been asked
// and a response is yet to be received.
 
console.log(program);
// Outputs: [Proxy(Object)]
// Okay... but,
console.log(program.width, program.height, program.frame);
// Expected output: 320, 240, frame()
// Actual output: undefined, undefined, undefined