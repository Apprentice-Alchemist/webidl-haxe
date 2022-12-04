package webidl;

import haxe.macro.Expr.TypePath;
import haxe.macro.MacroStringTools;
import haxe.DynamicAccess;
import haxe.ds.StringMap;

@:publicFields
@:structInit class Config {
	var types:Map<String, {
		exclude:Array<String>
	}>;

	var typedefs:Map<String, TypePath>;

	public static function fromJSON(d:Any):Config {
		final types = new Map();
		final typedefs = new Map();
		for (field in Reflect.fields(d)) {
			final value:Any = Reflect.field(d, field);
			if (value is String) {
				final value:String = value;
				final pack = value.split(".");
				if (pack.length < 1)
					throw "assert";
				final name:String = cast pack.pop();
				typedefs.set(field, {pack: pack, name: name});
			} else {
				types.set(field, Reflect.field(d, field));
			}
		}
		return {types: types, typedefs: typedefs};
	}
}
