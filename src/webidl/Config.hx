package webidl;

import haxe.macro.MacroStringTools;
import haxe.DynamicAccess;
import haxe.ds.StringMap;

@:structInit class Config {
	public var pack:Array<String> = [];

	/**
	 * Map from webidl names to haxe type paths.
	 */
	public var typemap:Map<String, haxe.macro.Expr.TypePath> = [];

	public static function fromJson(j:Null<{pack:String, typemap:DynamicAccess<String>}>):Config {
		if (j == null)
			return {};
		return {
			pack: j.pack == null ? [] : j.pack.split(".").filter(s -> s != ""),
			typemap: j.typemap == null ? [] : [
				for (name => path in j.typemap)
					name => {
						var pack = path.split(".");
						{pack: pack, name: pack.pop(), params: []};
					}
			]
		}
	}
}
