package ui;

import anim9.Anim9;
import imgui.*;

typedef TimelineDump = ;

class AnimDebug {
	public static function dump_timeline(anim: Anim9) {
		var tl: lua.Table<Int, Anim9Track> = cast anim.internal_timeline;

		var height = 0;
		// for (time in frame.data) {
		// 	if (time.marker) {
		// 		continue;
		// 	}
		// 	height++;
		// }

		var spacing = 20;

		ImGui.begin_child("Graph", 0, height*spacing, true, lua.Table.create(["NoInputs"]));
		var size = ImGui.get_content_region_max();
		// var scale = frame.duration / size[0];

		// var i = 0;
		// for (time in frame.data) {
		// 	if (time.marker) {
		// 		continue;
		// 	}
		// 	var key = time.source;

		// 	if (pause_frame == null) {
		// 		ImGui.push_color("Button", time.color.r, time.color.g, time.color.b, 0.1);
		// 		ImGui.set_cursor_pos_x(time.start / scale);
		// 		ImGui.set_cursor_pos_y(spacing * i);
		// 		if (slowest.exists(key)) {
		// 			ImGui.button("", slowest[key] / scale, spacing);
		// 		}
		// 	}

		// 	ImGui.push_color("Button", time.color.r, time.color.g, time.color.b, 1.0);
		// 	ImGui.set_cursor_pos_x(time.start / scale);
		// 	ImGui.set_cursor_pos_y(spacing * i);
		// 	ImGui.button("", time.duration / scale, spacing);

		// 	if (pause_frame == null) {
		// 		ImGui.push_color("Button", time.color.r / 2, time.color.g / 2, time.color.b / 2, 0.75);
		// 		ImGui.set_cursor_pos_x(time.start / scale);
		// 		ImGui.set_cursor_pos_y(spacing * i);
		// 		if (fastest.exists(key)) {
		// 			ImGui.button("", fastest[key] / scale, spacing);
		// 		}
		// 		ImGui.pop_color(3);
		// 	}
		// 	else {
		// 		ImGui.pop_color(1);
		// 	}
		// 	i++;
		// }

		// i = 0;
		// for (time in frame.data) {
		// 	ImGui.set_cursor_pos_x(time.start / scale + 2);
		// 	ImGui.set_cursor_pos_y(spacing * i);
		// 	if (!time.marker) {
		// 		ImGui.text(time.label + " (" + Std.string(Std.int(time.duration * 100000) / 100.0) + "ms)");
		// 		i++;
		// 	}
		// 	else {
		// 		ImGui.text(time.label);
		// 	}
		// }

		ImGui.end_child();
	}
}