package render;

// import math.Vec3;
import math.Mat4;
import components.Material;

import lua.Table;

typedef DrawCommand = {
	xform_mtx: Mat4,
	normal_mtx: Mat4,
	mesh: MeshView,
	material: Material,
	bones: Table<Dynamic, Dynamic>
}
