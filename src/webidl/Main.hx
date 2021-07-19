package webidl;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		var cwd = "tests";
		for(f in FileSystem.readDirectory(cwd)) {
			if (Path.extension(f) == "widl") {
				Parser.parseString(File.getContent(f),cwd + f);
			}
		}
	}
}
