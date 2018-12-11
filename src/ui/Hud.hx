package ui;

import actor.*;
import backend.Profiler;
import math.Utils;
import math.Vec2;
import math.Vec3;
import math.Vec4;
import love.graphics.GraphicsModule as Lg;
import love.graphics.*;

typedef OverlayInfo = { id: Int, text: String, location: Vec3 };

class Hud {
	static inline function format(fmt: String, args: Array<Dynamic>): String {
		var _real = untyped __lua__("{}");
		for (i in 0...args.length) {
			untyped __lua__("table.insert({0}, {1})", _real, args[i]);
		}
		return untyped __lua__("string.format({0}, unpack({1}))", fmt, _real);
	}

	static var overlays: Array<OverlayInfo> = [];

	static function mismatch_overlays(out: Array<OverlayInfo>, list_a: Array<OverlayInfo>, list_b: Array<OverlayInfo>) {
		for (a in list_a) {
			var is_new = true;
			for (b in list_b) {
				if (a.id == b.id) {
					is_new = false;
				}
			}
			if (is_new) {
				out.push(a);
			}
		}
	}

	// i don't want to know how slow this is with an n larger than a few
	public static function update_overlays(?_overlays: Array<OverlayInfo>) {
		var bubbles = layer.find_actor("bubbles");
		if (_overlays == null || _overlays.length == 0) {
			bubbles.trigger("hide", true);
			overlays.resize(0);
			return;
		}

		var new_overlays = [];
		mismatch_overlays(new_overlays, _overlays, overlays);

		var old_overlays = [];
		mismatch_overlays(old_overlays, overlays, _overlays);

		for (o in new_overlays) {
			bubbles.children.push(new BubbleActor(o.id, o.text, (self) -> {
				self.user_data = o.location;
				// self.set_font(noto_sans_14);
				self.set_offset(0, -30);
				self.trigger("show");
			}));
		}

		for (o in old_overlays) {
			var actor = layer.find_actor("bubble_" + o.id, bubbles);
			if (actor == null) {
				continue;
			}
			actor.trigger("hide");
		}

		overlays = _overlays;

		var remove = [];
		for (c in bubbles.children) {
			if (c.actual.aux[0] < -0.99) {
				remove.push(c);
			}
		}

		for (c in remove) {
			bubbles.children.remove(c);
		}

		for (o in overlays) {
			var actor: BubbleActor = cast layer.find_actor("bubble_" + o.id, bubbles);
			if (actor == null) {
				continue;
			}
			actor.set_text(o.text);
			actor.user_data = o.location;
		}

		var center = new Vec2(ui.Anchor.center_x, ui.Anchor.center_y);
		var scale = ui.Anchor.width / 1.5;
		for (a in bubbles.children) {
			var location: Vec3 = a.user_data;
			var pos = new Vec2(location.x, location.y);
			location.z = Math.max(1-Vec2.distance(pos, center) / scale, 0);
			location.z = Math.pow(location.z, 0.25);
		}
	}

	static var layer: ActorLayer;
	static var brown = {
		r: 81/255,
		g: 39/255,
		b:  3/255
	};

