package webidl;

import webidl.Ast.CallbackType;
import haxe.ds.ArraySort;
import haxe.macro.Expr;
import haxe.macro.Expr.Field;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.TypeDefinition;
import webidl.Ast.InterfaceType;
import webidl.Ast.DictionaryType;
import webidl.Ast.EnumType;
import webidl.Ast.TypedefType;
import webidl.Ast.Definition;
import haxe.ds.StringMap;

#if !eval
using webidl.Converter.ContextUtils;
#end
using Lambda;
using StringTools;

#if !eval
class ContextUtils {
	public static function makeExpr(_:Class<haxe.macro.Context>, v:Dynamic, pos:Position):haxe.macro.Expr {
		var e:haxe.macro.Expr.ExprDef = switch Type.typeof(v) {
			case TNull: EConst(CIdent("null"));
			case TInt: EConst(CInt(Std.string(v)));
			case TFloat: EConst(CFloat(Std.string(v)));
			case TBool: EConst(CIdent((v : Bool) ? "true" : "false"));
			case TClass(std.String): EConst(CString((v : String)));
			case _: throw "Not supported";
		}
		return {
			expr: e,
			pos: pos
		};
	}

	public static function makePosition(_:Class<haxe.macro.Context>, inf:{min:Int, max:Int, file:String}):haxe.macro.Expr.Position {
		return inf;
	}
}
#end

class Converter {
	static function escape(s:String) {
		return switch s {
			case "interface", "dynamic", "function", "static", "import", "using", "default", "operator", "inline", "continue", "break", "extends", "public",
				"private":
				"_"
				+ s;
			case var s:
				s;
		}
	}

	var interfaces = new StringMap<InterfaceType>();
	var dictionaries = new StringMap<DictionaryType>();
	var enums = new StringMap<EnumType>();
	var typedefs = new StringMap<TypedefType>();
	var callbacks = new StringMap<CallbackType>();

	var mixins = new StringMap<InterfaceType>();
	var includes:Array<{what:String, included:String}> = [];
	var partials:Array<Definition> = [];

	var type_paths = new StringMap<haxe.macro.Expr.TypePath>();
	var config:Config;

	public function new(config) {
		this.config = config;
		for (name => type_path in config.typedefs) {
			type_paths.set(name, type_path);
		}
	}

	public inline function getTypePath(name:String):TypePath {
		return type_paths.exists(name) ? cast type_paths.get(name) : {pack: [], name: name};
	}

	public function convert():Array<TypeDefinition> {
		var ret = [];
		// resolve partials
		for (p in partials)
			switch p {
				case Mixin(part) | Interface(part):
					var i = interfaces.get(part.name);
					if (i == null) {
						interfaces.set(part.name, part);
						continue;
					} else {
						i.attributes = i.attributes.concat(part.attributes);
						i.members = i.members.concat(part.members);
					}
				case Dictionary(part):
					{
						var d = dictionaries.get(part.name);
						if (d == null) {
							dictionaries.set(part.name, part);
						} else {
							d.attributes = d.attributes.concat(part.attributes);
							d.members = d.members.concat(part.members);
						}
					}
				case Namespace(part):
				case d:
					Sys.println("Warning: Partials should be interfaces or namespaces");
			}
		// mix mixins
		for (inc in includes) {
			var i = interfaces.get(inc.included);
			if (i == null) {
				Sys.println('Warning: unknown interface ${inc.included}');
				continue;
			}
			var m = mixins.get(inc.what);
			if (m == null) {
				Sys.println("Warning : Could not find mixin " + inc.what);
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
		for(c in callbacks)
			ret.push(convertCallback(c));
		return ret;
	}

	public function addDefinitions(defs:Array<Definition>) {
		var pack = [];
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
					if (n.members.foreach(i -> i.match(InterfaceMember({name: _, kind: Const(_, _)})))) {
						type_paths.set(n.name, {
							pack: pack,
							name: n.name
						});
						interfaces.set(n.name, {
							name: n.name,
							attributes: [],
							members: [
								for (member in n.members)
									switch member {
										case InterfaceMember({name: name, kind: Const(type, value)}):
											{
												name: name,
												kind: Const(type, value)
											}
										case _:
											throw "assert";
									}
							],
							setlike: false,
							settype: null,
							maptype: null,
							iterabletype: null,
							readonlysetlike: false,
							maplike: false,
							readonlymaplike: false,
							iterable: false,
							keyvalueiterable: false
						});
					} else {
						addDefinitions(n.members);
					}
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
					type_paths.set(c.name, {
						pack: pack,
						name: c.name
					});
					callbacks.set(c.name, c);
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
				case InterfaceMember(i):
			}
		}
	}

	function mergeMixin(mixin:InterfaceType, into:InterfaceType):InterfaceType {
		into.members = into.members.concat(mixin.members);
		return into;
	}

	// static var conversions = new Map<String, String>();
	function typeToHaxe(t:webidl.Ast.CType):ComplexType {
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
			case Record(s, typeToHaxe(_) => t): macro :haxe.DynamicAccess<$t>;
			case WithAttributes(e, typeToHaxe(_) => t): t; // TODO
			case Ident(s): 
				if(type_paths.exists(s)){
					var p = getTypePath(s);
					if(p == null) throw "assert";
					TPath(p);
				}else {
					Sys.println("Warning : Failed to resolve identifier " + s);
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
			case ObservableArray(typeToHaxe(_) => t): macro :Array<$t>;
			// @formatter:on
		}
	}

