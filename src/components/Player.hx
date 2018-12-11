package components;

import math.Utils;
import math.Plane;
import math.Capsule;
import math.Vec3;

import ini.IniFile;
import backend.Fs;

private typedef PlayerConfig = {
	player: {
		gravity: Float,
		glide_gravity: Float,
		glide_min_height: Float,
		jump_power: Float
	},
	ground: {
		slope_friction_bias: Float,
		friction: Float,
		speed: Float,
		max_speed: Float,
	},
	air: {
		friction: Float,
		speed: Float,
		max_speed: Float,
		max_fall: Float
	},
	rail: {
		friction: Float,
		radius: Float,
		speed: Float,
		min_speed: Float,
		max_speed: Float,
		boost: Float
	}
}

class Player {
	// config settings, use the ini!
	public var slope_friction_bias: Float;

	public var friction:            Float;
	public var speed:               Float;
	public var speed_limit:         Float;

	public var air_friction:        Float;
	public var air_speed:           Float;
	public var air_speed_limit:     Float;
	public var air_speed_fall:      Float;

	public var rail_boost:          Float;
	public var rail_speed:          Float;
	public var rail_attach_radius:  Float;
	public var rail_stick_min:      Float;
	public var rail_friction:       Float;
	public var rail_speed_limit:    Float;

	public var gravity:             Float;
	public var gravity_glide:       Float;

	public var jump_power:          Float;

	public var glide_threshold:     Float;

	// status stuff
	public var gliding:            Bool          = false;
	public var rail:               Null<Array<Capsule>>    = null;
	public var rail_index:         Null<Int>     = null;
	public var contacts:           Array<Plane>  = [];
	public var grounded:           Bool          = false;

	public var target_distance: Float = 4.5;
	public var last_target_heading: Float;
	public var last_heading: Float;
	public var last_pitch: Float;

	public var stop_adjust: Float = 0.0;

	public var turn_weight: Int = 3;
	public var accel: Vec3 = new Vec3(0, 0, 0);

	public var last_speed: Float = 0.0;
	public var last_vel: Float = 0.0;

	public var total_items(get, never): Int;
	function get_total_items(): Int {
		return Main.collectibles;
	}

	public var collected_items: Int = 0;

	public inline function new() {
		var player_base: PlayerConfig = {
			player: {
				gravity: 0.5,
				glide_gravity: 0.05,
				glide_min_height: 5,
				jump_power: 15
			},
			ground: {
				slope_friction_bias: 1.0,
				friction: 0.005,
				speed: 0.5,
				max_speed: 1e4
			},
			air: {
				friction: 0.005,
				speed: 0.5,
				max_speed: 1e4,
				max_fall: 1e4
			},
			rail: {
				friction: 0.005,
				radius: 0.25,
				speed: 0.5,
				min_speed: 1.0,
				max_speed: 1e4,
				boost: 0.0
			}
		};
		var cfg = player_base;

		var filename = 'assets/physics_config.ini';
		if (Fs.is_file(filename)) {
			cfg = IniFile.parse_typed(player_base, filename);
			console.Console.ds('loaded config $filename');
		}

		this.gravity = cfg.player.gravity;
		this.gravity_glide = cfg.player.glide_gravity;
		this.glide_threshold = Utils.max(0.0, cfg.player.glide_min_height);
		this.jump_power = Utils.max(0.0, cfg.player.jump_power);

		this.slope_friction_bias = Utils.clamp(cfg.ground.slope_friction_bias, 0.0, 1.0);
		this.friction = Utils.clamp(cfg.ground.friction, 0.0, 1.0);
		this.speed = Utils.max(0.0, cfg.ground.speed);
		this.speed_limit = Utils.max(0.0, cfg.ground.max_speed);

		this.air_friction = Utils.clamp(cfg.air.friction, 0.0, 1.0);
		this.air_speed = Utils.max(0.0, cfg.air.speed);
		this.air_speed_limit = Utils.max(0.0, cfg.air.max_speed);
		this.air_speed_fall = Utils.max(0.0, cfg.air.max_fall);

		this.rail_friction = Utils.clamp(cfg.rail.friction, 0.0, 1.0);
		this.rail_attach_radius = Utils.max(0.0, cfg.rail.radius);
		this.rail_boost = Utils.max(0.0, cfg.rail.boost);
		this.rail_speed = Utils.max(0.0, cfg.rail.speed);
		this.rail_stick_min = Utils.max(0.0, cfg.rail.min_speed);
		this.rail_speed_limit = Utils.max(0.0, cfg.rail.max_speed);
	}
}
