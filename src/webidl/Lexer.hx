package webidl;

import haxe.ds.GenericStack;
import webidl.Ast.Pos;

class LexerError extends haxe.Exception {
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

enum abstract Keyword(String) to String {
	public static final ALL_KEYWORDS = [
		Async, Attribute, Callback, Const, Constructor, Deleter, Dictionary, Enum, Getter, Includes, Inherit, Interface, Iterable, Maplike, Mixin, Namespace,
		Partial, Readonly, Required, Setlike, Setter, Static, Stringifier, Typedef, Unrestricted, Implements
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
	var Implements = "implements";
}

typedef Token = {
	var t:TokenKind;
	var pos:webidl.Ast.Pos;
}

enum TokenKind {
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
	TInteger(s:String);
	TDecimal(s:String);
	TKeyword(k:Keyword);
	TIdent(s:String);
	TEof;
}

class Lexer {
	public static function lex(input:String, filename:String) {
		return new Lexer(input, filename)._lex();
	}

	var pos:Int;
	var line:Int;
	var linepos:Int;

	var input:String;
	var filename:String;

	public function new(input:String, filename:String) {
		this.input = input;
		this.filename = filename;
		this.pos = 0;
		this.line = 1;
		this.linepos = 1;
	}

	var posStack:GenericStack<{pos:Int, line:Int, linepos:Int}> = new GenericStack();

	function save() {
		posStack.add({
			pos: pos,
			line: line,
			linepos: linepos
		});
	}

	function restore() {
		final state = posStack.pop();
		if (state != null) {
			pos = state.pos;
			line = state.line;
			linepos = state.linepos;
		}
	}

	inline function incpos() {
		linepos++;
		return pos++;
	}

	inline function incline() {
		line++;
		linepos = 1;
		return pos++;
	}

	inline function next():Int
		return cast input.charCodeAt(incpos());

	inline function current():Int
		return cast input.charCodeAt(pos);

	inline function peek():Int
		return cast input.charCodeAt(pos + 1);

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
		for (i in 0...s.length) {
			if (input.charCodeAt(pos + i) != s.charCodeAt(i))
				return false;
		}
		pos += s.length;
		linepos += s.length;
		return true;
	}

	inline function readStringUntil(ec:Int) {
		var s = new StringBuf();
		while (true) {
			var c = next();
			if (c == null)
				throw "eof";
			if (c == ec)
				break;
			else {
				s.addChar(c);
			}
		}
		return s.toString();
	}

	inline function isAlpha(c:Int) {
		return c >= "a".code && c <= "z".code || c >= "A".code && c <= "Z".code;
	}

	inline function isNum(c:Int) {
		return c >= "0".code && c <= "9".code;
	}

	inline function isAlphaNum(c:Int) {
		return isAlpha(c) || isNum(c);
	}

	inline function isAlphaDash(c:Int) {
		return isAlpha(c) || c == "_".code || c == "-".code;
	}

	inline function isAlphaNumDash(c:Int) {
		return isAlphaNum(c) || c == "_".code || c == "-".code;
	}

	function token():Token {
		eatWhitespace();
		var start = linepos;
		function t(t:TokenKind):Token {
			return {
				t: t,
				pos: {
					file: filename,
					line: line,
					min: start,
					max: linepos
				}
			}
		}
		var c = next();
		return t(switch c {
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
			case "/".code if (match("/")):
				while (next() != "\n".code) {}
				line++;
				linepos = 0;
				return token();
			case "/".code if (match("*")):
				while (!match("*/")) {
					incpos();
				}
				return token();
			case ".".code if (match("..")): TDotDotDot;
			case "-".code if (match("Infinity")): TIdent("-Infinity");
			case null: TEof;
			case _:
				this.pos -= 1;
				this.linepos -= 1;
				final pos = this.pos;
				final line = this.line;
				final linepos = this.linepos;

				inline function _restore() {
					this.pos = pos;
					this.line = line;
					this.linepos = linepos;
				}

				~/^-?(([0-9]+\.[0-9]*|[0-9]*\.[0-9]+)([Ee][+-]?[0-9]+)?|[0-9]+[Ee][+-]?[0-9]+)/m;
				{
					final hasMin = match("-");
					// ([Ee][+-]?[0-9]+)
					function parseE() {
						save();
						if (current() == "E".code || current() == "e".code) {
							next();
							if (current() == "+".code || current() == "-".code) {
								next();
							}
							if (isNum(current())) {
								next();
								while (isNum(current()))
									next();
								return true;
							}
						}
						restore();
						return false;
					}
					// ([0-9]+\.[0-9]*|[0-9]*\.[0-9]+)
					function branch1() {
						save();
						if (isNum(current())) {
							next();
							while (isNum(current()))
								next();
							if (match(".")) {
								while (isNum(current()))
									next();
								parseE();
								return true;
							}
						}
						restore();
						while (isNum(current()))
							next();
						if (match(".")) {
							if (isNum(next())) {
								while (isNum(current()))
									next();
							}
							parseE();
							return true;
						}
						return false;
					}
					// [0-9]+[Ee][+-]?[0-9]+
					function branch2() {
						save();
						if (isNum(current())) {
							next();
							while (isNum(current()))
								next();
						}
						if (parseE()) {
							return true;
						}
						restore();
						return false;
					}
					if (branch1() || branch2()) {
						return t(TDecimal(input.substring(pos, this.pos)));
					}
				}
				_restore();
				~/^-?([1-9][0-9]*|0[Xx][0-9A-Fa-f]+|0[0-7]*)/m;
				{
					save();
					final hasMin = match("-");
					function parseDecimal() {
						save();
						final n = next();
						if (n >= "1".code && n <= "9".code) {
							while (isNum(current()))
								next();
							return true;
						}
						restore();
						return false;
					}
					function parseHex() {
						save();
						if (next() == "0".code) {
							final n = next();
							if (n == "X".code || n == "x".code) {
								inline function isHex(c:Int) {
									return isNum(c) || c >= 'A'.code && c <= "F".code || c >= 'a'.code && c <= 'f'.code;
								}
								if (isHex(next())) {
									while (isHex(current()))
										next();
									return true;
								}
							}
						}
						restore();
						return false;
					}
					function parseOctal() {
						save();
						if (next() == "0".code) {
							if (isNum(current())) {
								next();
								while (isNum(current()))
									next();
							}
							return true;
						}
						restore();
						return false;
					}
					if (parseDecimal() || parseHex() || parseOctal()) {
						// let's forget about octal for now
						return t(TInteger(input.substring(pos, this.pos)));
					}
					restore();
				}
				_restore();
				~/^[_-]?[A-Za-z][0-9A-Z_a-z-]*/m;
				if (isAlphaDash(next())) {
					while (isAlphaNumDash(current()))
						next();
					final ident = input.substring(pos, this.pos);
					if (Keyword.ALL_KEYWORDS.indexOf(cast ident) > -1) {
						return t(TKeyword(cast ident));
					} else {
						return t(TIdent(ident));
					}
				}
				_restore();
				throw new LexerError({
					file: filename,
					line: line,
					min: start,
					max: linepos
				}, "Invalid character : " + std.String.fromCharCode(c));
		});
	}

	public function _lex():Array<Token> {
		var a = new Array();
		while (true) {
			var t = token();
			a.push(t);
			if (t.t == TEof)
				break;
		}
		return a;
	}
}
