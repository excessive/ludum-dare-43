import render.TextureCache;
import render.MaterialCache;
import components.Emitter.ParticleData;
import render.MeshView;
import math.Intersect;
import math.Capsule;
import backend.Input;
import anim9.Anim9;
import haxe.ds.Map;
import backend.Fs;
import math.Utils;
import math.Vec3;
import math.Bounds;
import math.Quat;
import backend.BaseGame;
import backend.GameLoop;
import backend.Gc;
import backend.Profiler;
import components.*;
import math.Vec4;
import systems.*;
import ui.Anchor;
import utils.RecycleBuffer;
import love.math.MathModule as Lm;

import components.Item;

import haxe.Json;

typedef TiledMap = {
	width: Int,
	height: Int,
	hexsidelength: Int,
	infinite: Bool,
	layers: Array<{
		data: Array<Int>,
		// data: [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3],
		height: Int,
		id: Int,
		// name: Tile Layer 1,
		opacity: Float,
		// type: tilelayer,
		visible: Bool,
		width: Int,
		x: Int,
		y: Int
	}>,
 	nextlayerid: Int,
	nextobjectid: Int,
	orientation: String, // hex
	renderorder: String, // left-up
	staggeraxis: String, // x
	staggerindex: String, // even
	tiledversion: String, // 2018.08.06
	tileheight: Int,
	tilesets: Array<{
		columns: Int,
		firstgid: Int,
		grid: {
			height: Int,
			orientation: String, //orthogonal,
			width: Int
		},
		margin: Int,
		name: String, // stuff
		spacing: Int,
		tilecount: Int,
		tileheight: Int,
		tiles: Array<{
			id: Int,
			image: String, //dirt tile.png,
			imageheight: Int,
			imagewidth: Int,
			type: String,
			properties: Array<{
				name: String,
				type: String,
				value: String
			}>
		}>,
		tilewidth: Int
	}>,
 	tilewidth: Int,
	type: String, // map
	version: Float // 1.2,
}

class Main extends BaseGame {
	public static var game_title = "OFF THE RAILS 2: TRASH THE RAILS (v1.02)";
	public static var scene: Scene;

	var systems:       Array<System>;
	var lag:           Float = 0.0;
	var current_state: RecycleBuffer<Entity>;
	public static var timestep(default, never): Float = 1 / 60;

	public static function get_map(): SceneNode {
		var map = scene.get_child("Map");
		if (map == null) {
			console.Console.es("Map node not found");
			return new SceneNode(); // rip
		}
		return map;
	}

	public static var spawn_transform(default, null): Transform;

	public static function new_scene() {
		// paranoid memory release of everything in the old scene
		if (scene != null) {
			scene.release();
		}
		scene = new Scene();

		// clean out the old map and entities
		Gc.run(true);

		// Reset game conditions
		lose = false;
		win  = false;

		Time.set_time(10);
		Main.stage_timer = Main.stage_length;
		Main.collectibles = 0;

		scene.add(World.load("assets/stages/city.exm", true, true));
		// scene.add(load_map("assets/map.json"));

		inline function load_extras(filename: String, collision: Bool) {
			if (collision) {
				return World.load(filename, true, false);
			}
			var node = new SceneNode();
			node.drawable = IqmLoader.load_file(filename, collision);
			return node;
		}

		scene.add(load_extras("assets/stages/terrain.exm", false));

		// clean out the temporary data from stage load
		// these help prevent a large memory usage spike on level reload
		Gc.run(true);

		Input.set_relative(true);

		inline function load_animated(filename, trackname, pos) {
			var ret = new SceneNode();
			ret.drawable = IqmLoader.load_file(filename);
			if (ret.drawable.length > 0) {
				var anim = ret.drawable[0].iqm_anim;
				if (anim != null) {
					ret.animation = new Anim9(anim);

					var t = ret.animation.new_track(trackname);
					ret.animation.play(t);
					ret.animation.update(0);
				}
				else {
					trace("no anim");
				}
			}
			else {
				trace("load fail");
			}
			ret.transform.position.set_from(pos);
			return ret;
		}

		// scene.add(load_animated("assets/models/farmer.exm", "run", new Vec3(0, 0, 0)));
		// scene.add(load_animated("assets/models/hunter.iqm", "idle", new Vec3(5, 0, 0)));

		var player        = new SceneNode();
		player.player     = new Player();
		player.name       = "Korbo";
		player.collidable = new Collidable();
		player.collidable.radius.set_xyz(0.35, 0.35, 0.85);

		player.drawable   = IqmLoader.load_file("assets/models/player.iqm");

		// sparks
		player.emitter.push({
			data: new ParticleData(),
			enabled: false,
			limit: 5,
			pulse: 0.0,
			spawn_radius: 0.0,
			spread: 5,
			emission_rate: 60,
			emission_life_min: 1/20,
			emission_life_max: 1/10,
			drawable: IqmLoader.load_file("assets/models/spark.iqm")
		});

		player.transform.position.z = 5;
		// player.transform.offset.z = 0.5;
		if (player.drawable.length > 0) {
			for (d in player.drawable) {
				d.material = "player";
			}
			var anim = player.drawable[0].iqm_anim;
			if (anim != null) {
				player.animation = new Anim9(anim);
				// var t = player.animation.new_track("idle");
				// player.animation.play(t);
				// player.animation.update(0);
			}
		// 	// trace(anim != null);
		}
		// player.transform.scale *= 0.5;
		spawn_transform = player.transform.copy();

		scene.add(player);
		Render.player = player;

		var cam = new Camera(player.transform.position);
		// cam.orientation = Quat.from_angle_axis(Utils.rad(70), Vec3.right());
		Render.camera = cam;
	}

