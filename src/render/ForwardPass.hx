package render;

import backend.Profiler;
import love.graphics.Canvas;
import love.graphics.GraphicsModule as Lg;
import love.graphics.Shader as LgShader;
import love.image.ImageModule as Li;
import math.Mat4;
import utils.RecycleBuffer;
import excessive.Tricks;

class ForwardPass {
	static var fallback: love.graphics.Image;
	static var transparent = new RecycleBuffer<DrawCommand>();

	static function draw(s: LgShader, d: DrawCommand, light_vp: Mat4) {
		var mat = d.material;
		if (mat.double_sided) {
			Lg.setMeshCullMode(None);
		}
		else {
			Lg.setMeshCullMode(Back);
		}

		Lg.setShader(s);
		Helpers.send_mtx(s, "u_model", d.xform_mtx);
		Helpers.send_mtx(s, "u_normal_mtx", d.normal_mtx);
		Helpers.send_mtx(s, "u_lightvp", light_vp);
		if (d.bones != null) {
			Helpers.send(s, "u_rigged", 1);
			// untyped __lua__("print(#{0})", d.bones);
			untyped __lua__("{0}:send({1}, \"column\", unpack({2}))", s, "u_pose", d.bones);
			// Helpers.send_transpose(s, "u_pose", lua.TableTools.unpack(d.bones));
		}
		else {
			Helpers.send(s, "u_rigged", 0);
		}
		Helpers.send(s, "u_metalness", mat.metalness);
		Helpers.send(s, "u_roughness", mat.roughness);
		Helpers.send(s, "u_receive_shadow", !mat.shadow);

		var mesh = d.mesh.use();
		var tex = null;

		var aniso = Render.config.quality.anisotropic_filtering;
		// note: the renderer automatically clamps this to whatever
		// the maximum supported value is.
		var aniso_max = 16;

		Helpers.send(s, "s_shadow", Render.shadow.depth);

		var filter = null;
		if (aniso) {
			filter = aniso_max;
		}

		if (mat.textures.albedo != null) {
			tex = TextureCache.get(mat.textures.albedo, true);
			tex.setFilter(Linear, Linear, filter);
			tex.setWrap(Repeat, Repeat);

			var w = tex.getWidth();
			var h = tex.getHeight();
			Helpers.send(s, "u_texel_size", untyped __lua__("{ {0}, {1}, {2}, {3} }", 1.0 / w, 1.0 / h, w, h));
		}
		else {
			Helpers.send(s, "u_texel_size", untyped __lua__("{ {0}, {1}, {2}, {3} }", 1, 1, 1, 1));
		}

		if (mat.textures.roughness != null) {
			var rough = TextureCache.get(mat.textures.roughness, true);
			rough.setFilter(Linear, Linear, filter);
			rough.setWrap(Repeat, Repeat);
			Helpers.send(s, "s_roughness", rough);
		}
		else {
			Helpers.send(s, "s_roughness", fallback);
		}

		if (mat.textures.metalness != null) {
			var metal = TextureCache.get(mat.textures.metalness, true);
			metal.setFilter(Linear, Linear, filter);
			metal.setWrap(Repeat, Repeat);
			Helpers.send(s, "s_metalness", metal);
		}
		else {
			Helpers.send(s, "s_metalness", fallback);
		}

		mesh.setTexture(tex);
		Lg.draw(mesh);
	}

	public static function render(shaded: Canvas, depth: Canvas, light_vp: Mat4, draws: RecycleBuffer<DrawCommand>) {
		if (draws.length == 0) {
			return;
		}

		if (fallback == null) {
			var data = Li.newImageData(1, 1, "rgba8");
			data.setPixel(0, 0, 1, 1, 1, 1);
			fallback = Lg.newImage(data);
		}

		Profiler.push_block("Forward");

		Lg.setCanvas(untyped __lua__("{ {0}, depthstencil = {1} }", shaded, depth));

		var camera = Render.camera;
		var tripla = Shader.get("terrain");
		Lg.setShader(tripla);
		Helpers.send_uniforms(camera, tripla);

		var shader = Shader.get("basic");
		Lg.setShader(shader);
		Helpers.send_uniforms(camera, shader);

		transparent.reset();

		Lg.setFrontFaceWinding(Cw);
		Lg.setDepthMode(Lequal, true);
		Lg.setBlendMode(Replace);
		Tricks.set_alpha_to_coverage(true);
		Helpers.send(shader, "u_alpha_blend", false);

		for (d in draws) {
			if (d.material.opacity < 0.995) {
				transparent.push(d);
				continue;
			}
			var mat = d.material;
			var r = mat.color.x;
			var g = mat.color.y;
			var b = mat.color.z;
			Lg.setColor(r, g, b, 1);
			if (mat.triplanar) {
				Lg.setShader(tripla);
				draw(tripla, d, light_vp);
			}
			else {
				Lg.setShader(shader);
				draw(shader, d, light_vp);
			}
		}

		Tricks.set_alpha_to_coverage(false);
		Lg.setShader(shader);
		Helpers.send(shader, "u_alpha_blend", true);

		// transparent.resize_and_sort((a, b) -> a.view_pos.z > b.view_pos.z ? 1 : (a.view_pos.z < b.view_pos.z ? -1 : 0));
		// transparent.resize_and_sort((a, b) -> a.view_pos.z > b.view_pos.z ? -1 : (a.view_pos.z < b.view_pos.z ? 1 : 0));

		// write color (only) for transparent objects
		Lg.setBlendMode(Alpha, Premultiplied);
		Lg.setDepthMode(Lequal, false);
		for (d in transparent) {
			var mat = d.material;
			Lg.setColor(mat.color.x, mat.color.y, mat.color.z, d.material.opacity);
			draw(shader, d, light_vp);
		}

		// write depth now that color is updated, so sky is correct
		Lg.setColorMask(false, false, false, false);
		Lg.setDepthMode(Lequal, true);
		for (d in transparent) {
			draw(shader, d, light_vp);
		}
		Lg.setColorMask(true, true, true, true);
		Lg.setColor(1, 1, 1, 1);

		Lg.setBlendMode(Replace);
		Lg.setDepthMode();
		Lg.setMeshCullMode(None);

		Profiler.pop_block();
	}

}
