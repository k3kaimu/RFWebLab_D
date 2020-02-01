module app;

import core.thread;
import core.time;

import std.algorithm;
import std.array;
import std.complex;
import std.conv;
import std.digest.md;
import std.getopt;
import std.meta;
import std.path;
import std.range;
import std.regex;
import std.stdio;
import std.zip;

import requests;

import serializer;

void main(string[] args)
{
    import std.file : read, write;

    if(args.length != 5 || (args[2] != "float" && args[2] != "double") ) {
        writeln("rfweblab_client <rms dBm> <float|double> <input_file_name> <output_file_name>");
        return;
    }

    double RMSIn = args[1].to!double;
    string type = args[2];
    string inputfilename = args[3];
    string outputfilename = args[4];

    RFWebLabRequest rq;
    static foreach(F; AliasSeq!(float, double)) {
        if(type == F.stringof)
            rq = makeRequestData(cast(Complex!F[])read(inputfilename), RMSIn);
    }

    assert(rq.Re_data);

    auto filename = requestToRFWebLab(rq);
    writeln(filename);

    auto rs = getResponseFromRFWebLab(filename);
    writeln(rs.DCmeas);
    writeln(rs.status);
    writeln(rs.RMS_out);
    writeln(rs.error_hanlde);

    static foreach(F; AliasSeq!(float, double)) {
        if(type == F.stringof) {
            auto res_cpx = zip(rs.b3_re, rs.b3_im).map!(a => Complex!F(a.tupleof)).array();
            write(outputfilename, cast(ubyte[])res_cpx);
        }
    }
}


struct RFWebLabRequest
{
    float Client_version;
    string OpMode;
    double PowerLevel;
    double SA_Samples;
    double[] Re_data;
    double[] Im_data;
}


struct DCmeasType { double Id, Vd, Ig, Vg; }


struct RFWebLabResponse
{
    double[] b3_re;
    double[] b3_im;
    DCmeasType DCmeas;
    double status;
    double RMS_out;
    int error_hanlde;   // 元々のAPIがタイポしてる．．．
}


RFWebLabRequest makeRequestData(F)(const Complex!F[] signal, double rms)
{
    RFWebLabRequest data;

    data.Client_version = 1.1;
    data.OpMode = "A5Z6UNud";
    data.PowerLevel = rms;
    data.SA_Samples = signal.length;
    data.Re_data = signal.map!"cast(double)a.re".array();
    data.Im_data = signal.map!"cast(double)a.im".array();

    return data;
}


// return file name like "output_\d+_\d+.dat"
string requestToRFWebLab(RFWebLabRequest data)
{
    auto app = appender!(ubyte[])();
    app.serialize(data);

    auto binary = matlabDigest(app.data) ~ app.data;

    // construct HTTP POST request
    MultipartForm form;
    form.add(formData("myFile", binary, ["filename": "dummy.dat", "Content-Type": "Content-Type: application/octet-stream"]));

    // send POST request and get response
    auto result = cast(const(char)[])postContent("http://dpdcompetition.com/rfweblab/matlab/upload.php", form).data;

    // get result filename
    return matchFirst(result, ctRegex!`output_\d+_\d+\.dat`)[0].dup;
}


//
RFWebLabResponse getResponseFromRFWebLab(string filename)
{
    immutable baseURL = "http://dpdcompetition.com/rfweblab/matlab/files/";

    auto zipfilename = filename.setExtension(".zip");
    auto checkfilename = filename.replace("output_", "ok_");

    // auto checkresp = getContent(baseURL ~ checkfilename).data;
    // writeln(cast(const(char)[])checkresp);
    while(1) {
        Thread.sleep(3.seconds);
        Request rq = Request();
        Response rs = rq.get(baseURL ~ checkfilename);
        if(rs.code != 404)
            break;
    }

    auto zipfile = getContent(baseURL ~ zipfilename).data;
    auto archive = new ZipArchive(cast(ubyte[])zipfile);
    assert(filename in archive.directory);

    auto member = archive.directory[filename];
    const(ubyte)[] data = archive.expand(member);

    RFWebLabResponse dst;
    deserialize(data, dst);
    return dst;
}


ubyte[16] matlabDigest(const(ubyte)[] binary)
{
    MD5 digest;
    digest.start();
    digest.put(cast(ubyte[])"uint8");

    ulong[3] dims = [2, binary.length, 1];
    digest.put(cast(ubyte[])dims);
    digest.put(binary);

    return digest.finish();
}
