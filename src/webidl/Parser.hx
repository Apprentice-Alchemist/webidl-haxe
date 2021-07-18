package webidl;

import webidl.Ast;

class ParserError extends haxe.Exception {
	final pos:Position;
	final msg:String;

	public function new(pos:Position, message:String) {
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
		return parse(lex(input, file));
	}

	static inline function error(pos:Position, message:String) {
		throw new ParserError(pos, message);
	}

	// static function unexpected(t:Token) {
	// 	error(t.pos, "Unexpected " + tokenToString(t));
	// }

	static function tokenToString(t:TokenKind) {
		return switch t {
			case TComment:
				"";
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
			case TNumber(s):
				s;
			case TKeyword(k):
				k;
			case TIdent(s):
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
			case TNumber(as): switch b {
					case TNumber(bs): as == bs;
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

	public static function parse(tokens:Array<Token>) {
		var current_token:Token;

		function token() {
			current_token = tokens.shift();
			// trace(current_token);
			return current_token.t;
		}

		function unexpected(?t:Token, ?pos:haxe.PosInfos) {
			// haxe.Log.trace("unexpected", pos);
			if (t == null)
				t = current_token;
			error(t.pos, "Unexpected " + tokenToString(t.t));
			throw "";
		}

		function match(...rest:TokenKind) {
			var toshift = 0;
			for (t in rest) {
				var _t = tokens[toshift++];
				if (!comp(t, _t.t)) {
					return false;
				}
			}
			for (_ in 0...toshift)
				current_token = tokens.shift();
			return true;
		}

		function consume(...rest:TokenKind) {
			for (t in rest) {
				var _t = tokens[0];
				if (comp(t, _t.t)) {
					tokens.shift();
					continue;
				} else {
					error(_t.pos, 'Unexpected ${tokenToString(_t.t)}, expected ${tokenToString(t)}');
				}
			}
		}

		function ident(?pos:haxe.PosInfos):String {
			// haxe.Log.trace("ident", pos);
			return switch token() {
				case TIdent(s) | TKeyword(s):
					s;
				case var t:
					error(current_token.pos, "Expected identifier");
					throw "";
			}
		}

		function parseConstant():Constant {
			return switch token() {
				case TIdent("true"): True;
				case TIdent("false"): False;
				case TNumber(s): Decimal(s);
				case TIdent("Infinity"): Infinity;
				case TIdent("-Infinity"): MinusInfinity;
				case TIdent("NaN"): NaN;
				case _:
					unexpected();
					throw "";
			}
		}

		function parseValue():Value {
			return switch token() {
				case TIdent("null"): Null;
				case TString(s): String(s);
				case TBraceOpen if (match(TBraceClose)): EmptyDict;
				case TSquareBracketOpen if (match(TSquareBracketClose)): EmptyArray;
				case _:
					tokens.unshift(current_token);
					Const(parseConstant());
			}
		}

		function parseExtendedAttributes():ExtendedAttributes {
			function parseAttribute():ExtendedAttribute {
				var name = ident();
				var kind:ExtendedAttributeKind = if (match(TEqual)) {
					switch token() {
						case TIdent(s): ExtendedAttributeIdent(s);
						case TParenOpen:
							var l = [];
							do {
								l.push(ident());
							} while (match(TComma));
							consume(TParenClose);
							ExtendedAttributeIdentList(l);
						case var t:
							error(current_token.pos, "Did not expect this token.");
							throw "";
					}
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
				case TIdent("byte"): Byte;
				case TIdent("octet"): Octet;
				case TIdent("short"): Short;
				case TIdent("long") if (match(TIdent("long"))): LongLong;
				case TIdent("long"): Long;
				case TIdent("unsigned"):
					if (match(TIdent("short"))) UnsignedShort else if (match(TIdent("long"),
						TIdent("long"))) UnsignedLongLong else if (match(TIdent("long"))) UnsignedLong else throw new ParserError(tokens[0].pos,
						"Expected one of short, long or long long.");
				case TIdent("float"): Float;
				case TIdent("double"): Double;
				case TIdent("unrestricted"):
					switch token() {
						case TIdent("float"): UnrestrictedFloat;
						case TIdent("double"): UnrestrictedFloat;
						case _: throw new ParserError(tokens[0].pos, "Expected float or double.");
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
				case TIdent(s): Ident(s);
				case TParenOpen:
					var types = [];
					do {
						types.push(parseType());
					} while (match(TIdent("or")));
					consume(TParenClose);
					Union(types);
				case _:
					unexpected();
					throw "";
			}
			t = if (match(TQuestion)) Null(t) else t;
			t = if (match(TDotDotDot)) Rest(t) else t;
			t = if (attributes.length > 0) WithAttributes(attributes, t) else t;
			return t;
		}

		function parseDefinition():Definition {
			var attributes = parseExtendedAttributes();
			var partial = match(TKeyword(Partial));
			return switch token() {
				case TKeyword(k):
					switch k {
						case Interface:
							var mixin = match(TKeyword(Mixin));
							var name = ident();
							var parent = if (match(TColon)) ident() else null;
							var setlike = false;
							var readonlyset = false;
							var settype = null;
							consume(TBraceOpen);
							var members:Array<InterfaceMember> = [];
							while (!match(TBraceClose, TSemicolon)) {
								var att = parseExtendedAttributes();
								if (match(TKeyword(Constructor))) {
									var args:Array<Argument> = [];
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
									members.push({
										name: "constructor",
										kind: Function(Undefined, args)
									});
								} else if (match(TKeyword(Const))) {
									var type = parseType();
									var name = ident();
									var value = if (match(TEqual)) parseConstant() else null;
									consume(TSemicolon);
									members.push({
										name: name,
										kind: Const(type, value)
									});
								} else {
									var stringifier = match(TKeyword(Stringifier));
									var _static = !stringifier && match(TKeyword(Static));
									var readonly = match(TKeyword(Readonly));
									if (match(TKeyword(Setlike))) {
										setlike = true;
										readonlyset = readonly;
										consume(TLeftArrow);
										settype = parseType();
										consume(TRightArrow, TSemicolon);
									} else if (match(TKeyword(Attribute))) {
										var type = parseType();
										var name = ident();
										consume(TSemicolon);
										members.push({
											name: name,
											kind: Attribute(type, _static, readonly)
										});
									} else if (readonly) {
										error(tokens[0].pos, "Expected attribute");
									} else {
										var type = parseType();
										var name = ident();
										var args:Array<Argument> = [];
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
										members.push({
											name: name,
											kind: Function(type, args)
										});
									}
								}
							}
							Interface({
								name: name,
								parent: parent,
								mixin: mixin,
								members: members,
								attributes: attributes,
								partial: partial
							});
						case Callback: null;
						case Dictionary:
							var name = ident();
							var parent = if (match(TColon)) ident() else null;
							var members = [];
							consume(TBraceOpen);
							while (!match(TBraceClose, TSemicolon)) {
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
								partial: partial,
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
										unexpected();
										throw "";
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
							var defs = [
								while (!match(TBraceClose, TSemicolon)) {
									parseDefinition();
								}
							];
							Namespace({
								name: name,
								partial: partial,
								members: defs
							});
						case Typedef:
							var t = parseType();
							var name = ident();
							consume(TSemicolon);
							Typedef({
								type_attributes: attributes,
								type: t,
								name: name
							});
						case _:
							unexpected();
							throw "";
					}
				case TIdent(s) if (match(TKeyword(Includes))):
					var x = ident();
					consume(TSemicolon);
					Include(x, s);
				case _:
					unexpected();
					throw "";
			}
		}

		return [
			while (!match(TEof))
				parseDefinition()
		];
	}

	public static function lex(input:String, file:String):Array<Token> {
		var pos = 0;
		var line = 1;
		var linepos = 1;

		function incpos() {
			linepos++;
			return pos++;
		}
		function incline() {
			line++;
			linepos = 1;
			return pos++;
		}
		function next()
			return input.charCodeAt(incpos());
		function current()
			return input.charCodeAt(pos);
		function peek()
			return input.charCodeAt(pos + 1);

		function isAlpha(c:Int) {
			return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code);
		}
		function isNum(c:Int) {
			return c >= "0".code && c <= "9".code;
		}
		function isAlphaNum(c:Int) {
			return isAlpha(c) || isNum(c);
		}
		function eatWhitespace() {
			while (true) {
				switch current() {
					case " ".code, "\t".code, "\r".code:
						incpos();
					case "\n".code:
						incline();
					case _:
						break;
				}
			}
		}
		function match(s:String):Bool {
			if (input.substr(pos, s.length) == s && !isAlphaNum(input.charCodeAt(pos + s.length))) {
				pos += s.length;
				linepos += s.length;
				return true;
			}
			return false;
		}
		function escape(c:Int) {
			return switch c {
				case "\\".code:
					"\\".code;
				case "n".code:
					"\n".code;
				case "r".code:
					"\r".code;
				case "t".code:
					"\t".code;
				case var c:
					throw "Invalid escape sequence : " + "\\" + std.String.fromCharCode(c);
			}
		}
		function readStringUntil(ec:Int) {
			var s = new StringBuf();
			while (true) {
				var c = next();
				if (c == ec)
					break;
				else if (c == "\\".code) {
					s.addChar(escape(next()));
				} else {
					s.addChar(c);
				}
			}
			return s.toString();
		}

		function token() {
			eatWhitespace();
			var start = linepos;
			var c = next();
			var t = switch c {
				case "[".code: TSquareBracketOpen;
				case "]".code: TSquareBracketClose;
				case "{".code: TBraceOpen;
				case "}".code: TBraceClose;
				case "(".code: TParenOpen;
				case ")".code: TParenClose;
				case "<".code: TLeftArrow;
				case ">".code: TRightArrow;
				case ":".code: TColon;
				case ";".code: TSemicolon;
				case ",".code: TComma;
				case "=".code: TEqual;
				case "?".code: TQuestion;
				case '"'.code: TString(readStringUntil('"'.code));
				case "'".code: TString(readStringUntil("'".code));
				case null: TEof;
				case _:
					var t = null;
					pos--;
					linepos--;
					if (c == "/".code) {
						while (next() != "\n".code) {}
						line++;
						linepos = 0;
						t = TComment;
					}
					if (t == null)
						if (match("-Infinity")) {
							t = TIdent("-Infinity");
						}
					if (t == null)
						for (k in Keyword.ALL_KEYWORDS) {
							if (match(k)) {
								t = TKeyword(k);
								break;
							}
						}
					if (t == null) {
						var s = new StringBuf();
						if (isAlpha(c) || c == "_".code || c == "-".code) {
							// s.addChar(c);
							while (true) {
								var c = current();
								if (isAlphaNum(c) || c == "_".code || c == "-".code) {
									s.addChar(c);
									incpos();
								} else {
									break;
								}
							}
							t = TIdent(s.toString());
						} else if (isNum(current())) {
							// Really dirty hack, because parsing numbers is a real pain
							while (true) {
								var c = current();
								if (isAlphaNum(c)) {
									s.addChar(c);
									incpos();
								} else {
									break;
								}
							}
							t = TNumber(s.toString());
						}
					}
					if (match("..."))
						t = TDotDotDot;
					if (t == null) {
						trace(input.substring(pos - 10, pos + 10));
						error({
							file: file,
							line: line,
							min: start,
							max: linepos
						}, "Invalid character : " + std.String.fromCharCode(c));
					}
					t;
			}
			return {
				t: t,
				pos: {
					file: file,
					line: line,
					min: start,
					max: linepos
				}
			}
		}
		var a = [];
		while (true) {
			var t = token();
			if (t.t != TComment)
				a.push(t);
			if (t.t == TEof)
				break;
		}
		return a;
	}

	static function fromCharCode(c:Int):Null<String> {
		return try std.String.fromCharCode(c) catch (e) null;
	}
}

private enum abstract Keyword(String) to String {
	public static final ALL_KEYWORDS = [
		Async, Attribute, Callback, Const, Constructor, Deleter, Dictionary, Enum, Getter, Includes, Inherit, Interface, Iterable, Maplike, Mixin, Namespace,
		Partial, Readonly, Required, Setlike, Setter, Static, Stringifier, Typedef, Unrestricted,
	];
	var Async = "async";
	var Attribute = "attribute";
	var Callback = "callback";
	var Const = "const";
	var Constructor = "constructor";
	var Deleter = "deleter";
	var Dictionary = "dictionary";
	var Enum = "enum";
	var Getter = "getter";
	var Includes = "includes";
	var Inherit = "inherit";
	var Interface = "interface";
	var Iterable = "iterable";
	var Maplike = "maplike";
	var Mixin = "mixin";
	var Namespace = "namespace";
	var Partial = "partial";
	var Readonly = "readonly";
	var Required = "required";
	var Setlike = "setlike";
	var Setter = "setter";
	var Static = "static";
	var Stringifier = "stringifier";
	var Typedef = "typedef";
	var Unrestricted = "unrestricted";
}

private typedef Token = {
	var t:TokenKind;
	var pos:Position;
}

private enum TokenKind {
	TComment;

	TSquareBracketOpen;
	TSquareBracketClose;
	TBraceOpen;
	TBraceClose;
	TParenOpen;
	TParenClose;
	TLeftArrow;
	TRightArrow;
	TColon;
	TSemicolon;
	TComma;
	TEqual;
	TQuestion;
	TDotDotDot;
	TString(s:String);
	TNumber(s:String);
	TKeyword(k:Keyword);
	TIdent(s:String);
	TEof;
}
