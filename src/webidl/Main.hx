package webidl;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class Main {
	static inline function makePath(p)
		return inline Path.normalize(inline Path.join(p));

	static function main() {
		var output = "idl";
		var files = [];
		var format = false;
		final handler = Args.generate([@doc("Set output folder")
			["-o", "--output"] => (arg:String) -> output = new haxe.io.Path(arg).dir,
			@doc("Run the formatter on the output")
			["--format"] => () -> format = true,
			_ => (file:String) -> {
				if (FileSystem.isDirectory(file)) {
					for (f in FileSystem.readDirectory(file))
						files.push(makePath([file, f]));
				} else {
					files.push(Path.normalize(file));
				}
			}
		], true);
		final args = Sys.args();
		final haxelib = Sys.getEnv("HAXELIB_RUN") != null;
		final haxelib_name = Sys.getEnv("HAXELIB_RUN_NAME");
		if (haxelib)
			Sys.setCwd(args.pop());
		if (args.length == 0) {
			Sys.print("Usage: ");
			if (haxelib)
				Sys.print('haxelib run ${haxelib_name}')
			else
				Sys.print("webidl");
			Sys.println(" [options] files...");
			Sys.println(handler.getDoc());
			Sys.exit(0);
		} else
			handler.parse(args);
		final converter = new Converter();

		for (f in files) {
			if(!FileSystem.exists(f)) Sys.println("File not found : " + f);
			final ext = Path.extension(f);
			final d = Path.directory(f);
			final name = Path.withoutDirectory(f);
			if (ext == "idl" || ext == "webidl" || ext == "widl") {
				var conf:{pack:String} = FileSystem.exists(makePath([d, name + ".json"])) ? Json.parse(File.getContent(makePath([d, name + ".json"]))) : {pack: ""};
				final defs = Parser.parseString(File.getContent(f), f);
				converter.addDefinitions(defs, conf.pack == null ? [] : conf.pack.split(".").filter(s -> s != ""));
			}
		}
		final printer = new haxe.macro.Printer();
		for (td in converter.convert()) {
			final dir = makePath([output].concat(td.pack));
			FileSystem.createDirectory(dir);
			sys.io.File.saveContent(makePath([dir, td.name + ".hx"]), printer.printTypeDefinition(td));
		}
		if(format) Sys.command("haxelib run formatter -s " + output);
	}
}
