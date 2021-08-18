package webidl;

import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.Field;
import haxe.macro.Expr.TypeDefinition;

using Lambda;

class Printer extends haxe.macro.Printer {
	override function printComplexType(ct:ComplexType):String {
		return switch (ct) {
			case TPath(tp): printTypePath(tp);
			case TFunction(args, ret):
				var wrapArgumentsInParentheses = switch args {
					// type `:(a:X) -> Y` has args as [TParent(TNamed(...))], i.e `a:X` gets wrapped in `TParent()`. We don't add parentheses to avoid printing `:((a:X)) -> Y`
					case [TParent(t)]: false;
					// this case catches a single argument that's a type-path, so that `X -> Y` prints `X -> Y` not `(X) -> Y`
					case [TPath(_) | TOptional(TPath(_))]: false;
					default: true;
				}
				var argStr = args.map(printComplexType).join(", ");
				(wrapArgumentsInParentheses ? '($argStr)' : argStr) + " -> " + (switch ret {
					// wrap return type in parentheses if it's also a function
					case TFunction(_): '(${printComplexType(ret)})';
					default: (printComplexType(ret) : String);
				});
			case TAnonymous(fields): "{\n" + [for (f in fields) printField(f) + "; "].join("    \n") + "\n}";
			case TParent(ct): "(" + printComplexType(ct) + ")";
			case TOptional(ct): "?" + printComplexType(ct);
			case TNamed(n, ct): n + ":" + printComplexType(ct);
			case TExtend(tpl, fields):
				var types = [for (t in tpl) "> " + printTypePath(t) + ", "].join("");
				var fields = [for (f in fields) printField(f) + "; "].join("");
				'{${types}${fields}}';
			case TIntersection(tl): tl.map(printComplexType).join(" & ");
		}
	}

	override function printStructure(fields:Array<Field>):String {
		return fields.length == 0 ? "{}" : '{\n$tabs' + fields.map(printField).join(';\n$tabs') + ";\n}";
	}

	override function printTypeDefinition(t:TypeDefinition, printPackage:Bool = true):String {
		var old = tabs;
		tabs = tabString;

		var str = t == null ? "#NULL" : (printPackage
			&& t.pack.length > 0
			&& t.pack[0] != "" ? "package " + t.pack.join(".") + ";\n\n" : "")
			+ (t.doc != null && t.doc != "" ? "/**\n" + tabString + StringTools.replace(t.doc, "\n", "\n" + tabString) + "\n**/\n" : "")
			+ (t.meta != null && t.meta.length > 0 ? t.meta.map(printMetadata).join("\n") + "\n" : "")
			+ (t.isExtern ? "extern " : "")
			+ switch (t.kind) {
				case TDEnum:
					"enum "
					+ t.name
					+ ((t.params != null && t.params.length > 0) ? "<" + t.params.map(printTypeParamDecl).join(", ") + ">" : "")
					+ " {\n"
					+ [
						for (field in t.fields)
							tabs
							+ (field.doc != null
								&& field.doc != "" ? "/**\n"
									+ tabs
									+ tabString
									+ StringTools.replace(field.doc, "\n", "\n" + tabs + tabString)
									+ "\n"
									+ tabs
									+ "**/\n"
									+ tabs : "")
							+ (field.meta != null && field.meta.length > 0 ? field.meta.map(printMetadata).join(" ") + " " : "")
							+ (switch (field.kind) {
								case FVar(t, _): field.name + opt(t, printComplexType, ":");
								case FProp(_, _, _, _): throw "FProp is invalid for TDEnum.";
								case FFun(func): field.name + printFunction(func);
							})
							+ ";"].join("\n") + "\n}";
				case TDStructure:
					"typedef "
					+ t.name
					+ ((t.params != null && t.params.length > 0) ? "<" + t.params.map(printTypeParamDecl).join(", ") + ">" : "")
					+ " = {\n"
					+ [
						for (f in t.fields) {
							tabs + printField(f) + ";";
						}
					].join("\n") + "\n}";
				case TDClass(superClass, interfaces, isInterface, isFinal, isAbstract):
					(isFinal ? "final " : "")
						+ (isAbstract ? "abstract " : "")
						+ (isInterface ? "interface " : "class ")
						+ t.name
						+ (t.params != null && t.params.length > 0 ? "<" + t.params.map(printTypeParamDecl).join(", ") + ">" : "")
						+ (superClass != null ? " extends " + printTypePath(superClass) : "")
						+ (interfaces != null ? (isInterface ? [for (tp in interfaces) " extends " + printTypePath(tp)] : [
							for (tp in interfaces)
								" implements " + printTypePath(tp)
						]).join("") : "")
						+ " {\n"
						+ [
							for (f in t.fields) {
								tabs + printFieldWithDelimiter(f);
							}
						].join("\n") + "\n}";
				case TDAlias(ct):
					"typedef "
					+ t.name
					+ ((t.params != null && t.params.length > 0) ? "<" + t.params.map(printTypeParamDecl).join(", ") + ">" : "")
					+ " = "
					+ (switch (ct) {
						case TExtend(tpl, fields): printExtension(tpl, fields);
						case TAnonymous(fields): printStructure(fields);
						case _: printComplexType(ct);
					})
					+ ";";
				case TDAbstract(tthis, from, to):
					"abstract "
					+ t.name
					+ ((t.params != null && t.params.length > 0) ? "<" + t.params.map(printTypeParamDecl).join(", ") + ">" : "")
					+ (tthis == null ? "" : "(" + printComplexType(tthis) + ")")
					+ (from == null ? "" : [for (f in from) " from " + printComplexType(f)].join(""))
					+ (to == null ? "" : [for (t in to) " to " + printComplexType(t)].join(""))
					+ " {\n"
					+ [
						for (f in t.fields) {
							tabs + printFieldWithDelimiter(f);
						}
					].join("\n") + "\n}";
				case TDField(kind, access):
					tabs = old;
					(access != null && access.length > 0 ? access.map(printAccess).join(" ") + " " : "") + switch (kind) {
						case FVar(type,
							eo): ((access != null && access.has(AFinal)) ? '' : 'var ') + '${t.name}' + opt(type, printComplexType, " : ")
								+ opt(eo, printExpr, " = ") + ";";
						case FProp(get, set, type, eo): 'var ${t.name}($get, $set)'
							+ opt(type, printComplexType, " : ")
							+ opt(eo, printExpr, " = ")
							+ ";";
						case FFun(func): 'function ${t.name}' + printFunction(func) + switch func.expr {
								case {expr: EBlock(_)}: "";
								case _: ";";
							};
					}
			} tabs = old;

		return str;
	}
}
