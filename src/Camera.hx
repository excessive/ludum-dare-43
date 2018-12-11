import math.Utils;
import math.Vec3;
import math.Quat;
import math.Mat4;
import math.Frustum;

class Camera {
	public var fov:            Float = 70;
	public var target_offset:  Float = 1.525;
	public var orbit_distance: Float = 4.5;

	public var freeze_position: Bool = false;

	public var last_position: Vec3;
	public var target:        Vec3;
	public var last_target:   Vec3;
	public var orientation = new Quat(0, 0, 0, 1);
	public var last_orientation = new Quat(0, 0, 0, 1);
	public var view:          Mat4  = new Mat4();
	public var projection:    Mat4  = new Mat4();
	public var clip_distance: Float = 999;
	public var near:          Float = 1.0;
	public var far:           Float = 750.0;

	var mouse_sensitivity: Float = 0.2;
	var pitch_limit_up: Float = 0.9;
	var pitch_limit_down: Float = 0.9;

	var up    = Vec3.up();

	public var frustum(default, null): Frustum;

	public function new(target: Vec3) {
		this.target    = target + new Vec3(0.0, 0.01, 0);
		this.last_target = this.target.copy();
		this.last_position = this.target.copy();
	}

	inline function real_orientation(mix: Float): Quat {
		var otn = this.orientation;
		if (mix < 1.0) {
			otn = Quat.slerp(this.last_orientation, this.orientation, mix);
		}
		return otn;
	}

	inline function real_target(mix: Float): Vec3 {
		var t = Utils.clamp(mix, 0.0, 1.0);
		var tgt = Vec3.lerp(this.last_target, this.target, t);
		return tgt + new Vec3(0, 0, this.target_offset);
	}

	public function rotate_xy(mx: Float, my: Float) {
		var sensitivity = this.mouse_sensitivity;
		var mouse_direction = {
			x: Utils.rad(-mx * sensitivity),
			y: Utils.rad(-my * sensitivity)
		};

		var direction = this.orientation.apply_forward();

		// get the axis to rotate around the x-axis.
		var axis = Vec3.cross(direction, this.up);
		axis.normalize();

		// First, we apply a left/right rotation.
		this.orientation = Quat.from_angle_axis(mouse_direction.x, this.up) * this.orientation;

		// Next, we apply up/down rotation.
		// up/down rotation is applied after any other rotation (so that other rotations are not affected by it),
		// hence we post-multiply it.
		var new_orientation = this.orientation * Quat.from_angle_axis(mouse_direction.y, Vec3.unit_x());
		var new_pitch       = Vec3.dot(new_orientation * Vec3.unit_y(), this.up);

		// Don't rotate up/down more than this.pitch_limit.
		// We need to limit pitch, but the only reliable way we're going to get away with this is if we
		// calculate the new orientation twice. If the new rotation is going to be over the threshold and
		// Y will send you out any further, cancel it out. This prevents the camera locking up at +/-PITCH_LIMIT
		if (new_pitch >= this.pitch_limit_up) {
			mouse_direction.y = Math.min(0, mouse_direction.y);
		}
		else if (new_pitch <= -this.pitch_limit_down) {
			mouse_direction.y = Math.max(0, mouse_direction.y);
		}

		this.orientation = this.orientation * Quat.from_angle_axis(mouse_direction.y, Vec3.unit_x());

		// Apply rotation to camera direction
		// this.direction = this.orientation.apply_forward();
	}

	public function update(w: Float, h: Float, mix: Float = 1.0) {
		var orientation = real_orientation(mix);
		var dir = orientation.apply_forward();

		var target = real_target(mix);
		if (this.freeze_position) {
			this.view = Mat4.look_at(this.last_position, target + dir * 0.001, this.up);
		}
		else {
			var pos = dir * -this.orbit_distance;
			this.last_position = target + pos;

			var look = Mat4.look_at(target, target + dir * 0.001, this.up);
			var offset = Mat4.translate(-pos);
			this.view = look * offset;
		}

		var aspect = Math.max(w / h, h / w);
		var aspect_inv = Math.min(w / h, h / w);

		var fovy = this.fov * aspect_inv;
		this.projection = Mat4.from_perspective(fovy, aspect, this.near, this.far);

		this.frustum = (this.projection * this.view).to_frustum();
	}
}
