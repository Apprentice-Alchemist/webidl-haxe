package webidl;

import haxe.ds.ArraySort;
import haxe.macro.Expr;
import haxe.macro.Expr.Field;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.TypeDefinition;
import webidl.Ast;
import haxe.ds.StringMap;

using Lambda;
using StringTools;

class Converter {
	static function escape(s:String) {
		return switch s {
			case "interface", "dynamic", "function", "static", "import", "using":
				"_" + s;
			case var s:
				s;
		}
	}

	var interfaces = new StringMap<InterfaceType>();
	var dictionaries = new StringMap<DictionaryType>();
	var enums = new StringMap<EnumType>();
	var typedefs = new StringMap<TypedefType>();

	var mixins = new StringMap<InterfaceType>();
	var includes:Array<{what:String, included:String}> = [];
	var partials:Array<Definition> = [];

	var type_paths = new StringMap<haxe.macro.Expr.TypePath>();

	public function new() {}

	public inline function getTypePath(name:String):TypePath {
		return type_paths.exists(name) ? cast type_paths.get(name) : throw "assert";
	}

	public function convert():Array<TypeDefinition> {
		var ret = [];
		// resolve partials
		for (p in partials)
			switch p {
				case Interface(part):
					var i = interfaces.get(part.name);
					if (i == null) {
						trace("unknown interface", part.name);
						continue;
					}
					i.attributes = i.attributes.concat(part.attributes);
					i.members = i.members.concat(part.members);
				case Namespace(n): // TODO
				case _:
					throw "partials should be interfaces or namespaces";
			}
		// mix mixins
		for (inc in includes) {
			var i = interfaces.get(inc.included);
			if (i == null) {
				trace("unkown interface", inc.included);
				continue;
			}
			var m = mixins.get(inc.what);
			if (m == null) {
				trace("Warning : Could not find mixin " + inc.what);
			} else {
				i.members = i.members.concat(m.members);
			}
		}
		// convert types
		for (i in interfaces)
			ret.push(convertInterface(i));
		for (e in enums)
			ret.push(convertEnum(e));
		for (d in dictionaries)
			ret.push(convertDictionary(d));
		for (t in typedefs)
			ret.push(convertTypedef(t));
		return ret;
	}

	public function addDefinitions(defs:Array<Definition>, config:Config) {
		var pack = config.pack;
		for (def in defs) {
			switch def {
				case Mixin(i):
					mixins.set(i.name, i);
				case Interface(i):
					type_paths.set(i.name, {
						pack: pack,
						name: i.name
					});
					interfaces.set(i.name, i);
				case Namespace(n):
					addDefinitions(n.members, config);
				case Dictionary(d):
					type_paths.set(d.name, {
						pack: pack,
						name: d.name
					});
					dictionaries.set(d.name, d);
				case Enum(e):
					type_paths.set(e.name, {
						pack: pack,
						name: e.name
					});
					enums.set(e.name, e);
				case Callback(c):
				case Typedef(t):
					type_paths.set(t.name, {
						pack: pack,
						name: t.name
					});
					typedefs.set(t.name, t);
				case Includes(what, included):
					includes.push({what: what, included: included});
				case Partial(d):
					partials.push(d);
			}
		}
		for (name => path in config.typemap)
			type_paths.set(name, path);
	}

	function mergeMixin(mixin:InterfaceType, into:InterfaceType):InterfaceType {
		into.members = into.members.concat(mixin.members);
		return into;
	}

