import love.audio.AudioModule as La;
import love.audio.Source;

class Sfx {
	public static var coin:  Source;
	public static var grind: Source;

	static var all_sounds: Array<Source> = [];

	static var volume = 0.95;

	public static function init() {
		if (coin == null) {
			coin = La.newSource("assets/sfx/coin.ogg", Static);
			coin.setVolume(0.25);
		}

		if (grind == null) {
			grind = La.newSource("assets/sfx/grind.ogg", Static);
			grind.setVolume(0.25);
			grind.setLooping(true);
		}

		all_sounds = [
		];
	}

	static var holding = [];

	public static function menu_pause(set: Bool) {
		if (set) {
			for (s in all_sounds) {
				if (s.isPlaying()) {
					s.pause();
					if (holding.indexOf(s) < 0) {
						holding.push(s);
					}
				}
			}
		}
		else {
			for (s in holding) {
				s.play();
			}
			holding.resize(0);
		}
	}

	public static function stop_all() {
		for (s in all_sounds) {
			s.stop();
		}
	}
}
