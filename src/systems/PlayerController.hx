package systems;

import components.Emitter.ParticleData;
import iqm.Iqm;
import math.Quat;
import math.Vec2;
import math.Vec3;
// import math.Ray;
import math.Utils;
import anim9.Anim9.Anim9Track;
import backend.Input;
import collision.Response;
import GameInput.Action;

enum QueueAnim {
	Idle;
	Jump;
	Skate;
	Slow;
	TrickA;
	GrindA;
	Grind;
	Fall;
	Land;
}

class PlayerController extends System {
	public static var tracks: {
		idle:   Anim9Track,
		jump:   Anim9Track,
		skate:  Anim9Track,
		slow:   Anim9Track,
		tricka: Anim9Track,
		grinda: Anim9Track,
		grind:  Anim9Track,
		fall:   Anim9Track,
		land:   Anim9Track
	} = {
		idle:   null,
		jump:   null,
		skate:  null,
		slow:   null,
		tricka: null,
		grinda: null,
		grind:  null,
		fall:   null,
		land:   null
	};

	static var queue_anim:  QueueAnim = Idle;
	static var was_blocked: Bool      = false;

	static var cube: IqmFile;

	static var num_grinds: Int = 2;
	static var grind_idx:  Int = 0;

	override function filter(e: Entity) {
		if (e.player != null && e.transform != null) {
			// Load animations tracks
			if(e.animation != null && tracks.idle == null) {
				tracks.idle   = e.animation.new_track("idle");
				tracks.jump   = e.animation.new_track("jump");
				tracks.skate  = e.animation.new_track("skate");
				tracks.slow   = e.animation.new_track("slow");
				tracks.tricka = e.animation.new_track("trick.a");
				tracks.grinda = e.animation.new_track("grind.a");
				tracks.grind  = e.animation.new_track("grind");
				tracks.fall   = e.animation.new_track("fall");
				// TODO
				// tracks.land   = e.animation.new_track("skate");
			}

			if (cube == null) {
				cube = Iqm.load("assets/models/debug/unit-cube.iqm");
			}

			return true;
		}
		return false;
	}

	override function process(e: Entity, dt: Float) {
		if (GameInput.pressed(MenuToggle)) {
			Input.set_relative(!Input.get_relative());
		}

		var move = Vec3.splat(0.0);
		update_controls(e, move, dt);

		update_physics(e, dt);

		// we need to move last so that blocking animations keep you frozen
		update_animation(e, dt);

		update_camera(e, move, dt);

		// Render.camera.target = e.transform.position;

		// if (follow_camera) {
		// 	Render.camera.orientation = Quat.slerp(Render.camera.orientation, e.transform.orientation, dt*2);
		// }
	}

	function update_orientation(e: Entity, move: Vec3, ml: Float, can_jump: Bool) {
		// if you're moving too slow this function won't do anything anyways.
		var vel = e.transform.velocity;
		if (vel.length() < 1e-2 && ml == 0.0) {
			return;
		}

		// Orient player
		if (e.player.rail == null) {
			var nudge = 0.0001; // prevent weird crap
			var move_angle = new Vec2(move.x, move.y + 0.0001).angle_to() - Math.PI / 2;
			var move_orientation: Quat  = Render.camera.orientation * Quat.from_angle_axis(move_angle, Vec3.up());
			move_orientation.x = 0;
			move_orientation.y = 0;
			move_orientation.normalize();

			var dir = move_orientation.apply_forward();
			var angle = new Vec2(vel.x + dir.x * nudge, vel.y + dir.y * nudge).angle_to() + Math.PI / 2;
			var speed_orientation = Quat.from_angle_axis(angle, Vec3.up());

			var hit_normal = Vec3.up();
			if (e.player.contacts.length > 0) {
				var up = Vec3.up();
				hit_normal.set_xyz(0, 0, 0);
				var hits = 0;
				for (c in e.player.contacts) {
					// ignore wall hits
					if (Vec3.dot(c.normal, up) > 0.1) {
						hits += 1;
						hit_normal += c.normal;
					}
				}
				if (hits > 0) {
					hit_normal /= hits;
				}
				// oops, only touching walls. reset.
				else {
					hit_normal.z = 1;
				}
			}

			speed_orientation = Quat.from_direction(hit_normal) * speed_orientation;
			speed_orientation.normalize();

			var mix = 0.3;
			if (!can_jump || ml == 0.0) {
				mix = 0.0;
			}
			move_orientation = Quat.slerp(speed_orientation, move_orientation, mix);

			e.transform.orientation = Quat.slerp(e.transform.orientation, move_orientation, 1/8);
		}
		else {
			var angle = new Vec2(e.transform.velocity.x, e.transform.velocity.y + 0.0001).angle_to() + Math.PI / 2;
			var rail_orientation = Quat.from_angle_axis(angle, Vec3.up());
			e.transform.orientation = Quat.slerp(e.transform.orientation, rail_orientation, 1/8);
		}
	}

