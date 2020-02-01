module serializer;

// import std.algorithm;
import std.conv;
import std.meta;
import std.range;
import std.traits;


const(ubyte)[] toUbytes(E)(const E[] array)
{
    return (cast(const(ubyte)*)array.ptr)[0 .. array.length * E.sizeof];
}


ubyte[] toUbytes(T)(T value)
if(!isArray!T)
{
    const(ubyte)[] slice = (cast(ubyte*)&value)[0 .. T.sizeof];
    return slice.dup;
}


uint[2] getShape(T)(T data)
{
    uint[2] dst = [1, 1];

    static if(isNarrowString!T)
        dst[1] = cast(uint) data.length;
    else static if(isArray!T)
        dst[0] = cast(uint) data.length;

    return dst;
}


template classToByte(T)
{
    static if(isArray!T)
        enum byte classToByte = .classToByte!(ElementEncodingType!T);
    else
        enum byte classToByte = staticIndexOf!(Unqual!T, AliasSeq!(double, float, bool, char, byte, ubyte, short, ushort, int, uint, long, ulong));
}


void serialize(R, T)(ref R output, const T data)
if(isOutputRange!(R, ubyte) && is(T == struct) && __traits(isPOD, T))
{
    output.put(cast(ubyte) 255);
    output.put(cast(ubyte) data.tupleof.length);

    static foreach(string field; __traits(allMembers, T)) {
        output.put(field.length.to!uint.toUbytes);
        output.put(field.toUbytes);
    }

    output.put(cast(ubyte) 2);              // put ndims(data)
    output.put(data.getShape.toUbytes);     // put size of each dimension

    static foreach(string field; __traits(allMembers, T)) {
        .serialize(output, __traits(getMember, data, field));
    }
}


void serialize(R, T)(ref R output, const T data)
if(isOutputRange!(R, ubyte) && !is(T == struct))
{
    output.put(classToByte!T);
    output.put(cast(ubyte) 2);              // put ndims(data)
    output.put(data.getShape.toUbytes);     // put size of each dimension
    output.put(data.toUbytes);
}


T fromUbytes(T)(ref const(ubyte)[] binary)
if(!isArray!T)
{
    ubyte[T.sizeof] buf;
    buf[] = binary[0 .. T.sizeof];
    binary = binary[T.sizeof .. $];

    return *cast(T*)buf.ptr;
}


T fromUbytes(T)(ref const(ubyte)[] binary, size_t len)
if(isArray!T)
{
    alias E = ElementEncodingType!T;
    auto ret = (cast(E*)binary.ptr)[0 .. len].dup;
    binary = binary[len * E.sizeof .. $];

    return cast(T)ret;
}


void deserialize(T)(ref const(ubyte)[] binary, ref T data)
if(is(T == struct) && __traits(isPOD, T))
{
    assert(binary.fromUbytes!ubyte == 255);
    assert(binary.fromUbytes!ubyte == data.tupleof.length);

    string[] fieldNames;
    foreach(i; 0 .. data.tupleof.length) {
        size_t strlen = binary.fromUbytes!uint;
        fieldNames ~= binary.fromUbytes!string(strlen);
    }

    assert(binary.fromUbytes!ubyte == 2);
    assert(binary.fromUbytes!(uint[])(2) == [1, 1]);

    foreach(name; fieldNames) {
        Lswitch:
        switch(name) {
            static foreach(string field; __traits(allMembers, T)) {
                case field:
                    .deserialize(binary, __traits(getMember, data, field));
                    break Lswitch;
            }

                default:
                    assert(0);
        }
    }
}


void deserialize(T)(ref const(ubyte)[] binary, ref T data)
if(!is(T == struct))
{
    auto ty = binary.fromUbytes!ubyte;
    assert(ty == classToByte!T);
    assert(binary.fromUbytes!ubyte == 2);

    uint[] shape = binary.fromUbytes!(uint[])(2);
    size_t len = shape[0] * shape[1];

    static if(isArray!T)
        data = binary.fromUbytes!T(len);
    else
        data = binary.fromUbytes!T();
}
