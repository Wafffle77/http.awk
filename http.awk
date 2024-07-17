#!/usr/bin/awk -f

# Run with `socat tcp-listen:8080,reuseaddr,fork exec:'awk http.awk'`.
# or don't. I can't tell you what to do

BEGIN {
    RS = "\r\n";
    ORS = "\r\n";
    FS = " ";
}

# Constants
BEGIN {
    for(i=0;i<256;i++)ORD[sprintf("%c",i)]=i;
    reasons[100] = "Continue";
    reasons[101] = "Switching Protocols";
    reasons[200] = "OK";
    reasons[201] = "Created";
    reasons[202] = "Accepted";
    reasons[203] = "Non-Authoritative Information";
    reasons[204] = "No Content";
    reasons[205] = "Reset Content";
    reasons[206] = "Partial Content";
    reasons[300] = "Multiple Choices";
    reasons[301] = "Moved Permanently";
    reasons[302] = "Found";
    reasons[303] = "See Other";
    reasons[304] = "Not Modified";
    reasons[305] = "Use Proxy";
    reasons[307] = "Temporary Redirect";
    reasons[400] = "Bad Request";
    reasons[401] = "Unauthorized";
    reasons[402] = "Payment Required";
    reasons[403] = "Forbidden";
    reasons[404] = "Not Found";
    reasons[405] = "Method Not Allowed";
    reasons[406] = "Not Acceptable";
    reasons[407] = "Proxy Authentication Required";
    reasons[408] = "Request Time-out";
    reasons[409] = "Conflict";
    reasons[410] = "Gone";
    reasons[411] = "Length Required";
    reasons[412] = "Precondition Failed";
    reasons[413] = "Request Entity Too Large";
    reasons[414] = "Request-URI Too Large";
    reasons[415] = "Unsupported Media Type";
    reasons[416] = "Requested range not satisfiable";
    reasons[417] = "Expectation Failed";
    reasons[418] = "I'm a teapot";
    reasons[500] = "Internal Server Error";
    reasons[501] = "Not Implemented";
    reasons[502] = "Bad Gateway";
    reasons[503] = "Service Unavailable";
    reasons[504] = "Gateway Time-out";
    reasons[505] = "HTTP Version not supported";
    enc[":"] = "%3A";
    enc["\\/"] = "%2F";
    enc["\\?"] = "%3F";
    enc["#"] = "%23";
    enc["\\["] = "%5B";
    enc["\\]"] = "%5D";
    enc["@"] = "%40";
    enc["!"] = "%21";
    enc["\\$"] = "%24";
    enc["&"] = "%26";
    enc["\\'"] = "%27";
    enc["\\("] = "%28";
    enc["\\)"] = "%29";
    enc["\\*"] = "%2A";
    enc["\\+"] = "%2B";
    enc[","] = "%2C";
    enc[";"] = "%3B";
    enc["="] = "%3D";
    enc[" "] = "%20";
}

function toHex(msg,    ret) {
    for(i=1; i <= length(msg); i++)
        ret = ret sprintf("%02x", ORD[substr(msg, i, 1)]);
    return ret;
}

function fromHex(msg,     ret) {
    for(i=1; i < length(msg); i += 2)
        ret = ret sprintf("%c",strtonum("0x" substr(msg, i, 2)));
    return ret;
}

function encodeURL(url,      arr) {
    gsub("%", "%25", url);
    for(c in enc)
        gsub(c, enc[c], url);
    return url;
}

function encodeQuery(query,        ret) {
    for(parameter in query) {
        ret = ret "&" encodeURL(parameter) "=" encodeURL(query[parameter]);
    }
    return substr(ret, 2);
}

function decodeURL(url,      arr) {
    gsub("+", " ", url);
    while(match(url, /%([0-9A-Fa-f]{2})/, arr)) {
        gsub(arr[0], sprintf("%c", strtonum("0x" arr[1])), url);
    }
    return url;
}

function decodeQuery(query, ret,    arr, arr2) {
    split(query, arr, "&");
    for(i in arr) {
        split(arr[i], arr2, "=");
        ret[decodeURL(arr2[1])] = decodeURL(arr2[2]);
    }
}

function processRequest(ret,        oldFS, arr, i) {
    oldFS = FS;
    FS = " ";
    ret["method"]  = $1;
    ret["version"] = $3;
    
    split($2, arr, "?");
    ret["path"]    = arr[1];
    request["query"] = arr[2];
    decodeQuery(arr[2], arr);
    for(i in arr) {
        ret["query",i] = arr[i];
    }
    
    i = 0;
    FS = " *: *";
    getline;
    while(NF > 0 && i < 512) {
        ret["headers", $1] = $2;
        i++;
        getline;
    }

    FS = oldFS;
}

function sendResponse(response,     oldOFS, combined, header) {
    if(!response["headers", "Server"])
        response["headers", "Server"] = getVersion();
    
    if(!response["headers", "Content-Length"])
        response["headers", "Content-Length"] = length(response["content"]);
    
    oldOFS = OFS;
    OFS = " ";

    print("HTTP/1.1", response["status"], reasons[response["status"]]);

    OFS = ": ";
    for(combined in response) {
        split(combined, header, SUBSEP);
        if(header[1] == "headers")
            print(header[2], response["headers",header[2]]);
    }
    
    print("");

    printf("%s", response["content"]);

    OFS = oldOFS;
}

function readFile(path,            ret, line) {
    while((getline line < path) > 0)
        ret = ret "\n" line;
    close(path);
    return ret;
}

function getVersion(line, arr, ver) {
    ver = ARGV[0] " --version";
    ver | getline line;
    close(ver);
    split(line, arr, ",")
    return arr[1];
}

{
    processRequest(request);
    print(request["method"], request["path"], request["query"]) > "/dev/stderr";
}

request["method"] == "GET" {
    if(request["path"] ~ /\/$/) {
        response["content"] = readFile("www" request["path"] "index.html");
    } else if(request["path"] !~ /\.\./) {
        response["content"] = readFile("www" request["path"]);
    } else {
        response["status"]  = 418;
        response["content"] = "Please don't. It's rude.";
    }

    if(!response["status"] && length(response["content"]) > 0) {
        response["status"] = 200;
    } else {
        response["status"]  = 404;
        response["content"] = "File not found: " request["path"];
    }

    response["headers", "Content-Type"] = "text/html";

    sendResponse(response);
    exit(0);
}