	// static var conversions = new Map<String, String>();
	function typeToHaxe(t:CType):ComplexType {
		return switch t {
			// @formatter:off
			case Rest(typeToHaxe(_) => t): macro :haxe.extern.Rest<$t>;
			case Undefined: macro :Void;
			case Boolean: macro :Bool;
			case Byte,Octet,Short,Bigint: macro :Int;
			case Float,Double,UnrestrictedFloat,UnrestrictedDouble: macro:Float;
			case UnsignedShort: macro :Int;
			case UnsignedLong: macro :Int;
			case UnsignedLongLong: macro :Int;
			case Long: macro :Int;
			case LongLong: macro :Int;
			case ByteString: macro :String;
			case DOMString: macro :String;
			case USVString: macro :String;
			case Promise(typeToHaxe(_) => t): macro :js.lib.Promise<$t>;
			case Record(s, typeToHaxe(_) => t): macro :DynamicAccess<$t>;
			case WithAttributes(e, typeToHaxe(_) => t): t; // TODO
			case Ident(s): 
				if(type_paths.exists(s)){
				var p = getTypePath(s);
				if(p == null) throw "assert";
					TPath(p);
				}else {
					trace("Warning : Failed to resolve identifier " + s);
					macro :Dynamic;
				}
			
			case Sequence(typeToHaxe(_) => t): macro :Array<$t>;
			case Object: macro :{};
			case Symbol: macro :js.lib.Symbol;
			case Union([for(_ in _) typeToHaxe(_)] => t): t.fold((item, result) -> macro :haxe.extern.EitherType<$result,$item>,cast t.pop());
			case Any: macro :Any;
			case Null(typeToHaxe(_) => t): macro :Null<$t>;
			case ArrayBuffer: macro :js.lib.ArrayBuffer;
			case DataView: macro :js.lib.DataView;
			case Int8Array: macro :js.lib.Int8Array;
			case Int16Array: macro :js.lib.Int16Array;
			case Int32Array: macro :js.lib.Int32Array;
			case Uint8Array: macro :js.lib.Uint8Array;
			case Uint16Array: macro :js.lib.Uint16Array;
			case Uint32Array: macro :js.lib.Uint32Array;
			case Uint8ClampedArray: macro :js.lib.Uint8ClampedArray;
			case BigInt64Array: macro:Dynamic; //macro :js.lib.BigInt64Array;
			case BigUint64Array: macro:Dynamic; //macro :js.lib.BigUint64Array;
			case Float32Array: macro :js.lib.Float32Array;
			case Float64Array: macro :js.lib.Float64Array;
			case FrozenArray(typeToHaxe(_) => t): macro :haxe.ds.ReadOnlyArray<$t>;
			// @formatter:on
		}
	}

	function valueToExpr(v:Value) {
		return switch v {
			case String(s): macro $v{s};
			case EmptyDict: macro {};
			case EmptyArray: macro [];
			case Null: macro null;
			case Const(c): constToExpr(c);
		}
	}

	function constToExpr(c:Constant):haxe.macro.Expr {
		return switch c {
			case True: macro true;
			case False: macro false;
			case Integer(s): {
					expr: EConst(CInt(s)),
					pos: (macro null).pos
				}
			case Decimal(s): {
					expr: EConst(CFloat(s)),
					pos: (macro null).pos
				}
			case MinusInfinity: macro Math.INFINITY;
			case Infinity: macro - Math.INFINITY;
			case NaN: macro Math.NaN;
		}
	}