	override function quit(): Bool {
		return false;
	}

	public static var collectibles: Int = 0;
	public static var stage_timer(default, null):   Float = 0.0;
	public static var stage_length(default, never): Float = 600;

	public static var lose: Bool = false;
	public static var win:  Bool = false;
	static var min_to_win:  Int  = 15;

	override function load(window, args) {
		love.mouse.MouseModule.setVisible(true);

		Anchor.update(window);

		Bgm.load_tracks(["assets/bgm/TIH3.ogg", "assets/bgm/TIH2.ogg"]);

		Sfx.init();

		Signal.register("quiet", (_) -> { Bgm.set_ducking(0.25); Sfx.menu_pause(true);  });
		Signal.register("loud",  (_) -> { Bgm.set_ducking(1.0);  Sfx.menu_pause(false); });

		// TODO: only fire on the currently active gamepad(s)
		Signal.register("vibrate", function(params: { power: Float, duration: Float, ?weak: Bool  }) {
			var lpower = params.power;
			var rpower = params.power;
			if (params.weak != null && params.weak) {
				rpower *= 0;
			}

			var js: lua.Table<Int, love.joystick.Joystick> = cast love.joystick.JoystickModule.getJoysticks();
			var i = 0;
			while (i++ < love.joystick.JoystickModule.getJoystickCount()) {
				if (!js[i].isGamepad()) {
					continue;
				}
				js[i].setVibration(lpower, rpower, params.duration);
			}
		});

		Signal.register("rail-on", (_) -> {
			Sfx.grind.play();
		});

		Signal.register("rail-off", (_) -> {
			Sfx.grind.stop();
		});

		Signal.register("collected-item", (_) -> {
			Sfx.coin.play();
		});

		Signal.register("lose", (_) -> {
			lose = true;

			Signal.after(5, () -> {
				new_scene();
			});
		});

		Signal.register("win", (_) -> {
			win = true;
		});

		GameInput.init();
		Time.init();
		Render.init();

		systems = [
			new ItemEffect(),
			new Trigger(),
			new PlayerController(),
			new ParticleEffect(),
			new Animation(),
		];
		new_scene();

		Signal.emit("resize", Anchor.get_viewport());

		Signal.register("collected-item", function(_) {
			var p = Render.player;
			p.player.collected_items += 1;
		});

		// hack: this should be done in a non-bindy way in PlayerController
		GameInput.bind_scroll(function(x, y) {
			if (GameInput.locked || lose) { return; }

			var p = Render.player.player;
			var orbit = p.target_distance;
			orbit -= y * 0.5;
			p.target_distance = Utils.clamp(orbit, 2.5, 7.5);
		});
		// force a tick on the first frame if we're using fixed timestep.
		// this prevents init bugs
		if (timestep > 0) {
			tick(timestep, window);
		}
	}

	static var rails: Array<Entity> = [];
	static var tmp_rails: Array<Entity> = [];

	/** gets culled rails based on player attach radius */
	public static function get_rails(position: Vec3, attach_radius: Float) {
		var len = 0;
		var search = new Bounds(position, Vec3.splat(attach_radius * 2));
		for (e in rails) {
			if (Intersect.aabb_aabb(search, e.bounds)) {
				tmp_rails[len] = e;
				len += 1;
			}
		}
		tmp_rails.resize(len);
		return tmp_rails;
	}

