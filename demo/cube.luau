
--!strict
--!optimize 2
--!native

return {
	vertices = { 
		vector.create(0.25, 0.25, 0.25),
		vector.create(-0.25, 0.25, 0.25),
		vector.create(-0.25, -0.25, 0.25),
		vector.create(0.25, -0.25, 0.25),

		vector.create(0.25, 0.25, -0.25),
		vector.create(-0.25, 0.25, -0.25),
		vector.create(-0.25, -0.25, -0.25),
		vector.create(0.25, -0.25, -0.25),
	};

	faces = {
		{0, 1, 2},
		{0, 2, 3},
		{4, 6, 5},
		{4, 7, 6},
		{0, 5, 1},
		{0, 4, 5},
		{3, 2, 6},
		{3, 6, 7},
		{0, 3, 7},
		{0, 7, 4},
		{1, 5, 6},
		{1, 6, 2},
	};
}