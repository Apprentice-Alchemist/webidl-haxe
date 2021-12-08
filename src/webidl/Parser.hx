package webidl;

import webidl.Lexer;
import webidl.Ast;

class ParserError extends haxe.Exception {
	final pos:Pos;
	final msg:String;

	public function new(pos:Pos, message:String) {
		this.pos = pos;
		this.msg = message;
		super(message);
	}

	public function print():String {
		return '${pos.file}:${pos.line}: characters ${pos.min}-${pos.max} : $msg';
	}
}

class Parser {
	public static function parseString(input:String, file:String) {
		// final t = Sys.time();
		var tokens = Lexer.lex(input, file);
		// Sys.println('$file: lexer: ${Sys.time() - t}s');
		// trace(tokens.map(t -> t.t)[0]);
		// final t = Sys.time();
		final ast = new Parser(tokens).parse();
		// Sys.println('$file: parser: ${Sys.time() - t}s');
		return ast;
	}

	var current_token:Token;
	var tokens:Array<Token>;
	var used_tokens:Array<Token>;

	public function new(tokens:Array<Token>) {
		this.tokens = tokens;
		this.used_tokens = new Array();
		this.current_token = cast null;
	}

	static function tokenToString(t:TokenKind) {
		return switch t {
			case TSquareBracketOpen:
				"[";
			case TSquareBracketClose:
				"]";
			case TBraceOpen:
				"{";
			case TBraceClose:
				"}";
			case TParenOpen:
				"(";
			case TParenClose:
				")";
			case TLeftArrow:
				"<";
			case TRightArrow:
				">";
			case TColon:
				":";
			case TSemicolon:
				";";
			case TComma:
				",";
			case TEqual:
				"=";
			case TQuestion:
				"?";
			case TString(s):
				'"$s"';
			case TInteger(s), TDecimal(s), TKeyword(s), TIdent(s):
				s;
			case TEof:
				"<eof>";
			case TDotDotDot:
				"...";
		}
	}

	static function comp(a:TokenKind, b:TokenKind):Bool {
		return switch a {
			case TString(as): switch b {
					case TString(bs): as == bs;
					case _: false;
				}
			case TInteger(as): switch b {
					case TInteger(bs): as == bs;
					case _: false;
				}
			case TDecimal(as): switch b {
					case TDecimal(bs): as == bs;
					case _: false;
				}
			case TKeyword(as): switch b {
					case TKeyword(bs): as == bs;
					case _: false;
				}
			case TIdent(as): switch b {
					case TIdent(bs): as == bs;
					case _: false;
				}
			case _: a == b;
		}
	}

	inline function token() {
		current_token = cast tokens.shift();
		used_tokens.push(current_token);
		return current_token.t;
	}

	inline function restore() {
		var t = used_tokens.pop();
		if (t == null)
			throw "";
		tokens.unshift(cast t);
		current_token = cast t;
		return t.t;
	}

	inline function unexpected(?t:Token, ?pos:haxe.PosInfos) {
		if (t == null)
			t = current_token;
		// trace([for (t in used_tokens) tokenToString(t.t)].concat([tokenToString(tokens[0].t), tokenToString(tokens[1].t)]).join(" "));
		haxe.Log.trace(used_tokens[used_tokens.length - 2], pos);
		return new ParserError(t.pos, "Unexpected " + tokenToString(t.t));
	}

	function match(...rest:TokenKind) {
		var count = 0;
		for (t in rest) {
			var _t = token();
			count++;
			if (!comp(t, _t)) {
				for (_ in 0...count)
					restore();
				return false;
			}
		}
		return true;
	}

	inline function consume(...rest:TokenKind) {
		for (t in rest) {
			var _t = token();
			if (comp(t, _t)) {
				continue;
			} else {
				trace(used_tokens[used_tokens.length - 2]);
				throw new ParserError(current_token.pos, 'Unexpected ${tokenToString(_t)}, expected ${tokenToString(t)}');
			}
		}
	}

	function ident(?pos:haxe.PosInfos):String {
		return switch token() {
			case TIdent(s) | TKeyword(s):
				s;
			case var t:
				trace(t);
				throw new ParserError(current_token.pos, "Expected identifier");
		}
	}