	function tick(dt: Float, window: backend.Window) {
		Profiler.push_block("Tick");
		GameInput.update(dt);
		Time.update(dt);
		// Stage.update(dt);

		if (!win) {
			stage_timer = Utils.max(0, stage_timer - dt);
		}

		Signal.update(dt);
		Bgm.update(dt);

		// order-insensitive updates can self register
		Profiler.push_block("SelfUpdates");
		Signal.emit("update", dt);
		Profiler.pop_block();

#if (imgui || debug)
		GameInput.bind(Debug_F8, function() {
			Signal.emit("advance-day");
			return true;
		});
#end

		GameInput.bind(Debug_F6, function() {
			Render.potato_mode = !Render.potato_mode;
			var size = window.get_size();
			Render.reset(size.width, size.height);
			return true;
		});

		GameInput.bind(Debug_F5, function() {
			MaterialCache.flush();
			TextureCache.flush();
			new_scene();
			return true;
		});

#if 0
		GameInput.bind(Debug_F6, function() {
			trace("nvm back");
			Bgm.prev();
			return true;
		});

		GameInput.bind(Debug_F7, function() {
			trace("skip");
			Bgm.next();
			return true;
		});
#end

		var cam = Render.camera;
		cam.last_orientation = cam.orientation;
		cam.last_target   = cam.target;

		var entities = scene.get_entities();

		rails.resize(0);

		Profiler.push_block("TransformCache");
		for (e in entities) {
			if (e.item != null) {
				switch (e.item) {
					case Rail(capsules): {
						for (segment in capsules) {
							Debug.capsule(segment, 1, 0, 1);
						}
						rails.push(e);
					}
					default:
				}
			}
			if (!e.transform.is_static) {
				e.last_tx.position.set_from(e.transform.position);
				e.last_tx.orientation.set_from(e.transform.orientation);
				e.last_tx.scale.set_from(e.transform.scale);
				e.last_tx.velocity.set_from(e.transform.velocity);
			}
		}
		Profiler.pop_block();

		var relevant = [];
		for (system in systems) {
			Profiler.push_block(system.PROFILE_NAME, system.PROFILE_COLOR);
			relevant.resize(0);
			for (entity in entities) {
				if (system.filter(entity)) {
					relevant.push(entity);
					system.process(entity, dt);
				}
			}
			system.update(relevant, dt);
			Profiler.pop_block();
		}

		// Fail condition
		if (!lose && !win && stage_timer == 0) {
			Signal.emit("lose");
		}

		// Win condition
		else if (!lose && !win && Render.player.player.collected_items >= min_to_win) {
			Signal.emit("win");
		}

		Profiler.pop_block();
	}

	public static var frame_graph(default, null): Array<Float> = [ for (i in 0...250) 0.0 ];

	var last_vp: Vec4;

	override function update(window, dt: Float) {
		Anchor.update(window);
		var vp = Anchor.get_viewport();
		if (vp != last_vp) {
			last_vp = vp;
			Signal.emit("resize", vp);
		}

#if !imgui
		if (love.mouse.MouseModule.isVisible()) {
			// love.mouse.MouseModule.setVisible(false);
		}
#end

		frame_graph.push(dt);
		while (frame_graph.length > 250) {
			frame_graph.shift();
		}

		if (timestep < 0) {
			tick(dt, window);
			current_state = scene.get_entities();
			return;
		}

		lag += dt;

		while (lag >= timestep) {
			lag -= timestep;
			if (lag >= timestep) {
				Debug.draw(true);
				Debug.clear_capsules();
			}
			tick(timestep, window);
		}

		current_state = scene.get_entities();
	}

	override function mousepressed(x: Float, y: Float, button: Int) {
		GameInput.mousepressed(x, y, button);
	}

	override function mousereleased(x: Float, y: Float, button: Int) {
		GameInput.mousereleased(x, y, button);
	}

	override function wheelmoved(x: Float, y: Float) {
		GameInput.wheelmoved(x, y);
	}

	override function keypressed(key: String, scan: String, isrepeat: Bool) {
		if (!isrepeat) {
			GameInput.keypressed(scan);
		}
	}

	override function keyreleased(key: String, scan: String) {
		GameInput.keyreleased(scan);
	}

	override function resize(w, h) {
		Render.reset(w, h);
	}

	override function draw(window) {
		var alpha = lag / timestep;
		if (timestep < 0) {
			alpha = 1;
		}
		var visible = scene.get_visible_entities();
		Profiler.push_block("Render");
		Render.frame(window, visible, alpha);
		Profiler.pop_block();
	}

	static function main() {
#if (debug || !release)
		return GameLoop.run(new Main());
#else
		return GameLoop.run(new Splash());
#end
	}
}
