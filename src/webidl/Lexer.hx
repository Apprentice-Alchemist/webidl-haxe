package webidl;

import webidl.Ast.Position;

class LexerError extends haxe.Exception {
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
	var pos:webidl.Ast.Position;
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

	static final ident_reg = ~/^[_-]?[A-Za-z][0-9A-Z_a-z-]*/m;
	static final integer_reg = ~/^-?([1-9][0-9]*|0[Xx][0-9A-Fa-f]+|0[0-7]*)/m;
	static final decimal_reg = ~/^-?(([0-9]+\.[0-9]*|[0-9]*\.[0-9]+)([Ee][+-]?[0-9]+)?|[0-9]+[Ee][+-]?[0-9]+)/m;

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
		if (input.substr(pos, s.length) == s) {
			pos += s.length;
			linepos += s.length;
			return true;
		}
		return false;
	}

	function readStringUntil(ec:Int) {
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

	function token():Token {
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
				if (decimal_reg.match(input.substr(pos - 1))) {
					var matched = decimal_reg.matched(0);
					pos += matched.length - 1;
					linepos += matched.length - 1;
					TDecimal(matched);
				} else if (integer_reg.match(input.substr(pos - 1))) {
					var matched = integer_reg.matched(0);
					pos += matched.length - 1;
					linepos += matched.length - 1;
					TInteger(matched);
				} else if (ident_reg.match(input.substr(pos - 1))) {
					var matched = ident_reg.matched(0);
					pos += matched.length - 1;
					linepos += matched.length - 1;
					Keyword.ALL_KEYWORDS.indexOf(cast matched) > -1 ? TKeyword(cast matched) : TIdent(matched);
				} else {
					throw new LexerError({
						file: filename,
						line: line,
						min: start,
						max: linepos
					}, "Invalid character : " + std.String.fromCharCode(c));
				}
		}
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