	function parseConstant():Constant {
		return switch token() {
			case TIdent("true"): True;
			case TIdent("false"): False;
			case TInteger(s): Integer(s);
			case TDecimal(s): Decimal(s);
			case TIdent("Infinity"): Infinity;
			case TIdent("-Infinity"): MinusInfinity;
			case TIdent("NaN"): NaN;
			case _:
				throw unexpected();
		}
	}

	function parseValue():Value {
		return switch token() {
			case TIdent("null"): Null;
			case TString(s): String(s);
			case TBraceOpen if (match(TBraceClose)): EmptyDict;
			case TSquareBracketOpen if (match(TSquareBracketClose)): EmptyArray;
			case _:
				restore();
				Const(parseConstant());
		}
	}

	function parseExtendedAttributes():ExtendedAttributes {
		function parseAttribute():ExtendedAttribute {
			var name = ident();
			var kind:ExtendedAttributeKind = if (match(TEqual)) {
				switch token() {
					case TString(s), TIdent(s):
						if (match(TParenOpen)) {
							restore();
							ExtendedAttributeNamedArgList(name, parseArguments());
						} else ExtendedAttributeIdent(s);
					case TParenOpen:
						if (tokens[0].t.match(TIdent(_)) && tokens[1].t.match(TComma | TParenClose)) {
							var l = [];
							do {
								l.push(ident());
							} while (match(TComma));
							consume(TParenClose);
							ExtendedAttributeIdentList(l);
						} else {
							restore();
							ExtendedAttributeNamedArgList(name, parseArguments());
						}
					case var t:
						throw unexpected(current_token);
						// throw new ParserError(current_token.pos, 'Did not expect this token : $t.');
				}
			} else if (match(TParenOpen)) {
				var l = [];
				do {
					l.push(ident());
				} while (match(TComma));
				consume(TParenClose);
				ExtendedAttributeIdentList(l);
			} else {
				ExtendedAttributeNoArg;
			}
			return {
				name: name,
				kind: kind
			};
		}
		if (match(TSquareBracketOpen)) {
			var a = [];
			do {
				a.push(parseAttribute());
			} while (match(TComma));
			consume(TSquareBracketClose);
			return a;
		}
		return [];
	}

	function parseType():CType {
		var attributes = parseExtendedAttributes();
		var t = switch token() {
			case TIdent("undefined"): Undefined;
			case TIdent("boolean"): Boolean;
			case TIdent("any"): Any;
			case TIdent("byte"): Byte;
			case TIdent("octet"): Octet;
			case TIdent("short"): Short;
			case TIdent("long") if (match(TIdent("long"))): LongLong;
			case TIdent("long"): Long;
			case TIdent("unsigned"):
				switch token() {
					case TIdent("short"): UnsignedShort;
					case TIdent("long"): if (match(TIdent("long"))) UnsignedLongLong else UnsignedLong;
					case _: throw new ParserError(current_token.pos, "Expected one of short, long or long long.");
				}
			case TIdent("float"): Float;
			case TIdent("double"): Double;
			case TKeyword(Unrestricted):
				switch token() {
					case TIdent("float"): UnrestrictedFloat;
					case TIdent("double"): UnrestrictedFloat;
					case _: throw new ParserError(current_token.pos, "Expected float or double.");
				}
			case TIdent("bigint"): Bigint;
			case TIdent("DOMString"): DOMString;
			case TIdent("ByteString"): ByteString;
			case TIdent("USVString"): USVString;
			case TIdent("object"): Object;
			case TIdent("symbol"): Symbol;
			case TIdent("sequence"):
				consume(TLeftArrow);
				var t = parseType();
				consume(TRightArrow);
				Sequence(t);
			case TIdent("FrozenArray"):
				consume(TLeftArrow);
				var t = parseType();
				consume(TRightArrow);
				FrozenArray(t);
			case TIdent("record"):
				consume(TLeftArrow);
				var s = parseType();
				consume(TComma);
				var t = parseType();
				consume(TRightArrow);
				Record(s, t);
			case TIdent("Promise"):
				consume(TLeftArrow);
				var t = parseType();
				consume(TRightArrow);
				Promise(t);
			case TIdent("ObservableArray"):
				consume(TLeftArrow);
				var t = parseType();
				consume(TRightArrow);
				Ident("ObservableArray");
			case TIdent(s):
				var c:Null<CType> = null;
				for (t in CType.getConstructors())
					if (s == t)
						c = CType.createByName(t);
				c == null ? Ident(s) : (c : CType);
			case TParenOpen:
				var types = [];
				do {
					types.push(parseType());
				} while (match(TIdent("or")));
				consume(TParenClose);
				Union(types);
			case _:
				throw unexpected();
		}
		t = if (match(TQuestion)) Null(t) else t;
		t = if (match(TDotDotDot)) Rest(t) else t;
		t = if (attributes.length > 0) WithAttributes(attributes, t) else t;
		return t;
	}

