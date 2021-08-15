package webidl;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class Main {
	static function main() {
		final converter = new Converter();
		var cwd = "tests";
		for (f in FileSystem.readDirectory(cwd)) {
			if (Path.extension(f) == "idl") {
				var conf:{pack:String} = FileSystem.exists(cwd + "/" + f + ".json") ? Json.parse(File.getContent(cwd + "/" + f + ".json")) : {pack: ""};
				final defs = Parser.parseString(File.getContent(cwd + "/" + f), cwd + f);
				converter.addDefinitions(defs, conf.pack == null ? [] : conf.pack.split(".").filter(s -> s != ""));
			}
		}
		final printer = new haxe.macro.Printer();
		for (td in converter.convert()) {
			final dir = "src/" + td.pack.join("/");
			FileSystem.createDirectory(dir);
			sys.io.File.saveContent("src/" + td.pack.join("/") + "/" + td.name + ".hx", printer.printTypeDefinition(td));
		}
	}
}
