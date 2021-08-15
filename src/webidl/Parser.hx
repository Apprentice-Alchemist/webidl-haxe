package webidl;

import haxe.ds.GenericStack;
import webidl.Lexer;
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
		var tokens = Lexer.lex(input, file);
		sys.io.File.saveContent("dom.dump", tokens.map(t -> tokenToString(t.t)).join(" "));
		return try new Parser(tokens).parse() catch (e:ParserError) {
			Sys.println(e.print());
			null;
		}
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
		haxe.Log.trace("unexpected : " + t.t, pos);
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
				// trace([for (t in used_tokens) t.t].join(" "));
				throw new ParserError(current_token.pos, 'Unexpected ${tokenToString(_t)}, expected ${tokenToString(t)}');
			}
		}
	}

	function ident(?pos:haxe.PosInfos):String {
		return switch token() {
			case TIdent(s) | TKeyword(s):
				s;
			case _:
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
					case TIdent(s): ExtendedAttributeIdent(s);
					case TParenOpen:
						var l = [];
						do {
							l.push(ident());
						} while (match(TComma));
						consume(TParenClose);
						ExtendedAttributeIdentList(l);
					case var t:
						throw new ParserError(current_token.pos, "Did not expect this token.");
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
			case TIdent(s):
				for (t in CType.getConstructors())
					if (s == t)
						return CType.createByName(t);
				Ident(s);
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
						var settype = null;

						var maplike = false;
						var readonlymap = false;
						var maptype = null;

						var iterablelike = false;
						var iterabletype = null;
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
								if (!match(TSemicolon)) {
									var _static = !stringifier && match(TKeyword(Static));
									var readonly = match(TKeyword(Readonly));
									if (match(TKeyword(Setlike))) {
										setlike = true;
										readonlyset = readonly;
										consume(TLeftArrow);
										settype = parseType();
										consume(TRightArrow, TSemicolon);
									} else if (match(TKeyword(Maplike))) {
										maplike = true;
										readonlymap = readonly;
										consume(TLeftArrow);
										maptype = parseType();
										consume(TRightArrow, TSemicolon);
									} else if (match(TKeyword(Iterable))) {
										iterablelike = true;
										// readonlyset = readonly;
										consume(TLeftArrow);
										iterabletype = parseType();
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
										throw new ParserError(tokens.pop().pos, "Expected attribute");
									} else if (match(TKeyword(Getter))) {
										parseType();
										switch token() {
											case TIdent(s):
												consume(TParenOpen);
											case TParenOpen:
											case _: throw unexpected();
										}
										parseType();
										ident();
										consume(TParenClose, TSemicolon);
									} else if (match(TKeyword(Setter))) {
										parseType();
										switch token() {
											case TIdent(s):
												consume(TParenOpen);
											case TParenOpen:
											case _: throw unexpected();
										}
										parseType();
										ident();
										consume(TComma);
										parseType();
										ident();
										consume(TParenClose, TSemicolon);
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
						}
						var i = {
							name: name,
							parent: parent,
							members: members,
							attributes: attributes
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
						var defs = [
							while (!match(TBraceClose, TSemicolon)) {
								parseDefinition();
							}
						];
						Namespace({
							name: name,
							// partial: partial,
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
					case _:
						throw unexpected();
				}
			case TIdent(s) if (match(TKeyword(Includes))):
				var x = ident();
				consume(TSemicolon);
				Includes(x, s);
			case _:
				trace(current_token);
				throw unexpected();
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
