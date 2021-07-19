package webidl;

import webidl.Ast;
import haxe.ds.StringMap;
import sys.FileSystem;
import webidl.Parser.ParserError;
import sys.io.File;

using Lambda;
using StringTools;

class Converter {
	static function merge(what:InterfaceType, into:InterfaceType):InterfaceType {
		// trace(what, into);
		return {
			name: into.name,
			attributes: into.attributes,
			parent: into.parent,
			mixin: false,
			members: into.members.concat(what.members)
		}
	}

	static function typeToHaxe(t:CType) {
		return switch t {
			case Rest(t):
				'haxe.Rest<${typeToHaxe(t)}>';
			case Undefined:
				'Void';
			case Boolean:
				'Bool';
			case Byte:
				'Int';
			case Octet:
				'Int';
			case Short:
				'Int';
			case Bigint:
				'Int';
			case Float:
				'Float';
			case Double:
				'Float';
			case UnsignedShort:
				'Int';
			case UnsignedLong:
				'Int';
			case UnsignedLongLong:
				'Int';
			case UnrestrictedFloat:
				'Float';
			case UnrestrictedDouble:
				'Float';
			case Long:
				'Int';
			case LongLong:
				'Int';
			case ByteString: 'String';
			case DOMString: 'String';
			case USVString: 'String';
			case Promise(t): 'js.lib.Promise<${typeToHaxe(t)}>';
			case Record(s, t): 'haxe.DynamicAccess<${typeToHaxe(t)}>';
			case WithAttributes(e, t): typeToHaxe(t);
			case Ident(s): if (s == "boolean") "Bool" else s;
			case Sequence(t): 'Iterator<${typeToHaxe(t)}>';
			case Object: "Dynamic";
			case Symbol: 'js.lib.Symbol';
			case Union(t): "Dynamic"; // t.fold((item, result) -> 'haxe.extern.EitherType<' + typeToHaxe(t) + ', $result>', typeToHaxe(t.pop()));
			case Any: 'Any';
			case Null(t): 'Null<${typeToHaxe(t)}>';
			case ArrayBuffer, DataView, Int8Array, Int16Array, Int32Array, Uint8Array, Uint16Array, Uint32Array, Uint8ClampedArray, BigInt64Array,
				BigUint64Array, Float32Array, Float64Array: 'js.lib.'
				+ t.getName();
			case FrozenArray(t): 'haxe.ds.ReadOnlyArray<${typeToHaxe(t)}>';
		}
	}

	static var interfaces = new StringMap<InterfaceType>();
	static var dictionaries = new StringMap<DictionaryType>();
	static var enums = new StringMap<EnumType>();
	static var typedefs = new StringMap<TypedefType>();

	// static var conversions = new Map<String, String>();
	static function valueToString(v:Value) {
		return switch v {
			case String(s): '"' + s + '"';
			case EmptyDict: "{}";
			case EmptyArray: "[]";
			case Null: "null";
			case Const(c): constToString(c);
		}
	}

	static function constToString(c:Constant) {
		return switch c {
			case True:
				"true";
			case False:
				"false";
			case Integer(s):
				s;
			case Decimal(s):
				s;
			case MinusInfinity:
				"-Math.INFINITY";
			case Infinity:
				"Math.INFINITY";
			case NaN:
				"Math.NaN";
		}
	}

