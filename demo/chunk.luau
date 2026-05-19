
-- Chunked heightmap mesh generator
-- SPDX-License-Identifier: CC0-1.0

--!strict
--!optimize 2
--!native

export type raw_mesh = {
	vertices: {vector},
	uvs: {vector},
	faces: {vector}
}

local kN = 1/255 -- amplitude's theshold of negligibility

local HEIGHT_SIZE = 10
local POINT_PER_DIM, SPACING, TILING, RESOLUTION = 0, 0, 0, 0
local FREQUENCY, AMPLITUDE, OCTAVES, LACUNARITY, PERSISTENCE, MAX_AMPLITUDE = 0, 0, 0, 0, 0, 0

local function fbm(x: number, z: number): (number)
	local value = 0
	local amplitude = AMPLITUDE
	local frequency = FREQUENCY

	for _ = 1, OCTAVES do
		value += math.noise(x * frequency, z * frequency) * amplitude

		frequency *= LACUNARITY
		amplitude *= PERSISTENCE
	end

	return (value / MAX_AMPLITUDE) * HEIGHT_SIZE
end

local function SET_NOISE_CONFIGS(
	resolution: number, frequency: number, amplitude: number,
	octaves: number, lacunarity: number, persistence: number
): ()
	-- octave culling & finding the max amplitude
	local sample_amplitude = amplitude
	local amplitude_sum = 0
	for o = 1, octaves do
		if sample_amplitude <= kN then
			octaves = o - 1
			break
		end
		amplitude_sum += sample_amplitude
		sample_amplitude *= persistence
	end

	RESOLUTION, FREQUENCY, AMPLITUDE, OCTAVES, LACUNARITY, PERSISTENCE, MAX_AMPLITUDE =
		resolution, frequency, amplitude, octaves, lacunarity, persistence, amplitude_sum
end

local function SET_CHUNK_CONFIGS(tiles: number, spacing: number, tiling: number): ()
	POINT_PER_DIM, SPACING, TILING = tiles + 1, spacing, tiling
end

local function GENERATE(): (raw_mesh)
	local face_per_dim = POINT_PER_DIM - 1
	local total_vertices = POINT_PER_DIM * POINT_PER_DIM

	local uvs = table.create(total_vertices, vector.zero)
	local vertices = table.create(total_vertices, vector.zero)
	local faces = table.create(face_per_dim * face_per_dim * 2) :: {vector}

	local n_faces = 0

	-- Generate faces
	for z = 0, face_per_dim do
		local row_stride = z * POINT_PER_DIM
	
		for x = 0, face_per_dim do
			if x == 0 or z == 0 then continue end

			local ai = row_stride + x + 1
			local bi = ai - 1
			local ci = ai - POINT_PER_DIM
			local di = ci - 1

			n_faces += 2
			faces[n_faces - 1] = vector.create(ai, ci, bi)
			faces[n_faces] = vector.create(bi, ci, di)
		end
	end

	return { vertices = vertices, uvs = uvs, faces = faces }
end

local function SET_CHUNK_DATA(chunk: raw_mesh, chunk_x: number, chunk_z: number): ()
	local face_per_dim = POINT_PER_DIM - 1
	local offset_x = chunk_x * face_per_dim * SPACING
	local offset_z = chunk_z * face_per_dim * SPACING

	local uvs = chunk.uvs
	local vertices = chunk.vertices

	local n_vertices = 0

	-- Modified vertice data
	for z = 0, face_per_dim do
		for x = 0, face_per_dim do
			local height = fbm(
				(offset_x + x * SPACING) / RESOLUTION,
				(offset_z + z * SPACING) / RESOLUTION
			)

			local vertex = vector.create(x * SPACING, height, z * SPACING)

			n_vertices += 1
			vertices[n_vertices] = vertex
			uvs[n_vertices] = vector.create(x * TILING, z * TILING)
		end
	end
end

return {
	set_noise_configs = SET_NOISE_CONFIGS,
	set_chunk_configs = SET_CHUNK_CONFIGS,

	generate = GENERATE,
	set_chunk_data = SET_CHUNK_DATA,
}