package webidl;

typedef Pos = {
	var file:String;
	var line:Int;
	var min:Int;
	var max:Int;
}

typedef ExtendedAttributes = Array<ExtendedAttribute>;

typedef ExtendedAttribute = {
	var name:String;
	var kind:ExtendedAttributeKind;
}

enum ExtendedAttributeKind {
	ExtendedAttributeNoArg;
	ExtendedAttributeArgList(args:Array<Argument>);
	ExtendedAttributeNamedArgList(name:String, args:Array<Argument>);
	ExtendedAttributeIdent(ident:String);
	ExtendedAttributeIdentList(idents:Array<String>);
}

typedef Named = {
	var name:String;
}

typedef Annotated = {
	var attributes:ExtendedAttributes;
}

typedef InterfaceMember = Named & {
	var kind:InterfaceMemberKind;
}

enum InterfaceMemberKind {
	Const(type:CType, value:Constant);
	Attribute(type:CType, _static:Bool, readonly:Bool);
	Function(ret:CType, args:Array<Argument>, _static:Bool);
	Setlike(readonly:Bool, type:CType);
	Maplike(readonly:Bool, type:CType);
	Iterable(readonly:Bool, type:CType);
	Deleter;
	Setter;
	Getter;
}

typedef DictionaryMember = {
	var name:String;
	var optional:Bool;
	var type:CType;
	var ?value:Value;
}

typedef InterfaceType = {
	var name:String;
	var attributes:ExtendedAttributes;
	var members:Array<InterfaceMember>;
	var setlike:Bool;
	var settype:Null<CType>;
	var maptype:Null<CType>;
	var iterabletype:Null<CType>;
	var readonlysetlike:Bool;
	var maplike:Bool;
	var readonlymaplike:Bool;
	var iterable:Bool;
	var keyvalueiterable:Bool;
	// var mixin:Bool;
	var ?parent:String;
}

typedef NamespaceType = {
	var name:String;
	var members:Array<Definition>;
};

typedef DictionaryType = {
	var name:String;
	var attributes:ExtendedAttributes;
	var members:Array<DictionaryMember>;
	var ?parent:String;
}

typedef EnumType = {
	var name:String;
	var attributes:ExtendedAttributes;
	var values:Array<String>;
}

typedef TypedefType = {
	var name:String;
	var type:CType;
}

typedef CallbackType = Named &
	Annotated & {
	var ret:CType;
	var args:Array<Argument>;
}

enum Definition {
	Mixin(i:InterfaceType);
	Interface(i:InterfaceType);
	Namespace(n:NamespaceType);
	Dictionary(d:DictionaryType);
	Enum(e:EnumType);
	Callback(c:CallbackType);
	Typedef(t:TypedefType);
	Includes(what:String, included:String);
	Partial(d:Definition);
	InterfaceMember(i:InterfaceMember);
}

typedef Argument = {
	var name:String;
	var type:CType;
	var optional:Bool;
	var ?value:Value;
}

enum Value {
	String(s:String);
	EmptyDict;
	EmptyArray;
	Null;
	Const(c:Constant);
}

enum Constant {
	True;
	False;
	Integer(s:String);
	Decimal(s:String);
	MinusInfinity;
	Infinity;
	NaN;
}

enum CType {
	Rest(t:CType);

	Undefined;
	Boolean;
	Byte;
	Octet;
	Short;
	Bigint;
	Float;
	Double;
	UnsignedShort;
	UnsignedLong;
	UnsignedLongLong;
	UnrestrictedFloat;
	UnrestrictedDouble;
	Long;
	LongLong;
	ByteString;
	DOMString;
	USVString;
	Promise(t:CType);
	Record(s:CType, t:CType);
	WithAttributes(e:ExtendedAttributes, t:CType);
	Ident(s:String);
	Sequence(t:CType);
	Object;
	Symbol;
	Union(t:Array<CType>);
	Any;
	Null(t:CType);
	ArrayBuffer;
	DataView;
	Int8Array;
	Int16Array;
	Int32Array;
	Uint8Array;
	Uint16Array;
	Uint32Array;
	Uint8ClampedArray;
	BigInt64Array;
	BigUint64Array;
	Float32Array;
	Float64Array;
	FrozenArray(t:CType);
	ObservableArray(t:CType);
}