	function valueToExpr(v:webidl.Ast.Value) {
		return switch v {
			case String(s): macro $v{s};
			case EmptyDict: macro {};
			case EmptyArray: macro [];
			case Null: macro null;
			case Const(c): constToExpr(c);
		}
	}

	function constToExpr(c:webidl.Ast.Constant):haxe.macro.Expr {
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
		final exclude = config.types.exists(i.name) ? (cast config.types.get(i.name) : {var exclude:Array<String>;}).exclude : [];
		if (!i.maplike
			&& !i.iterable
			&& !i.setlike
			&& i.members.length > 0
			&& i.members.foreach(item -> item != null && item.kind.match(Const(_, _)))) {
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
			var overloads = new Map<String, Int>();
			for (f in i.members)
				if (f != null)
					switch f.kind {
						case Function(_, _, _):
							var v = cast overloads.exists(f.name) ? overloads.get(f.name) : 0;
							overloads.set(f.name, v + 1);
						case _:
							continue;
					}
			final fields:Array<Field> = [
				for (f in i.members)
					if (f != null && !exclude.contains(f.name)) switch f.kind {
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
												// value: a.value == null ? null : valueToExpr(a.value),
												meta: []
											}
									],
									ret: typeToHaxe(ret)
								}),
								pos: (macro null).pos,
								access: (_static ? [AStatic] : []).concat(if ((cast overloads.get(f.name) : Int) > 1) [AOverload] else []),
								meta: if (escape(f.name) != f.name) [
									{
										name: ":native",
										params: [macro $v{f.name}],
										pos: cast null
									}
								] else []
							}
						case Iterable(readonly, type):
							continue;
						case Maplike(readonly, type):
							continue;
						case Setlike(readonly, type):
							continue;
						case Deleter:
							continue;
						case Getter, Setter:
							continue;
					}
			];
			// for(field in fields)
			if (i.setlike && i.settype != null) {
				var t = typeToHaxe(i.settype);
				return {
					pack: pack,
					name: i.name,
					pos: (macro null).pos,
					// TODO
					kind: TDAlias(i.readonlysetlike ? macro : js.lib.Set<$t>:macro:js.lib.Set<$t>),
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
		// convert to an abstract, because @:native is not supported on typedefs
		final path:TypePath = getTypePath(e.name);
		var members = e.members;
		if (e.parent != null) {
			final parent = dictionaries.get(e.parent);
			if (parent != null) {
				members = members.concat(parent.members);
			}
		}
		final fields:Array<Field> = [
			for (m in members)
				{
					name: escape(m.name),
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
		final complex_type:ComplexType = TAnonymous(fields);
		var ret_complex_type = TPath(path);
		final abstract_fields:Array<Field> = [
			{
				name: "fromAnon",
				kind: FFun({
					args: [
						{
							name: "foo",
							type: complex_type
						}
					],
					ret: TPath(path),
					expr: macro {
						var ret:$ret_complex_type = cast {};
						$b{
							fields.map(f -> {
								final name = f.name;
								macro ret.$name = foo.$name;
							})
						};
						return ret;
					}
				}),
				pos: (macro null).pos,
				access: [AInline, AExtern, AStatic],
				meta: [
					{
						name: ":from",
						pos: (macro null).pos
					}
				]
			}
		];
		for (m in members) {
			abstract_fields.push({
				name: escape(m.name),
				kind: FProp("get", "set", typeToHaxe(m.type)),
				pos: (macro null).pos,
				access: [APublic]
			});
			abstract_fields.push({
				name: "get_" + escape(m.name),
				kind: FFun({
					args: [],
					ret: typeToHaxe(m.type),
					expr: macro {
						return untyped this[$v{m.name}];
					}
				}),
				pos: (macro null).pos,
				access: [AInline, AExtern, APublic]
			});
			abstract_fields.push({
				name: "set_" + escape(m.name),
				kind: FFun({
					args: [
						{
							name: "value",
							type: typeToHaxe(m.type)
						}
					],
					ret: typeToHaxe(m.type),
					expr: macro {
						untyped this[$v{m.name}] = value;
						return value;
					}
				}),
				pos: (macro null).pos,
				access: [AInline, AExtern, APublic]
			});
		}
		final type_def:TypeDefinition = {
			pack: path.pack,
			name: e.name,
			pos: (macro null).pos,
			kind: TDAbstract(macro:{}),
			fields: abstract_fields
		}
		return type_def;
	}

	function toIdent(s:String) {
		s = s.replace("-", "_").replace("/", "_").replace("+", "_");
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
					if (m != "") {
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

	function convertCallback(c:CallbackType):TypeDefinition {
		final path = getTypePath(c.name);
		return {
			pack: path.pack,
			name: c.name,
			pos: (macro null).pos,
			kind: TDAlias(TFunction(c.args.map(arg -> {
				final t = typeToHaxe(arg.type);
				if (arg.optional || arg.value != null)
					TOptional(t)
				else
					t;
			}), typeToHaxe(c.ret))),
			fields: []
		}
	}
}
