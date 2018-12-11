package systems;

import love.math.MathModule.random as rand;
import math.Utils;
import components.Transform;
import components.Emitter;

class ParticleEffect extends System {
	override function filter(e: Entity) {
		return e.emitter.length > 0;
	}

	function spawn_particle(transform: Transform, emitter: Emitter) {
		if (!emitter.enabled) {
			return;
		}

		var pd = emitter.data;
		pd.last_spawn_time = pd.time;
		pd.index++;

		var mul = 10000.0;
		var offset = rand(emitter.emission_life_min*mul, emitter.emission_life_max*mul) / mul;
		var despawn_time = pd.time + offset;

		pd.particles.push(new InstanceData(
			transform.position,
			math.Vec3.zero(), // ignore entity velocity
			transform.offset,
			pd.time,
			despawn_time,
			emitter.spawn_radius,
			emitter.spread
		));
	}

	function update_emitter(transform: Transform, particle: Emitter, dt: Float) {
		var pd = particle.data;
		pd.time += dt;

		// It's been too long since our last particle spawn and we need more, time
		// to get to work.
		var spawn_delta = pd.time - pd.last_spawn_time;
		var count = pd.particles.length;
		if (particle.pulse > 0.0) {
			if (count + particle.emission_rate <= particle.limit && spawn_delta >= particle.pulse) {
				for (i in 0...particle.emission_rate) {
					this.spawn_particle(transform, particle);

					if (particle.update != null) {
						particle.update(particle, pd.index);
					}
				}
			}
		}
		else {
			var rate = 1/particle.emission_rate;
			if (count < particle.limit && spawn_delta >= rate) {
				var need = Std.int(Utils.min(2, Math.floor(spawn_delta / rate)));

				for (i in 0...need) {
					this.spawn_particle(transform, particle);

					if (particle.update != null) {
						particle.update(particle, pd.index);
					}
				}
			}
		}

		// Because particles are added in order of time and removals maintain
		// order, we can simply count the number we need to get rid of and process
		// the rest.
		var remove_n = 0;
		for (i in 0...pd.particles.length) {
			var p = pd.particles[i];
			if (pd.time > p.despawn_time) {
				remove_n++;
				continue;
			}
			p.position.x = p.position.x + p.velocity.x * dt;
			p.position.y = p.position.y + p.velocity.y * dt;
			p.position.z = p.position.z + p.velocity.z * dt;
		}

		// Particles be gone!
		if (remove_n > 0) {
			pd.particles.splice(0, remove_n);
		}
	}

	override function process(e: Entity, dt: Float) {
		var i = e.emitter.length;
		while (i-- > 0) {
			var emitter = e.emitter[i];
			if (emitter.lifetime != null) {
				emitter.lifetime -= dt;
				if (emitter.lifetime <= 0) {
					e.emitter.splice(i, 1);
					continue;
				}
			}
			update_emitter(e.transform, emitter, dt);
		}
	}
}