	function parseArguments() {
		var args:Array<Argument> = [];
		if (match(TParenOpen)) {
			if (!match(TParenClose)) {
				do {
					var optional = match(TIdent("optional"));
					var t = parseType();
					var name = ident();
					var value = if (match(TEqual)) parseValue() else null;
					args.push({
						name: name,
						type: t,
						optional: optional,
						value: value
					});
				} while (match(TComma));
				consume(TParenClose);
			}
		}
		return args;
	}

	function parseInterfaceMember():InterfaceMember {
		var att = parseExtendedAttributes();
		if (match(TKeyword(Constructor))) {
			var args:Array<Argument> = parseArguments();
			consume(TSemicolon);
			return {
				name: "constructor",
				kind: Function(Undefined, args, false)
			};
		} else if (match(TKeyword(Const))) {
			var type = parseType();
			var name = ident();
			var value = if (match(TEqual)) parseConstant() else null;
			consume(TSemicolon);
			return {
				name: name,
				kind: Const(type, cast value)
			};
		} else {
			var stringifier = match(TKeyword(Stringifier));
			var inherit = match(TKeyword(Inherit));
			var async = match(TKeyword(Async));
			if (!match(TSemicolon)) {
				var _static = !stringifier && match(TKeyword(Static));
				var readonly = match(TKeyword(Readonly));

				if (match(TKeyword(Deleter))) {
					parseType();
					switch token() {
						case TIdent(_):
							consume(TParenOpen);
						case TParenOpen:
						case _: throw unexpected();
					}
					var type = parseType();
					ident();
					consume(TParenClose, TSemicolon);
					return {name: null, kind: Deleter};
				} else if (match(TKeyword(Iterable))) {
					consume(TLeftArrow);
					var type = parseType();
					if (match(TComma)) {
						parseType();
					}
					consume(TRightArrow);
					parseArguments();
					consume(TSemicolon);
					return {name: null, kind: Iterable(readonly, type)};
				} else if (match(TKeyword(Setlike))) {
					consume(TLeftArrow);
					var type = parseType();
					consume(TRightArrow, TSemicolon);
					return {name: null, kind: Setlike(readonly, type)}
				} else if (match(TKeyword(Maplike))) {
					consume(TLeftArrow);
					var type = parseType();
					if (match(TComma)) {
						parseType();
					}
					consume(TRightArrow, TSemicolon);
					return {name: null, kind: Maplike(readonly, type)}
				} else if (match(TKeyword(Attribute))) {
					var type = parseType();
					var name = ident();
					consume(TSemicolon);
					return {
						name: name,
						kind: Attribute(type, _static, readonly)
					};
				} else if (readonly) {
					trace(current_token);
					throw new ParserError((cast tokens.pop()).pos, "Expected attribute");
				} else if (match(TKeyword(Getter))) {
					parseType();
					switch token() {
						case TIdent(s):
							consume(TParenOpen);
						case TParenOpen:
						case _:
							throw unexpected();
					}
					parseType();
					ident();
					consume(TParenClose, TSemicolon);
					Getter;
				} else if (match(TKeyword(Setter))) {
					parseType();
					switch token() {
						case TIdent(s):
							consume(TParenOpen);
						case TParenOpen:

						case _:
							throw unexpected();
					}
					parseType();
					ident();
					if (match(TComma)) {
						parseType();
						ident();
					}
					consume(TParenClose);
					Setter;
				} else if (false) {
					parseType();
					ident();
					consume(TComma);
					parseType();
					ident();
					consume(TParenClose, TSemicolon);
				} else {
					var type = parseType();
					var name = ident();
					var args:Array<Argument> = parseArguments();
					consume(TSemicolon);
					return {
						name: name,
						kind: Function(type, args, false)
					};
				}
			}
		}
		return cast null;
	}