	function update_controls(e: Entity, move: Vec3, dt: Float) {
		if (Main.lose) {
			queue_anim = Idle;
			return;
		}

		var can_jump = e.player.grounded || e.player.contacts.length > 0 || e.player.rail != null;

		// Move player
		var stick = GameInput.move_xy();
		move.set_xyz(stick.x, stick.y, 0);
		move.trim(1);
		var ml = move.length();

		// handle inputs only when captured
		if (!Input.get_relative() || GameInput.locked) {
			// make sure this happens regardless of input, because it
			// updates passively too.
			update_orientation(e, Vec3.splat(0.0), 0.0, can_jump);
			return;
		}

		queue_anim = Idle;

		var hit_normal = Vec3.up();

		if (e.player.contacts.length > 0) {
			e.player.gliding = false;
			hit_normal.set_xyz(0, 0, 0);

			for (c in e.player.contacts) {
				hit_normal += c.normal;
			}

			hit_normal /= e.player.contacts.length;
		}

		// Rotate camera
		var mouse_delta = Input.get_mouse_moved(true);
		var freelook_time = 2.0;

		if (mouse_delta.x != 0 || mouse_delta.y != 0) {
			Render.camera.rotate_xy(mouse_delta.x, -mouse_delta.y);
			e.player.stop_adjust = freelook_time;
		}

		var rstick = GameInput.view_xy();
		if (rstick.x != 0 || rstick.y != 0) {
			rstick.y *= -1;
			var sens = 1000 * dt;
			Render.camera.rotate_xy(rstick.x * sens, rstick.y * sens * 0.375);
			e.player.stop_adjust = freelook_time;
		}

		// Zoom camera
		var trigger = GameInput.get_value(Action.LTrigger) - GameInput.get_value(Action.RTrigger);
		var orbit   = e.player.target_distance;
		orbit      -= trigger * 4 * dt;
		e.player.target_distance = Utils.clamp(orbit, 2.5, 7.5);

		var action_angle = new Vec2(move.x, move.y + 0.0001).angle_to() - Math.PI / 2;
		var action_orientation = Render.camera.orientation * Quat.from_angle_axis(action_angle, Vec3.up());
		action_orientation.x = 0;
		action_orientation.y = 0;
		action_orientation.normalize();
		var action_direction = action_orientation.apply_forward();

		if (ml > 0) {
			queue_anim = Skate;
			if (ml < 0.65) {
				queue_anim = Slow;
			}
			var speed  = e.player.speed;

			if (e.player.rail != null) {
				speed = e.player.rail_speed;
			} else if (e.player.contacts.length == 0) {
				speed = e.player.air_speed;
			}

			var limit: Float = 999;
			if (e.player.rail != null) {
				limit = e.player.rail_speed_limit;
			}
			else if (e.player.contacts.length > 0) {
				limit = e.player.speed_limit;
			}

			var new_velocity = e.transform.velocity + action_direction * speed * ml;
			var over_speed = new_velocity.length() > limit;

			if (over_speed && new_velocity.length() > e.transform.velocity.length()) {
				new_velocity.trim(e.player.last_vel);
			}
			e.transform.velocity = new_velocity;
		}

		// Glide
		// ray casts are missing against large world triangles. this breaks everything
		// disabled until there is a reasonable solution.

		// if (GameInput.pressed(Action.Glide)) {
		// 	var can_glide = true;
		// 	var ray_offset = 0.1;
		// 	var hit = World.cast_ray(new Ray(e.transform.position + new Vec3(0, 0, ray_offset), -Vec3.up()));
		// 	trace(hit);
		// 	if (hit != null && (hit.d - ray_offset) < e.player.glide_threshold) {
		// 		trace("can't glide, too close");
		// 		can_glide = false;
		// 	}
		// 	trace(can_glide, e.player.gliding);
		// 	if (can_glide || e.player.gliding) {
		// 		trace("glide toggled");
		// 		e.player.gliding = !e.player.gliding;
		// 	}
		// }

		// If we didn't contact anything, we're falling
		if (!can_jump) {
			queue_anim = Fall;
		}

		// Jump
		if (GameInput.pressed(Action.Jump) && can_jump) {
			queue_anim     = Jump;
			var jump_power = e.player.jump_power;

			e.transform.velocity += hit_normal * jump_power;
			e.transform.position += e.transform.velocity * dt;

			e.player.rail       = null;
			e.player.rail_index = null;
		}

		// Trick
		if (GameInput.pressed(Action.Trick) && e.player.rail != null) {
			queue_anim = TrickA;
			grind_idx += 1;
			grind_idx %= num_grinds;
		}

		if (e.player.rail != null && queue_anim != TrickA) {
			queue_anim = switch (grind_idx) {
				case 0: Grind;
				case 1: GrindA;
				default: Grind; // shouldn't happen
			}
		}

		update_orientation(e, move, ml, can_jump);
	}

