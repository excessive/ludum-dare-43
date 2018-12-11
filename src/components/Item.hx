package components;

import math.Capsule;

enum Item {
	Theme;
	Rail(capsules: Array<Capsule>);
	MapInfo(info: { width: Int, height: Int, nodes: Array<SceneNode> });
}