	static function convertInterface(i:InterfaceType) {
		var o = new StringBuf();
		o.add("package wgpu;\n\n");

		if (i.members.foreach(item -> item.kind.match(Const(_, _)))) {
			o.add("enum abstract " + i.name + "(Int) {\n");
			for (m in i.members) {
				switch m.kind {
					case Const(type, value):
						o.add('    final ' + m.name + ' = ' + constToString(value) + ';\n');
					case _:
						// case Attribute(type, _static, readonly):
						// case Function(ret, args, _static):
				}
			}
		} else {
			o.add('@:native("${i.name}")\n');
			o.add("extern class " + i.name);
			if (i.parent != null) {
				if (i.parent == "EventTarget")
					i.parent = "js.html.EventTarget";
				o.add(' extends ${i.parent}');
			}
			o.add(" {\n");
			for (m in i.members) {
				switch m.kind {
					case Const(type, value):
						if (value != null)
							trace(value);
						o.add('    final ${m.name}:${typeToHaxe(type)};\n');
					case Attribute(type, _static, readonly):
						o.add('    ');
						if (_static)
							o.add('static ');
						o.add(readonly ? 'final ' : 'var ');
						o.add(m.name);
						o.add(':${typeToHaxe(type)};\n');
					case Function(ret, args, _static):
						o.add('    ');
						if (_static)
							o.add('static ');
						o.add('function ${m.name}(');
						o.add([
							for (arg in args)
								'${arg.optional ? "?" : ""}${arg.name}:${typeToHaxe(arg.type)}'
						].join(", "));
						o.add('):${typeToHaxe(ret)};\n');
				}
			}
		}

		o.add("}\n");
		return o.toString();
	}

	// var includes = [];
	// var partials = [];
	// for (def in ast) {
	// 	switch def {
	// 		case Interface(i):
	// 			if (i.partial)
	// 				partials.push(i)
	// 			else
	// 				interfaces.set(i.name, i);
	// 		case Dictionary(d):
	// 			dictionaries.set(d.name, d);
	// 		case Enum(e):
	// 			enums.set(e.name, e);
	// 		case Callback(c):
	// 		case Typedef(t):
	// 			typedefs.set(t.name, t);
	// 		case Include(included, _in):
	// 			includes.push([included, _in]);
	// 		case Namespace(n):
	// 	}
	// }
	// for (i in partials) {
	// 	var int = interfaces.get(i.name);
	// 	if (int != null) {
	// 		int.members = int.members.concat(i.members);
	// 	}
	// 	interfaces.set(i.name, int);
	// }
	// for (i in includes) {
	// 	if (interfaces.exists(i[1]))
	// 		interfaces.set(i[1], merge(interfaces.get(i[0]), interfaces.get(i[1])));
	// }
	// for (i in interfaces) {
	// 	sys.io.File.saveContent("src/wgpu/" + i.name + ".hx", convertInterface(i));
	// }
	// for (t in typedefs) {
	// 	var o = new StringBuf();
	// 	o.add("package wgpu;\n\n");
	// 	o.add("typedef " + t.name + " = " + typeToHaxe(t.type) + ";\n");
	// 	sys.io.File.saveContent("src/wgpu/" + t.name + ".hx", o.toString());
	// }
	// for (d in dictionaries) {
	// 	var o = new StringBuf();
	// 	o.add("package wgpu;\n\n");
	// 	o.add("typedef " + d.name + " = ");
	// 	if (d.parent != null)
	// 		o.add(d.parent + " & ");
	// 	o.add("{\n");
	// 	for (m in d.members) {
	// 		o.add("    var ");
	// 		if (m.optional)
	// 			o.add("?");
	// 		o.add(m.name);
	// 		o.add(':${typeToHaxe(m.type)}');
	// 		// if (m.value != null)
	// 		// 	o.add(' = ${valueToString(m.value)}');
	// 		o.add(";\n");
	// 	}
	// 	o.add("}\n");
	// 	sys.io.File.saveContent("src/wgpu/" + d.name + ".hx", o.toString());
	// }
	// for (e in enums) {
	// 	var o = new StringBuf();
	// 	o.add("package wgpu;\n\n");
	// 	o.add("enum abstract " + e.name + "(String) to String {\n");
	// 	for (v in e.values) {
	// 		o.add("    var ");
	// 		var name = v.toUpperCase().replace("-", '_');
	//         if(~/^[0-9]/i.match(name)) name = "_" + name;
	// 		o.add(name);
	// 		o.add(' = "${v}"');
	// 		o.add(";\n");
	// 	}
	// 	o.add("}\n");
	// 	sys.io.File.saveContent("src/wgpu/" + e.name + ".hx", o.toString());
	// }
}