	function update_animation(e: Entity, dt: Float) {
		function play(track: Anim9Track, ?target: Anim9Track, immediate: Bool = false) {
			if (e.animation == null || track == null) { return; }

			if (!e.animation.find_track(track)) {
				e.animation.transition(track, 0.2);
				was_blocked = !e.animation.animations[cast track.name].loop;

				if (was_blocked) {
					track.callback = () -> {
						var into = tracks.idle;
						var len = 0.2;
						if (target != null) {
							into = target;
						}
						if (immediate) {
							len = 0.0;
						}
						e.animation.transition(into, len);
						was_blocked = false;
					}
				}
			}
		}

		if (!was_blocked) {
			switch (queue_anim) {
				case Idle:   play(tracks.idle);
				case Skate:  play(tracks.skate);
				case Slow:   play(tracks.slow);
				case Jump:   play(tracks.jump, tracks.fall, true);
				case Fall:   play(tracks.fall);
				case Grind:  play(tracks.grind);
				case GrindA: play(tracks.grinda);
				case TrickA: play(tracks.tricka);
				case Land:   play(tracks.land);
			}
		}
	}

	static function update_camera(e: Entity, move: Vec3, dt: Float) {
		if (move.lengthsq() > 0) {
			e.player.stop_adjust = Utils.max(0.0, e.player.stop_adjust - dt);
		}

		player.OrbitCamera.update_camera(e, move, dt);
		// player.PulledCamera.update_camera(e, move, dt);
	}

