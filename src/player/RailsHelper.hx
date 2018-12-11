// TODO: RAIL TRANSFERS

package player;

import math.Vec3;
import math.Capsule;
import math.Intersect;

class RailsHelper {
	static function closest_end_of_rail(position: Vec3, rail: Array<Capsule>, idx: Int) {
		var near = rail[idx].a;
		var far  = rail[idx].b;

		// Swap if needed
		if (Vec3.distance(near, position) > Vec3.distance(far, position)) {
			return {
				near:    far,
				far:     near,
				closest: idx+1
			}
		}

		return { near: near, far: far, closest: idx-1 }
	}

	static function transfer_rail(player: Entity, rail: Array<Capsule>, idx: Int): Bool {
		var data = closest_end_of_rail(player.transform.position, rail, idx);

		var connecting_rail = false;
		if (data.closest >= 0 && data.closest < rail.length) {
			connecting_rail = true;
		}
		else {
			// handle looping
			if (data.closest == -1) {
				var rail_near = closest_end_of_rail(player.transform.position, rail, rail.length-1).near;
				var dist = Vec3.distance(rail_near, data.near);
				if (dist < rail[0].radius) {
					connecting_rail = true;
					data.closest = rail.length - 1;
				}
			}
			else if (data.closest == rail.length) {
				var rail_near = closest_end_of_rail(player.transform.position, rail, 0).near;
				var dist = Vec3.distance(rail_near, data.near);
				if (dist < rail[0].radius) {
					connecting_rail = true;
					data.closest = 0;
				}
			}
		}

		// self transfer: bail.
		if (data.closest == idx) {
			return false;
		}

		if (connecting_rail) {
			var velocity = (rail[data.closest].a + rail[data.closest].b) / 2 - data.near;
			velocity.normalize();
			velocity *= player.transform.velocity.length();

			player.transform.position = data.near;
			player.transform.velocity = velocity;
			player.player.rail_index  = data.closest;

			return true;
		}

		return false;
	}

	static function slide_on_rail(e: Entity, player_capsule: Capsule, dt: Float) {
		var rail = e.player.rail;
		var i = e.player.rail_index;
		var segment = rail[i];

		var hit = Intersect.capsule_capsule(player_capsule, segment);

		// make sure we haven't gone off the rails!
		var result = closest_end_of_rail(e.transform.position, e.player.rail, e.player.rail_index);
		var rail_direction = result.near - result.far;
		rail_direction.normalize();

		var direction = result.near - e.transform.position;
		direction.normalize();

		// we need to try to transfer when you cross the end of a capsule,
		// even if you're still in contact. not doing this prevents it from
		// being smooth.
		if (Vec3.dot(rail_direction, direction) < 0) {
			hit = null;
		}

		// transfer to the next segment or disconnect if there isn't one
		if (hit == null) {
			if (!transfer_rail(e, rail, i)) {
				e.player.rail = null;
				e.player.rail_index = null;
			}
			return;
		}

		var direction = segment.b - segment.a;
		e.transform.velocity = Vec3.project_on(e.transform.velocity, direction);
		direction.set_from(e.transform.velocity);
		direction.normalize();
		e.transform.velocity += direction * e.player.rail_boost;
		e.transform.position = hit.p2 + e.transform.velocity * dt;
	}

	static function find_new_rail(e: Entity, player_capsule: Capsule) {
		var rails = Main.get_rails(e.transform.position, e.player.rail_attach_radius);

		if (e.transform.velocity.length() < e.player.rail_stick_min) {}

		for (r in rails) {
			var rail = switch (r.item) {
				case Rail(capsules): capsules;
				default: null;
			}
			for (i in 0...rail.length) {
				var segment = rail[i];

				var hit = Intersect.capsule_capsule(player_capsule, segment);

				// got a hit, stick to it
				if (hit != null) {
					var velocity = e.transform.velocity.copy();
					velocity.normalize();

					var to_rail = hit.p2 - player_capsule.b;
					to_rail.normalize();

					// do not attach to a rail you are moving away from
					var power = Vec3.dot(to_rail, velocity);
					if (power < 0.25) { continue; }

					var direction    = segment.b - segment.a;
					var new_velocity = Vec3.project_on(e.transform.velocity, direction);

					// don't attach if your speed will drop too much or you'll be going too slow to stay on
					var nvl = new_velocity.length();
					if (nvl < e.transform.velocity.length() / 5 || nvl < e.player.rail_stick_min) {
						continue;
					}

					e.transform.position = hit.p2;
					e.transform.velocity = new_velocity;
					e.player.rail = rail;
					e.player.rail_index = i;

					Signal.emit("rail-on");
					Signal.emit("vibrate", {
						power: 1.0,
						duration: 0.1,
					});
					break;
				}
			}
		}
	}

	public static function update(e: Entity, dt: Float) {
		var player_capsule = new Capsule(e.last_tx.position, e.transform.position, e.player.rail_attach_radius);

		// var was_on_rail = e.player.rail != null;

		if (e.player.rail != null) {
			slide_on_rail(e, player_capsule, dt);
		}

		// slide can detach the player from rails, so don't else
		if (e.player.rail == null) {
			find_new_rail(e, player_capsule);
		}

		if (e.player.rail == null) {
			Signal.emit("rail-off");
		}
	}
}