	public static function init() {
		Signal.register("update", update);
		Signal.register("resize", (_vp) -> {
			var vp: Vec4 = _vp;
			layer.update_bounds(vp);
		});

		var win1 = false;
		var win2 = false;
		var pi   = Math.PI;

		var typeface = "assets/fonts/animeace2_reg.ttf";
		var f36      = Lg.newFont(typeface, 36);
		var f128     = Lg.newFont(typeface, 128);

		layer = new ActorLayer(() -> [

			// Progress meter
			new Actor((self) -> {
				self.set_name("progress");
				self.set_anchor((vp) -> new Vec3(vp.center_x, vp.top, 0));

				// self.on_update = (_, dt) -> {
				// 	if (Main.win) {
				// 		self.set_offset(0, self.offset_y - 50 * dt);
				// 	}
				// }

				self.on_draw = (_) -> {
					Lg.setLineWidth(3);
					var x = self.final_position.x;
					var y = self.final_position.y + self.offset_y;

					var center_hole = () -> {
						Lg.circle(DrawMode.Fill, x, y, 55);
					}
					var seperator = () -> {
						Lg.circle(DrawMode.Fill, x, y, 80);
					}

					// Backestround
					Lg.setColor(0.0, 0.0, 0.0, 0.5);
					Lg.circle(DrawMode.Fill, x, y, 105);

					// Credit
					Lg.stencil(center_hole, StencilAction.Replace, 1);
					Lg.setStencilTest(CompareMode.Equal, 0);


					// Background
					Lg.setColor(0.9, 0.7, 0.0, 0.5);
					Lg.arc(DrawMode.Fill, x, y, 75, pi, 0);

					var p       = Render.player;
					var total   = p.player.total_items;
					var credits = p.player.collected_items;
					var pct     = credits / total;

					var length = Main.stage_length;
					var timer  = Main.stage_timer;
					var ptl    = timer / length;

					// Foreground
					Lg.setColor(0.9, 0.7, 0.0, 1);
					Lg.arc(DrawMode.Fill, x, y, 75, pi, pi - pi * pct);

					// Time
					Lg.stencil(seperator, StencilAction.Replace, 1);
					Lg.setStencilTest(CompareMode.Equal, 0);

					// Background
					Lg.setColor(0, 0.9, 0.7, 0.5);
					Lg.arc(DrawMode.Fill, x, y, 100, pi, 0);

					// Foreground
					Lg.setColor(0, 0.9, 0.7, 1);
					Lg.arc(DrawMode.Fill, x, y, 100, pi, pi * ptl);

					// Text
					Lg.setStencilTest();
					Lg.setFont(f36);

					if (Main.win) {
						Lg.printf("999", x-55, y-5, 110, AlignMode.Center);
					} else {
						Lg.printf(format("%d", [timer]), x-55, y-5, 110, AlignMode.Center);
					}
				}
			}),

			// Speedometer
			new Actor((self) -> {
				self.set_name("speed");
				self.set_anchor((vp) -> new Vec3(vp.right, vp.bottom, 0));

				self.on_draw = (_) -> {
					Lg.setLineWidth(3);
					var x = self.final_position.x;
					var y = self.final_position.y;

					// Speed values
					var p          = Render.player;
					var mps_to_kph = 3.6;
					var max        = p.player.speed_limit * mps_to_kph;
					var speed      = Utils.min(max, p.player.last_speed * mps_to_kph);
					var ratio      = speed / max;

					// Background
					Lg.setColor(0, 0, 0, 0.5);
					Lg.polygon(DrawMode.Fill, x-200, y, x, y, x, y-40);

					// Foreground
					var a = new Vec3(60, 1.0, 1.0);
					var b = new Vec3(0, 1.0, 1.0);
					var c = Utils.hsv_to_rgb(Vec3.lerp(a, b, Math.pow(ratio, 10)));

					// Lg.setColor(0.9, 1 - ratio, 0, 0.75);
					Lg.setColor(c.x, c.y, c.z, 1);
					Lg.polygon(DrawMode.Fill, x-200, y, x-200+(ratio * 200), y, x-200+(ratio * 200), y-(ratio * 40));

					// Reset
					Lg.setStencilTest();
					Lg.setColor(1, 1, 1, 1);
				}
			}),

			// Lose game
			new TextActor((self) -> {
				self.set_name("lose");
				self.set_anchor((vp) -> new Vec3(vp.center_x, vp.center_y, 0));
				self.set_text("FAIL GET!");
				self.set_stroke(3, 0, 0);
				self.set_stroke_color(0, 0, 0, 1);
				self.set_visible(false);
				self.set_color(1, 0, 0, 1);
				self.set_font(f128);
				self.set_align(Center);
				self.set_offset(0, -120);

				self.on_update = (_, dt) -> {
					if (Main.lose) {
						self.set_visible(true);
					} else {
						self.set_visible(false);
					}
				}

			}),

			// Win game
			new TextActor((self) -> {
				self.set_name("win");
				self.set_anchor((vp) -> new Vec3(vp.center_x, vp.center_y, 0));
				self.set_text("WIN GET!");
				self.set_stroke(3, 0, 0);
				self.set_stroke_color(0, 0, 0, 1);
				self.set_visible(false);
				self.set_color(0.25, 0.6, 0.9, 1);
				self.set_font(f128);
				self.set_align(Center);
				self.set_offset(0, -120);

				self.on_update = (_, dt) -> {
					if (Main.win && !win1) {
						win1 = true;
						self.set_visible(true);

						Signal.after(5, function() {
							self.set_visible(false);
						});
					}
				}
			}),

			// Win game subtext
			new TextActor((self) -> {
				self.set_name("win");
				self.set_anchor((vp) -> new Vec3(vp.center_x, vp.center_y, 0));
				//self.set_text("MAKE YOUR WAY TO THE ARCADE!");
				self.set_text("HAPPY END! PLAY FOREVER!");
				self.set_stroke(3, 0, 0);
				self.set_stroke_color(0, 0, 0, 1);
				self.set_visible(false);
				self.set_color(0.25, 0.6, 0.9, 1);
				self.set_font(f36);
				self.set_align(Center);
				self.set_offset(0, 40);

				self.on_update = (_, dt) -> {
					if (Main.win && !win2) {
						win2 = true;
						self.set_visible(true);

						Signal.after(5, function() {
							self.set_visible(false);
						});
					}
				}
			}),

			// old speed
			new Actor((self) -> {
				self.set_name("bubbles");
			})
		]);
	}

	public static function update(dt) {
		Profiler.push_block("HudUpdate");
		layer.update(dt);
		Profiler.pop_block();
	}

	public static function draw() {
		Profiler.push_block("HudDraw");
		ActorLayer.draw(layer);
		Profiler.pop_block();
	}
}