	function update_physics(e: Entity, dt: Float) {
		// player position is at feet but ellipsoid position at its center
		var gravity       = new Vec3(0, 0, -e.player.gravity);
		if (e.player.gliding && e.transform.velocity.z <= 0) {
			gravity.z = -e.player.gravity_glide;
		}
		if (e.player.contacts.length == 0 && e.player.rail == null) {
			var lateral_vel = e.transform.velocity.copy();
			lateral_vel.z = 0;

			var mix = Utils.min(1.0, lateral_vel.length() / e.player.air_speed_limit);
			gravity.z = Utils.lerp(gravity.z, -e.player.air_speed_fall, mix);
		}
		var radius        = e.collidable.radius;
		var visual_offset = new Vec3(0, 0, radius.z);
		var packet        = Response.update(
			e.transform.position + visual_offset,
			e.transform.velocity * dt,
			radius,
			gravity * dt,
			World.get_triangles,
			5
		);
		e.transform.position = packet.position - visual_offset;

		// small sphere at feet to determine grounded state
		// var sensor = Response.update(
		// 	e.transform.position,
		// 	Vec3.zero(),
		// 	Vec3.splat(0.125),
		// 	Vec3.zero(),
		// 	World.get_triangles,
		// 	1
		// );
		// e.player.grounded = sensor.contacts.length > 0;
		e.player.grounded = packet.contacts.length > 0;

		var old_speed = e.transform.velocity.length();
		e.transform.velocity = packet.velocity / dt;

		var speed = e.transform.velocity.length();

		// maintain velocity through rails
		if (e.player.rail != null && speed > 0) {
			e.transform.velocity.normalize();
			var target_speed = Utils.max(speed, old_speed);
			target_speed = Utils.max(target_speed, e.player.rail_stick_min);
			e.transform.velocity *= target_speed;
			speed = target_speed;
		}

		var just_landed = e.player.grounded && e.player.contacts.length == 0 && e.player.rail == null;

		e.player.contacts = packet.contacts;

		// friction boiiiii
		var friction = e.player.friction;
		var hit_normal = Vec3.up();
		if (e.player.contacts.length > 0) {
			hit_normal.set_xyz(0, 0, 0);
			for (c in e.player.contacts) {
				hit_normal += c.normal;
			}
			hit_normal /= e.player.contacts.length;
		}

		var bias = Utils.max(0.0, Vec3.dot(hit_normal, Vec3.up()));

		// if we're just grounding on this frame and hit normal is
		// approximately up: fx!
		if (just_landed && bias > 0.8 && e.transform.velocity.length() > 10) {
			var node = new SceneNode();
			var lifetime = 0.75;
			var particles = 25;
			node.emitter.push({
				data: new ParticleData(),
				enabled: true,
				limit: particles,
				pulse: lifetime,
				spawn_radius: 0.0,
				spread: 2.0,
				lifetime: lifetime,
				emission_rate: particles,
				emission_life_min: lifetime/5,
				emission_life_max: lifetime,
				drawable: IqmLoader.get_views(cube)
			});
			node.emitter[0].data.time = lifetime;
			node.transform.position.set_from(e.transform.position);

			Signal.emit("vibrate", {
				power: 1.0,
				duration: 0.1,
			});

			Main.scene.add(node);
			Signal.after(node.emitter[0].lifetime, function() {
				Main.scene.remove(node);
			});
		}

		// lower friction on slopes.
		var biased_friction = friction * bias;
		friction = Utils.lerp(friction, biased_friction, e.player.slope_friction_bias);


		if (e.player.rail != null) {
			friction = e.player.rail_friction;
			// limit    = e.player.rail_speed_limit;
		}
		else if (e.player.contacts.length == 0) {
			friction = e.player.air_friction;
			// limit = 999; // max air speed can be really fast, it's fine
		}
		else {
			var limit = Utils.max(e.player.speed_limit, e.player.rail_speed_limit);
			e.transform.velocity.trim(limit);
		}

		// this is only used for UI, show lateral speed.
		var lateral_vel = e.transform.velocity.copy();
		lateral_vel.z = 0;
		e.player.last_vel = e.transform.velocity.length();
		e.player.last_speed = lateral_vel.length();

		e.transform.velocity *= 1.0 - friction;

		// spark particles when on rail
		e.emitter[0].enabled = e.player.rail != null;

		// handle sliding on rails
		player.RailsHelper.update(e, dt);

		// respawn
		if (e.transform.position.z < World.kill_z) {
			e.transform.position.set_from(Main.spawn_transform.position);
			e.transform.orientation.set_from(Main.spawn_transform.orientation);
			e.transform.velocity *= 0;
			e.last_tx.position = e.transform.position.copy();
			e.last_tx.velocity = e.transform.velocity.copy();
		}
	}
}