	function convertInterface(i:InterfaceType):TypeDefinition {
		final path:TypePath = getTypePath(i.name);
		final pack = path.pack;

		if (!i.maplike
			&& !i.iterable
			&& !i.setlike
			&& i.members.length > 0
			&& i.members.foreach(item -> item.kind.match(Const(_, _)))) {
			return {
				pack: pack,
				name: i.name,
				pos: cast null,
				kind: TDAbstract(macro:Int),
				fields: [
					for (m in i.members)
						({
							name:m.name, kind:FVar(null, switch m.kind {
								case Const(type, value): constToExpr(value);
								case _: throw "assert";
							}), pos:cast null
						} : Field)
				].concat([
					{
						name: "and",
						kind: FFun({
							args: [
								{
									name: "a",
									type: TPath(path)
								},
								{
									name: "b",
									type: TPath(path)
								}
							],
							ret: TPath(path)
						}),
						pos: (macro null).pos,
						access: [AStatic],
						meta: [
							{
								name: ":op",
								params: [macro A | B],
								pos: (macro null).pos
							}
						]
					}
					]),
				meta: [
					{
						name: ":enum",
						pos: cast null
					}
				]
			};
		} else {
			// TODO : make this work like the spec says
			final fields:Array<Field> = [
				for (f in i.members)
					switch f.kind {
						case Const(type, value):
							{
								name: escape(f.name),
								kind: FVar(typeToHaxe(type), constToExpr(value)),
								pos: (macro null).pos,
								access: [AInline, AStatic],
								meta: if (escape(f.name) != f.name) [
									{
										name: ":native",
										params: [macro $v{f.name}],
										pos: cast null
									}
								] else []
							}
						case Attribute(type, _static, readonly):
							var access:Array<haxe.macro.Expr.Access> = [];
							if (_static)
								access.push(AStatic);
							if (readonly)
								access.push(AFinal);
							{
								name: escape(f.name),
								kind: FVar(typeToHaxe(type)),
								pos: (macro null).pos,
								access: access,
								meta: if (escape(f.name) != f.name) [{name: ":native", params: [macro $v{f.name}], pos: cast null}] else []
							}
						case Function(ret, args, _static):
							{
								name: f.name == "constructor" ? "new" : escape(f.name),
								kind: FFun({
									args: [
										for (a in args)
											{
												name: escape(a.name),
												opt: a.optional,
												type: typeToHaxe(a.type),
												value: a.value == null ? null : valueToExpr(a.value),
												meta: []
											}
									],
									ret: typeToHaxe(ret)
								}),
								pos: (macro null).pos,
								access: _static ? [AStatic] : [],
								meta: if (escape(f.name) != f.name) [{name: ":native", params: [macro $v{f.name}], pos: cast null}] else []
							}
					}
			];
			// for(field in fields)
			if (i.setlike && i.settype != null) {
				var t = typeToHaxe(i.settype);
				return {
					pack: pack,
					name: i.name,
					pos: (macro null).pos,
					kind: TDAlias(i.readonlysetlike ? macro : js.lib.ReadOnlySet<$t>:macro:js.lib.Set<$t>),
					fields: []
				}
			}
			ArraySort.sort(fields, (struct1, struct2) -> {
				var a1:Array<Access> = cast struct1.access == null ? [] : struct1.access;
				var a2:Array<Access> = cast struct2.access == null ? [] : struct2.access;
				if (a1.has(AStatic) && !a2.has(AStatic))
					-1
				else if (struct1.kind.match(FVar(_, _)) && struct2.kind.match(FFun(_)))
					-1
				else
					0;
			});
			return {
				pack: pack,
				name: i.name,
				pos: (macro null).pos,
				kind: TDClass(i.parent == null ? null : try getTypePath(i.parent) catch (_) {
					trace(i.parent);
					null;
				}, null, false, false, false),
				fields: fields,
				isExtern: true,
				meta: [
					{
						name: ":native",
						params: [macro $v{i.name}],
						pos: (macro null).pos
					}
				]
			}
		}
	}

	function convertDictionary(e:DictionaryType):TypeDefinition {
		final path:TypePath = getTypePath(e.name);
		final fields:Array<Field> = [
			for (m in e.members)
				{
					name: m.name,
					kind: FVar(typeToHaxe(m.type), null /**Typedefs do not support default values in haxe**/),
					pos: (macro null).pos,
					meta: if (m.optional) [
						{
							name: ":optional",
							pos: (macro null).pos
						}
					] else null
				}
		];
		return if (e.parent != null) {
			pack: path.pack,
			name: e.name,
			pos: (macro null).pos,
			kind: TDAlias(TExtend([
				try
					getTypePath(e.parent)
				catch (_) {
					trace(e.parent);
					{
						pack: [],
						name: "Dynamic"
					}
				}
			], fields)),
			fields: []
		} else {
			pack: path.pack,
			name: e.name,
			pos: (macro null).pos,
			kind: TDStructure,
			fields: fields
		}
	}

	function toIdent(s:String) {
		s = s.replace("-", "_");
		final r = ~/^[0-9]/m;
		if (r.match(s))
			return "_" + s;
		return s;
	}

	function convertEnum(e:EnumType):TypeDefinition {
		final path:TypePath = getTypePath(e.name);
		return {
			pack: path.pack,
			name: e.name,
			pos: (macro null).pos,
			kind: TDAbstract(macro:String, [macro:String], [macro:String]),
			fields: [
				for (m in e.values)
					{
						name: toIdent(m).toUpperCase(), // Make them higher up in completion
						kind: FVar(null, macro $v{m}),
						pos: (macro null).pos
					}
			],
			meta: [
				{
					name: ":enum",
					pos: (macro null).pos
				}
			]
		}
	}

	function convertTypedef(t:TypedefType):TypeDefinition {
		final path = getTypePath(t.name);
		final r = ~/^(\w+)Flags$/g;
		if (r.match(t.name)) {
			final name = r.matched(1);
			if (type_paths.exists(name))
				return {
					pack: path.pack,
					name: t.name,
					pos: (macro null).pos,
					kind: TDAlias(TPath(getTypePath(name))),
					fields: []
				}
		}
		return {
			pack: path.pack,
			name: t.name,
			pos: (macro null).pos,
			kind: TDAlias(typeToHaxe(t.type)),
			fields: []
		}
	}
}