	function parseDefinition():Definition {
		var attributes = parseExtendedAttributes();
		var partial = match(TKeyword(Partial));
		var t = switch token() {
			case TKeyword(k):
				switch k {
					case Interface:
						var mixin = match(TKeyword(Mixin));
						var name = ident();
						var parent = if (match(TColon)) ident() else null;
						var setlike = false;
						var readonlyset = false;
						var settype = cast null;

						var maplike = false;
						var readonlymap = false;
						var maptype = cast null;

						var iterablelike = false;
						var iterabletype = cast null;
						var members:Array<InterfaceMember> = [];
						if (match(TSemicolon)) {
							// turns out empty interfaces are a thing in firefox's webidl's
						} else {
							consume(TBraceOpen);
							while (!match(TBraceClose, TSemicolon)) {
								var att = parseExtendedAttributes();
								{
									members.push(parseInterfaceMember());
								}
							}
						}
						var i:InterfaceType = {
							name: name,
							parent: parent,
							members: members,
							attributes: attributes,
							setlike: setlike,
							readonlysetlike: readonlyset,
							maplike: maplike,
							readonlymaplike: readonlymap,
							maptype: maptype,
							settype: settype,
							iterable: iterablelike,
							iterabletype: iterabletype,
							keyvalueiterable: false
						};
						mixin ? Mixin(i) : Interface(i);
					case Callback:
						if (match(TKeyword(Interface))) {
							restore();
							return parseDefinition();
						}
						var name = ident();
						consume(TEqual);
						var ret = parseType();
						var args = [];
						consume(TParenOpen);
						if (!match(TParenClose)) {
							do {
								var optional = match(TIdent("optional"));
								var t = parseType();
								var name = ident();
								var value = if (match(TEqual)) parseValue() else null;
								args.push({
									name: name,
									type: t,
									optional: optional,
									value: value
								});
							} while (match(TComma));
							consume(TParenClose);
						}
						consume(TSemicolon);
						Callback({
							name: name,
							attributes: attributes,
							ret: ret,
							args: args
						});
					case Dictionary:
						var name = ident();
						var parent = if (match(TColon)) ident() else null;
						var members = [];
						consume(TBraceOpen);
						while (!match(TBraceClose, TSemicolon)) {
							parseExtendedAttributes();
							var required = match(TKeyword(Required));
							var type = parseType();
							var name = ident();
							var value = if (match(TEqual)) parseValue() else null;
							consume(TSemicolon);
							members.push({
								name: name,
								optional: !required,
								type: type,
								value: value
							});
						}
						Dictionary({
							name: name,
							// partial: partial,
							attributes: attributes,
							members: members,
							parent: parent
						});
					case Enum:
						var name = ident();
						consume(TBraceOpen);
						var values = [];
						function str() {
							return switch token() {
								case TString(s): s;
								case _:
									throw unexpected();
							}
						}

						var consumed = false;
						do {
							if (match(TBraceClose, TSemicolon)) {
								consumed = true;
								break;
							}
							values.push(str());
						} while (match(TComma));
						if (!consumed)
							consume(TBraceClose, TSemicolon);
						Enum({
							name: name,
							attributes: attributes,
							values: values
						});
					case Namespace:
						var name = ident();
						consume(TBraceOpen);
						var defs = [
							while (!match(TBraceClose, TSemicolon)) {
								parseDefinition();
							}
						];
						Namespace({
							name: name,
							members: defs
						});
					case Typedef:
						var t = parseType();
						var name = ident();
						consume(TSemicolon);
						Typedef({
							// type_attributes: attributes,
							type: t,
							name: name
						});
					// case Const:
					// 	var type = parseType();
					// 	var name = ident();
					// 	consume(TEqual);
					// 	var value = parseConstant();
					// 	consume(TSemicolon);
					// 	Definition.Const(name, type, value);
					case _:
						restore();
						InterfaceMember(parseInterfaceMember());
				}
			case TIdent(s) if (match(TKeyword(Includes)) || match(TKeyword(Implements))):
				var x = ident();
				consume(TSemicolon);
				Includes(x, s);
			case _:
				restore();
				InterfaceMember(parseInterfaceMember());
		}
		return partial ? Partial(t) : t;
	}

	public function parse() {
		return [
			while (!match(TEof))
				parseDefinition()
		];
	}
}
