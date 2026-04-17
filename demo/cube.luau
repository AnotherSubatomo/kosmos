
--!strict
--!optimize 2
--!native

return {
	vertices = {
		-- Front
		vector.create(0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, 0.25),
		vector.create(-0.25, -0.25, 0.25),
		vector.create(0.25, -0.25, 0.25),

		-- Back
		vector.create(0.25, 0.25, -0.25),
		vector.create(-0.25, 0.25, -0.25),
		vector.create(-0.25, -0.25, -0.25),
		vector.create(0.25, -0.25, -0.25),

		-- Left
		vector.create(-0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, -0.25),
		vector.create(-0.25, -0.25, -0.25),
		vector.create(-0.25, -0.25, 0.25),

		-- Right
		vector.create(0.25, 0.25, 0.25),
		vector.create(0.25, 0.25, -0.25),
		vector.create(0.25, -0.25, -0.25),
		vector.create(0.25, -0.25, 0.25),

		-- Top
		vector.create(0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, -0.25),
		vector.create(0.25, 0.25, -0.25),

		-- Bottom
		vector.create(0.25, -0.25, 0.25),
		vector.create(-0.25, -0.25, 0.25),
		vector.create(-0.25, -0.25, -0.25),
		vector.create(0.25, -0.25, -0.25),
	};

	uvs = {
		-- each face uses full 0–1 UV square
		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),

		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),

		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),

		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),

		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),

		vector.create(1, 1),
		vector.create(0, 1),
		vector.create(0, 0),
		vector.create(1, 0),
	};

	faces = {
		-- 6 faces × 2 triangles (CCW)
		-- Front
		vector.create(1, 2, 3),
		vector.create(1, 3, 4),

		-- Back
		vector.create(5, 7, 6),
		vector.create(5, 8, 7),

		-- Left
		vector.create(9, 10, 11),
		vector.create(9, 11, 12),

		-- Right
		vector.create(13, 15, 14),
		vector.create(13, 16, 15),

		-- Top
		vector.create(17, 19, 18),
		vector.create(17, 20, 19),

		-- Bottom
		vector.create(21, 22, 23),
		vector.create(21, 23, 24),
	};
}