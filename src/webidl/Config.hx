package webidl;

import haxe.macro.MacroStringTools;
import haxe.DynamicAccess;
import haxe.ds.StringMap;

@:publicFields
@:structInit class Config {
	var types:Map<String, {
		exclude:Array<String>
	}>;

	public static function fromJSON(d:Any):Config {
		final types = new Map();
		for (field in Reflect.fields(d)) {
			types.set(field, Reflect.field(d, field));
		}
		return {types: types};
	}
}
