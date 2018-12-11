package components;

import math.Quat;
import math.Vec3;
import math.Mat4;

class Transform {
	public var position:      Vec3 = new Vec3(0, 0, 0);
	public var orientation:   Quat = new Quat(0, 0, 0, 1);
	public var velocity:      Vec3 = new Vec3(0, 0, 0);
	public var scale:         Vec3 = new Vec3(1, 1, 1);
	public var offset:        Vec3 = new Vec3(0, 0, 0);
	public var is_static:     Bool = false;
	public var matrix:        Mat4;
	public var normal_matrix: Mat4;

	public var snap_to: Quat;
	public var snap: Bool;
	public var slerp: Float;

	public inline function new() {}

	public function update() {
		matrix = Mat4.from_srt(position + offset, orientation, scale);

		var inv = Mat4.inverse(matrix);
		inv.transpose();
		normal_matrix = inv;
	}

	public function copy() {
		var ret = new Transform();
		ret.position.set_from(position);
		ret.orientation.set_from(orientation);
		ret.velocity.set_from(velocity);
		ret.offset.set_from(offset);
		ret.scale.set_from(scale);

		return ret;
	}
}
