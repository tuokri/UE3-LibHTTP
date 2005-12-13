/*******************************************************************************
    HttpSock                                                                    <br />
    Base of [[LibHTTP]] this implements the main network methods for connecting
    to a webserver and retreiving data from it. Binary data is not supported.   <br />

    Dcoumentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2003-2005 Michiel "El Muerte" Hendriks                            <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense                <br />

    <!-- $Id: HttpSock.uc,v 1.45 2005/12/13 11:36:08 elmuerte Exp $ -->
*******************************************************************************/

class HttpSock extends Engine.Info
    config
    dependson(HttpUtil);

/** LibHTTP version number */
const VERSION = 401;
/**
    If you make a custom build of this package, or subclass this class then
    please change the following constant to countain your "extention" name. This
    will be used in the UserAgent string. (Change it in the defaultproperties)
*/
var const string EXTENTION;

/** the output buffer size */
const BUFFERSIZE = 2048;

/* HTTP request commands */
const HTTP_CONNECT  = "CONNECT";
const HTTP_DELETE   = "DELETE";
const HTTP_GET      = "GET";
const HTTP_HEAD     = "HEAD";
const HTTP_OPTIONS  = "OPTIONS";
const HTTP_POST     = "POST";
const HTTP_PUT      = "PUT";
const HTTP_TRACE    = "TRACE";

/** constant CR LF */
var protected string CRLF;

/** The HTTP version to use. Either 1.0 or 1.1 are supported. */
var protected string HTTPVER;

////////////////////////////////////////////////////////////////////////////////
//
//  Configuration variables
//  The "Proxy" variables are reserved for end-user configuration
//  The other config options should only be used as config option if you create
//  a subclass of HttpSock.
//
////////////////////////////////////////////////////////////////////////////////

/** the URL struct for the current request */
var(URL) HttpUtil.xURL CurrentURL;
/** the local port, leave zero to use a random port (adviced) */
var(URL) int iLocalPort;
/** the default value for the Accept header, we only support "text / *" */
var(URL) string DefaultAccept;

/**
    Possible authentication methods, Basic used Base64 encoding to encode the
    username and password. Digest is more secure.
*/
enum EAuthMethod
{
    AM_None,
    AM_Unknown,
    AM_Basic,
    AM_Digest,
};
/** Authentication method to use when <code>sUsername</code> is set. This will
    automatically be set when a <code>WWW-Authenticate</code> header is received */
var(Authentication) EAuthMethod AuthMethod;
/** If username and password have been set automatically retry the request to
    authenticate. Note: this can only be done in a second try because the
    authentication method is required. */
var(Authentication) bool bAutoAuthenticate;
/** authentication information */
var(Authentication) array<GameInfo.KeyValuePair> AuthInfo;

/**
    log verbosity, you probably want to leave this 0. check the [[HttpUtil]]
    class for various log levels.
*/
var(Options) config int iVerbose;
/** when set to false it won't follow redirects */
var(Options) bool bFollowRedirect;
/**
    responding to HTTP redirect headers is RFC compliant, otherwise it will
    behave much like some other HTTP clients behave. This means that in case
    of a 301/302 it will set the request method from POST to GET. This is not
    the way it should happen according to the standard.
*/
var(Options) bool bRfcCompliantRedirect;
/** Maximum redirections to follow */
var(Options) config int iMaxRedir;
/** Send cookie data when available, defaults to true */
var(Options) config bool bSendCookies;
/** Process incoming cookies, defaults to true */
var(Options) config bool bProcCookies;
/**
    connection timeout, if the connection couldn't be established within this
    time limit it will abort the connection and call <code>OnTimeout()</code>
*/
var(Options) config float fConnectTimout;

/**
    Use a proxy server, this is (and the other proxy settins) a client setting.
    It's meant for clients to be set when they need to use a proxy.
*/
var(Proxy) globalconfig bool bUseProxy;
/** The hostname of the proxy */
var(Proxy) globalconfig string sProxyHost;
/** The proxy port */
var(Proxy) globalconfig int iProxyPort;
/** proxy authentication information */
var(Proxy) globalconfig string sProxyUser, sProxyPass;
/** Authentication method to use when <code>sUsername</code> is set. This will
    automatically be set when a <code>Proxy-Authorisation</code> header is received */
var(Proxy) EAuthMethod ProxyAuthMethod;
/** authentication information */
var(Proxy) array<GameInfo.KeyValuePair> ProxyAuthInfo;

/** will be set to true in case of a ... */
var protected bool bTempProxyOverride;

/**
    Method used to download the data. <br />
    <code>TM_Fast</code> will try to read as much as possible in a single tick,
    this will have an impact on the game performance during the download. Only
    use this mode when it's time critical. Use the variables
    <code>iMaxBytesPerTick</code> and <code>iMaxIterationsPerTick</code> to
    tweak this transfer mode.
*/
enum ETransferMode
{
    TM_Normal,
    TM_Fast,
};
/** Transfer mode to use during downloads */
var(XferMode) config ETransferMode TransferMode;
/** maximum number of bytes to download in a single tick */
var(XferMode) config int iMaxBytesPerTick;
/**
    Maximum iterations per tick in fast transfer mode. This defines the number
    of download retries (when nothing was received) the code may perform within
    a single tick. Because the data pending variable is only updated each tick
    it will remain true until the transfer function returns even tho there is no
    data pending.
*/
var(XferMode) config int iMaxIterationsPerTick;

////////////////////////////////////////////////////////////////////////////////
//
//   runtime variables
//
////////////////////////////////////////////////////////////////////////////////

/** utility class, used to speed up lookups (optimization) */
var protected HttpUtil Utils;
/** cache object with hostname resolves */
var protected HttpResolveCache ResolveCache;

/** the request method */
var string RequestMethod;
/** the request headers */
var array<string> RequestHeaders;
/** the request data */
var array<string> RequestData;

/** the return headers */
var array<string> ReturnHeaders;
/** the return data */
var array<string> ReturnData;
/** The last returned HTTP status code */
var int LastStatus;

/** Cookie class to use (if it has not been set) */
var class<HttpCookies> HttpCookieClass;
/** the cookie data instance */
var HTTPCookies Cookies;

struct RequestHistoryEntry
{
    /** method used in the request */
    var string Method;
    /** server hostname */
    var deprecated string Hostname;
    /** location, can include GET data */
    var deprecated string Location;
    /** the request URL*/
    var HttpUtil.xURL URL;
    /** the HTTP response code received */
    var int HTTPresponse;
};
/** history with requests for a single request, will contain more then one entry
    when redirections are followed */
var array<RequestHistoryEntry> RequestHistory;

/** duration of the last request */
var float RequestDuration;
/**
    start of the request, will be set after the connection was opened and before
    the actual request will be send
*/
var protected float StartRequestTime;

/** the link class to use */
var protected class<HttpLink> HttpLinkClass;
/** handle to the HttpLink */
var protected HttpLink HttpLink;
/** i/o buffers */
var protected string inBuffer, outBuffer;
/** true if headers are being processed */
var protected bool procHeader;

/** local link address */
var protected InternetLink.IpAddr LocalLink;
/** the port we are connected to */
var protected int BoundPort;

/** true if a redirection should be followed */
var protected bool FollowingRedir;
/** current number of redirections */
var protected int CurRedir;

/** true if an authentication retry should happen */
var protected bool bAuthTrap;

/** Base64 encoding lookup table */
var protected array<string> authBasicLookup;

/** Timezone Offset, dynamically calculated from the server's time */
var protected int TZoffset;

/** Multipart boundary string, used to split fields */
var protected string MultiPartBoundary;

/** bytes left in the chunk */
var protected int chunkedCounter;
/** true if the data is chunked (e.g. Transfer-Encoding: chunked )  */
var protected bool bIsChunked;
/** true in case of a connection timeout */
var protected bool bTimeout;

/** temporary proxy configuration */
var protected HttpUtil.xURL TempProxy;
/** if true use the TempProxy */
var protected bool bUseTempProxy;


enum HTTPState
{
    HTTPState_Resolving,
    HTTPState_Connecting,
    HTTPState_SendingRequest,
    HTTPState_WaitingForResponse,
    HTTPState_ReceivingData,
    HTTPState_Closed,
};
/** The current state of the socket */
var HTTPState curState;

/** the hostname being resolved, used to add to the resolve cache */
var protected string ResolveHostname;

////////////////////////////////////////////////////////////////////////////////
//
//   Delegates
//
////////////////////////////////////////////////////////////////////////////////

/**
    Will be called when the return code has been received; This is the first
    function called after the request has been send.
*/
delegate OnReturnCode(HttpSock Sender, int ReturnCode, string ReturnMessage, string HttpVer);

/**
    Will be called in case of an internal error.
*/
delegate OnError(HttpSock Sender, string ErrorMessage, optional string Param1, optional string Param2);

/**
    Will be called when the host name is resolved. <br />
    Return true to continue, or false to abort.
*/
delegate bool OnResolved(HttpSock Sender, string hostname, InternetLink.IpAddr Addr)
{
    return true;
}

/** Called when the resolved failed, hostname is the hostname that could not be resolved */
delegate OnResolveFailed(HttpSock Sender, string hostname);

/**
    called when the connection has timed out (e.g. open() failed after a set time)
*/
delegate OnConnectionTimeout(HttpSock Sender);

/**
    Will be called when the operation was completed successfully. <br />
    It won't be called when an time out occured.
*/
delegate OnComplete(HttpSock Sender);

/**
    Called before the connection is established.
*/
delegate OnPreConnect(HttpSock Sender);

/**
    Called when Open() fails
*/
delegate OnConnectError(HttpSock Sender);

/**
    This delegate will be send right before the headers are send to the
    webserver. If you want to change the headers you should do it here. <br />
    Warning: becarefull not to change or unset automatically generated headers
    that are important for this request (like authentication or request body
    headers)
*/
delegate OnSendRequestHeaders(HttpSock Sender);

/**
    Will be called when the request body has to be send. Do note that you are
    required to set the <code>Content-Length</code> header to the total size of
    the content being send. If you use this delegate to send the request body
    manually you will have to set the Content-Length header yourself.
*/
delegate OnRequestBody(HttpSock Sender);

/**
    Will be called for every response line received (only the body). Return
    false to stop the default behavior of storing the response body. Use this
    delegate if you need to have live updates of the content and can not wait
    until the request is complete.
*/
delegate bool OnResponseBody(HttpSock Sender, string line)
{
    return true;
}

/**
    Called before the redirection is followed, return false to prevernt following
    the redirection
*/
delegate bool OnFollowRedirect(HttpSock Sender, HttpUtil.xURL NewLocation)
{
    return true;
}

/**
    Will be called when authorization is required for the current location. <br />
    This will be called directly after receiving the WWW-Authenticate header. So
    it's best not to stall this call. It's just a notification.
*/
delegate OnRequireAuthorization(HttpSock Sender, EAuthMethod method, array<GameInfo.KeyValuePair> info);

/**
    Will be called when authorization is required for the current proxy. <br />
    This will be called directly after receiving the Proxy-Authenticate header.
    So it's best not to stall this call. It's just a notification.
*/
delegate OnRequireProxyAuthorization(HttpSock Sender, EAuthMethod method, array<GameInfo.KeyValuePair> info);

////////////////////////////////////////////////////////////////////////////////
//
//   Public functions
//
////////////////////////////////////////////////////////////////////////////////

/**
    This function will clear the previous request data. You may want to use this
    when you do a new request with the same socket. Previous set headers won't
    be unset automatically.
*/
function ClearRequestData(optional bool bDontClearAuth)
{
    RequestData.length = 0;
    RequestHeaders.Length = 0;
    if (!bDontClearAuth)
    {
        AuthMethod = AM_None;
        AuthInfo.Length = 0;
        CurrentURL.username = "";
        CurrentURL.password = "";
        RemoveHeader("Authorization");
    }
}

/**
    This will perform a simple HTTP GET request. This will be the most commonly
    used function to retrieve a document from a webserver. The location is just
    like the location you would use in your webbrowser.
*/
function bool get(string location)
{
    return HttpRequest(location, HTTP_GET);
}

/**
    This will perform a simple HTTP POST request. If the PostData is not empty
    it will overwrite the current post data and set the content type to
    <code>application/x-www-form-urlencoded</code>.
*/
function bool post(string location, optional string PostData)
{
    if (PostData != "")
    {
        RequestData.length = 0;
        RequestData[0] = PostData;
        AddHeader("Content-Type", "application/x-www-form-urlencoded");
    }
    return HttpRequest(location, HTTP_POST);
}

/**
    Perform a HTTP POST request using an array containing the postdata.
    if the array length > 0 it will overwrite the current post data.
    It will send the post data AS IS and doesn't set the content-type. <br />
    You might want to use the <code>post();</code> function together with
    <code>setFormData();</code>, that method is easier to use.
*/
function bool postex(string location, optional array<string> PostData)
{
    if (PostData.length > 0) RequestData = PostData;
    return HttpRequest(location, HTTP_POST);
}

/**
    Add form data (used for <code>multipart/form-data</code> instead of
    <code>application/x-www-form-urlencoded</code>). This method makes it easier
    to add form-data. It doesn't clear the previous data, it will just append it.
    Form Data gives you more control over the actual data send. Also you don't
    have to escape the data. <br />
    It will also force the content type to <code>multipart/form-data</code>.
*/
function bool setFormDataEx(string field, array<string> data, optional string contentType, optional string contentEncoding)
{
    local int n, i, size;
    size = DataSize(data);
    if (size == 0) return false;
    if (MultiPartBoundary == "") MultiPartBoundary = randString(, "--==_NextPart.");
    AddHeader("Content-Type", "multipart/form-data; boundary=\""$MultiPartBoundary$"\"");
    n = RequestData.length;
    if (n > 0) n--; // remove previous end
    RequestData[n++] = "--"$MultiPartBoundary;
    RequestData[n++] = "Content-Disposition: form-data; name="$field;
    if (contentType != "") RequestData[n++] = "Content-Type:"@contentType;
    if (contentEncoding != "") RequestData[n++] = "Content-Encoding:"@contentEncoding;
    RequestData[n++] = "";
    for (i = 0; i < data.length; i++)
    {
        RequestData[n++] = data[i];
    }
    RequestData[n++] = "--"$MultiPartBoundary$"--"; // add "end"
    return true;
}

/**
    Simple form of <code>setFormDataEx</code> when the data is only one line
*/
function bool setFormData(string field, coerce string data, optional string contentType, optional string contentEncoding)
{
    local array<string> adata;
    adata[0] = data;
    return setFormDataEx(field, adata, contentType, contentEncoding);
}

/**
    This will clear the POST data. Use this before calling <code>setFormData</code>
*/
function bool clearFormData()
{
    MultiPartBoundary = "";
    RequestData.length = 0;
    return (RequestData.length == 0);
}

/**
    perform a HTTP HEAD request. This will only return the headers. Use this this
    if you only want to check the file info on the server and not the whole body.
*/
function bool head(string location)
{
    return HttpRequest(location, HTTP_HEAD);
}

/**
    perform a HTTP TRACE request. This will simply cause the webserver to return
    the request it received. It's only usefull for debugging.
*/
function bool httrace(string location)
{
    return HttpRequest(location, HTTP_TRACE);
}

/**
    Add a header, case insensitive. Set bNoReplace to false to not overwrite the
    old header. Returns true when the header has been set.
*/
function bool AddHeader(string hname, coerce string value, optional bool bNoReplace)
{
    local int i;
    for (i = RequestHeaders.length-1; i >= 0; i--)
    {
        if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
        {
            if (bNoReplace) return false;
            RequestHeaders.remove(i, 1);
            break;
        }
    }
    if (value == "") return false;
    RequestHeaders[RequestHeaders.length] = hname$":"@value;
    return true;
}

/**
    Remove a header, case insensitive. Returns true when the header is deleted
*/
function bool RemoveHeader(string hname)
{
    local int i;
    for (i = 0; i < RequestHeaders.length; i++)
    {
        if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
        {
            RequestHeaders.remove(i, 1);
            return true;
        }
    }
    return false;
}

/**
    Returns the value of the requested header, or default if not found
*/
function string GetRequestHeader(string hname, optional coerce string def)
{
    local int i, j;
    for (i = 0; i < RequestHeaders.length; i++)
    {
        j = InStr(RequestHeaders[i], ":");
        if (Left(RequestHeaders[i], j) ~= hname)
        {
            return Utils.trim(Mid(RequestHeaders[i], j+1));
        }
    }
    return def;
}

/**
    Returns the value of the returned header, or default if not found
*/
function string GetReturnHeader(string hname, optional coerce string def)
{
    local int i, j;
    for (i = 0; i < ReturnHeaders.length; i++)
    {
        j = InStr(ReturnHeaders[i], ":");
        if (Left(ReturnHeaders[i], j) ~= hname)
        {
            return Utils.trim(Mid(ReturnHeaders[i], j+1));
        }
    }
    return def;
}

/**
    Abort the current request, if possible
*/
function bool Abort()
{
    if (HttpLink == none) return true;
    switch (curState)
    {
        case HTTPState_Connecting: CloseSocket(); return HttpLink == none;
        case HTTPState_ReceivingData: if (HttpLink.IsConnected()) return HttpLink.Close();
    }
    return false;
}

/** Set the HTTP version, if empty the default will be used.
    Returns true when the version has been updated */
function bool setHTTPversion(optional string newver)
{
    if (newver == "")
    {
        HTTPVER = default.HTTPVER;
        return true;
    }
    else if ((newver ~= "1.0") || (newver ~= "1.1"))
    {
        HTTPVER = newver;
        return true;
    }
    return false;
}

/** return thr current HTTP version setting */
function string getHTTPversion()
{
    return HTTPVER;
}

/** return if the authentication method is supported */
static function bool IsAuthMethodSupported(EAuthMethod method)
{
    if (method == AM_Basic) return true;
    else if (method == AM_Digest) return true;
    else if (method == AM_None) return true;
    return false;
}

/** string to EAuthMethod */
static function EAuthMethod StrToAuthMethod(coerce string method)
{
    if (method ~= "basic") return AM_Basic;
    if (method ~= "digest") return AM_Digest;
    return AM_Unknown;
}

/**
    Returns the current timestamp. Warning this is not a valid UNIX timestamp
    because the timezone is unknown (e.g. timestamps are always GMT)
*/
function int now()
{
    return Utils.timestamp(Level.Year, Level.Month, Level.Day, Level.Hour, Level.Minute, Level.Second);
}

/**
    Generates a random string. The size defaults to 16. Prefix isn't included
    with the size;
*/
static function string randString(optional int size, optional coerce string prefix)
{
    local string str;
    local int i;
    if (size == 0) size = 16;
    i = size;
    frand(); //seed
    while (i > 0)
    {
        str = str$class'HttpUtil'.static.DecToHex(MaxInt*frand(), 4);
        i -= 4;
    }
    return prefix$Left(str, size);
}

/**
    Returns the value of a <code>KeyValuePair</code>
*/
static function string GetValue(string key, array<GameInfo.KeyValuePair> Info, optional coerce string def)
{
    local int i;
    for (i = 0; i < info.length; i++)
    {
        if (info[i].key ~= key) return info[i].value;
    }
    return def;
}

/** Returns the useragent string we use */
function string UserAgent()
{
    local string res;
    res = "LibHTTP/"$VERSION$" (UnrealEngine2; build "@Level.EngineVersion$"; http://wiki.beyondunreal.com/wiki/LibHTTP ";
    if (EXTENTION != "") res = res$"; "$EXTENTION;
    res = res$")";
    return res;
}

/**
    Return the actual data size of a string array, it appends sizeof(CRLF) for
    each line. This is used for sending the RequestData.
*/
function int DataSize(array<string> data)
{
    local int i, res, crlflen;
    res = 0;
    crlflen = Len(CRLF);
    for (i = 0; i < data.length; i++)
    {
        res += Len(data[i])+crlflen;
    }
    return res;
}

/**
    Return the timezone offset
*/
function int getTZoffset()
{
    return TZoffset;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Internal functions
//
////////////////////////////////////////////////////////////////////////////////

/** initialize some variables */
event PreBeginPlay()
{
    super.PreBeginPlay();
    foreach AllObjects(class'HttpUtil', Utils) break;
    if (Utils == none) Utils = new(Level) class'HttpUtil';
    foreach AllObjects(class'HttpResolveCache', ResolveCache) break;
    if (ResolveCache == none)
    {
        Logf("Creating resolve cache object", Utils.LOGINFO);
        ResolveCache = new(Level) class'HttpResolveCache';
    }
}

/** clean up as much as possible */
event Destroyed()
{
    Utils = none;
    ResolveCache = none;
    super.Destroyed();
}

/**
    Start the HTTP request. Location can be a fully qualified url, or just the
    location on the configured server. <br />
    This is an internal function called by the <code>get()</code>,
    <code>head()</code> and <code>post()</code> functions. If you want to support
    additional HTTP requests you should subclass this class.
*/
protected function bool HttpRequest(string location, string Method)
{
    if (curState != HTTPState_Closed)
    {
        Logf("HttpSock not closed", Utils.LOGERR, GetEnum(enum'HTTPState', curState));
        return false;
    }
    RequestHistory.length = 0;
    RequestMethod = Caps(Method);
    if (!IsSupportedMethod())
    {
        Logf("Unsupported method", Utils.LOGERR, RequestMethod);
        return false;
    }

    CurrentURL.hash = "";
    CurrentURL.hostname = "";
    CurrentURL.location = "";
    CurrentURL.port = -1;
    CurrentURL.protocol = "";
    CurrentURL.query = "";
    if (!Utils.parseUrl(location, CurrentURL))
    {
        Logf("Unable to parse request URL", Utils.LOGERR);
        return false;
    }
    //Logf("Parsed URL", Utils.LOGINFO, string(CurrentURL));

    if (CurrentURL.protocol ~= "https")
    {
        Logf("Secure HTTP connections (https://) are not supported", Utils.LOGERR);
        return false;
    }
    if (CurrentURL.protocol != "http")
    {
        Logf("Only HTTP requests are supported", Utils.LOGERR);
        return false;
    }
    // Add default headers
    AddHeader("Host", CurrentURL.hostname);
    AddHeader("User-Agent", UserAgent());
    AddHeader("Connection", "close");
    AddHeader("Accept", DefaultAccept);

    if ((AuthMethod != AM_None) && IsAuthMethodSupported(AuthMethod) && (CurrentURL.username != ""))
    {
        AddHeader("Authorization", genAuthorization(AuthMethod, CurrentURL.username, CurrentURL.password, AuthInfo));
    }
    if ((Method ~= HTTP_POST) && (CurrentURL.query != ""))
    {
        if (GetRequestHeader("Content-Type", "application/x-www-form-urlencoded") ~= "application/x-www-form-urlencoded")
        {
            if (Len(RequestData[0]) > 0) RequestData[0] = RequestData[0]$"&";
            RequestData[0] = RequestData[0]$CurrentURL.query;
            AddHeader("Content-Type", "application/x-www-form-urlencoded"); // make sure it's set
        }
        else {
            Logf("POST data collision, data on URL left in tact", Utils.LOGWARN);
        }
    }
    bUseTempProxy = false;
    CurRedir = 0;
    CRLF = Chr(13)$Chr(10);
    if (bProcCookies || bSendCookies)
    {
        if (Cookies == none) Cookies = new HttpCookieClass;
    }
    return OpenConnection();
}

/** Returns true when the request method is supported */
protected function bool IsSupportedMethod()
{
    if (RequestMethod ~= HTTP_GET) return true;
    else if (RequestMethod ~= HTTP_HEAD) return true;
    else if (RequestMethod ~= HTTP_POST) return true;
    else if (RequestMethod ~= HTTP_TRACE) return true;
    return false;
}

/** manage logging */
function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
    if (level == Utils.LOGERR) OnError(self, Message, Param1, Param2);
    if (level <= iVerbose)
    {
        if (Tag != '') Utils.Logf(Tag, Message, Level, Param1, Param2);
        else Utils.Logf(Name, Message, Level, Param1, Param2);
    }
}

/** start the download */
protected function bool OpenConnection()
{
    local int i;
    i = RequestHistory.Length;
    RequestHistory.Length = i+1;
    RequestHistory[i].URL = CurrentURL;
    RequestHistory[i].Method = RequestMethod;
    RequestHistory[i].HTTPresponse = 0; // none yet

    if (!CreateSocket()) return false;

    if (bUseTempProxy)
    {
        if ((TempProxy.port <= 0) || (TempProxy.port >= 65536))
        {
            Logf("Changing temp proxy port to default (80)", Utils.LOGWARN, TempProxy.port);
            TempProxy.port = 80;
        }
        AddHeader("Proxy-Connection", "close");
        if (!CachedResolve(TempProxy.hostname))
        {
            curState = HTTPState_Resolving;
            ResolveHostname = TempProxy.hostname;
            HttpLink.Resolve(TempProxy.hostname);
        }
    }
    else if (bUseProxy)
    {
        if (sProxyHost == "")
        {
            Logf("No remote hostname", Utils.LOGERR);
            return false;
        }
        if ((iProxyPort <= 0) || (iProxyPort >= 65536))
        {
            Logf("Changing proxy port to default (80)", Utils.LOGWARN, iProxyPort);
            iProxyPort = 80;
        }
        if ((ProxyAuthMethod != AM_Unknown) && (ProxyAuthMethod != AM_None))
        {
            AddHeader("Proxy-Authorization", genAuthorization(ProxyAuthMethod, sProxyUser, sProxyPass, ProxyAuthInfo));
        }
        AddHeader("Proxy-Connection", "close");
        if (!CachedResolve(sProxyHost))
        {
            curState = HTTPState_Resolving;
            ResolveHostname = sProxyHost;
            HttpLink.Resolve(sProxyHost);
        }
    }
    else {
        if (!CachedResolve(CurrentURL.hostname))
        {
            curState = HTTPState_Resolving;
            ResolveHostname = CurrentURL.hostname;
            HttpLink.Resolve(ResolveHostname);
        }
    }
    return true;
}

/** lookup a chached resolve and connect if found */
protected function bool CachedResolve(coerce string hostname, optional bool bDontConnect)
{
    local InternetLink.IpAddr Addr;
    if (ResolveCache.ResolveAddress(hostname, Addr))
    {
       Logf("Resolve cache hit", Utils.LOGINFO, hostname, HttpLink.IpAddrToString(Addr));
       ResolveHostname = hostname;
       if (!bDontConnect) InternalResolved(Addr, true);
       return true;
    }
    return false;
}

/** hostname has been resolved */
function InternalResolved( InternetLink.IpAddr Addr , optional bool bDontCache)
{
    Logf("Host resolved succesfully", Utils.LOGINFO, ResolveHostname);
    if (!bDontCache) ResolveCache.AddCacheEntry(ResolveHostname, Addr);
    LocalLink.Addr = Addr.Addr;
    if (bUseTempProxy) LocalLink.Port = TempProxy.port;
    else if (bUseProxy) LocalLink.Port = iProxyPort;
    else {
        if (CurrentURL.port != -1) LocalLink.Port = CurrentURL.port;
        else LocalLink.Port = Utils.getPortByProtocol(CurrentURL.protocol);
    }
    if (!OnResolved(self, ResolveHostname, Addr))
    {
        Logf("Request aborted", Utils.LOGWARN, "OnResolved() == false");
        curState = HTTPState_Closed;
        return;
    }
    if (iLocalPort > 0)
    {
        BoundPort = HttpLink.BindPort(iLocalPort, true);
        if (BoundPort != iLocalPort) Logf("Could not bind preference port", Utils.LOGWARN, iLocalPort, BoundPort);
    }
    else BoundPort = HttpLink.BindPort();

    if (BoundPort > 0) Logf("Local port succesfully bound", Utils.LOGINFO, BoundPort);
    else {
        CloseSocket();
        Logf("Error binding local port", Utils.LOGERR, BoundPort );
        return;
    }

    HttpLink.LinkMode = MODE_Text;
    if (TransferMode == TM_Fast)
    {
        HttpLink.ReceiveMode = RMODE_Manual;
        if (iMaxBytesPerTick <= 0) iMaxBytesPerTick = default.iMaxBytesPerTick;
        if (iMaxIterationsPerTick <= 0) iMaxIterationsPerTick = default.iMaxIterationsPerTick;
    }
    else HttpLink.ReceiveMode = RMODE_Event;

    OnPreConnect(self);
    curState = HTTPState_Connecting;
    bTimeout = false;
    bUseTempProxy = false;
    SetTimer(fConnectTimout, false);
    Logf("Opening connection", Utils.LOGINFO);
    if (!HttpLink.Open(LocalLink))
    {
        curState = HTTPState_Closed;
        OnConnectError(self);
        Logf("Open() failed", Utils.LOGERR, HttpLink.GetLastError());
    }
}

/** will be called from HttpLink when the resolve failed */
function ResolveFailed()
{
    curState = HTTPState_Closed;
    OnResolveFailed(self, ResolveHostname);
    Logf("Resolve failed", Utils.LOGERR, ResolveHostname);
}

/** timer is used for the conenection timeout. */
function Timer()
{
    if (curState == HTTPState_Connecting)
    {
        bTimeout = true;
        CloseSocket();
        curState = HTTPState_Closed;
        OnConnectionTimeout(self);
        Logf("Connection timeout", Utils.LOGERR, fConnectTimout);
    }
}

/** will be called from HttpLink */
function Opened()
{
    local int i, totalDataSize;
    Logf("Connection established", Utils.LOGINFO);
    StartRequestTime = Level.TimeSeconds;
    RequestDuration = -1;
    curState = HTTPState_SendingRequest;
    inBuffer = ""; // clear buffer
    outBuffer = ""; // clear buffer
    if (bUseProxy) SendData(RequestMethod@Utils.xURLtoString(CurrentURL)@"HTTP/"$HTTPVER);
        else SendData(RequestMethod@Utils.xURLtoLocation(CurrentURL)@"HTTP/"$HTTPVER);
    totalDataSize = DataSize(RequestData);
    if ((RequestMethod ~= HTTP_POST) || (RequestMethod ~= HTTP_PUT))
    {
        AddHeader("Content-Length", string(totalDataSize));
    }
    else {
        RemoveHeader("Content-Length");
        RemoveHeader("Content-Type");
    }

    if (bSendCookies && (Cookies != none))
    {
        AddHeader("Cookie", Cookies.GetCookieString(CurrentURL.hostname, CurrentURL.location, now()));
    }
    else RemoveHeader("Cookie"); // cookies should be set via the HttpCookie class

    OnSendRequestHeaders(self);
    for (i = 0; i < RequestHeaders.length; i++)
    {
        SendData(RequestHeaders[i]);
    }
    if (((RequestMethod ~= HTTP_POST) || (RequestMethod ~= HTTP_PUT)) && (totalDataSize > 0))
    {
        SendData("");
        OnRequestBody(self);
        for (i = 0; i < RequestData.length; i++)
        {
            SendData(RequestData[i], (i == RequestData.length-1));
        }
    }
    else SendData("", true); // flush the request
    ReturnHeaders.length = 0;
    ReturnData.length = 0;
    procHeader = true;
    FollowingRedir = false;
    bIsChunked = false;
    bAuthTrap = false;
    chunkedCounter = 0;
    curState = HTTPState_WaitingForResponse;
    Logf("Request send", Utils.LOGINFO);
}

/** connection closed, check for a required redirection */
function Closed()
{
    local int i;
    if (Len(inBuffer) > 0) ProcInput(inBuffer);
    if (bAutoAuthenticate && bAuthTrap && IsAuthMethodSupported(AuthMethod))
    {
        Logf("Retrying with authentication information", Utils.LOGINFO);
        AddHeader("Authorization", genAuthorization(AuthMethod, CurrentURL.username, CurrentURL.password, AuthInfo));
        OpenConnection();
    }
    else if (!FollowingRedir)
    {
        Logf("Connection closed", Utils.LOGINFO);
        curState = HTTPState_Closed;
        if (!bTimeout)
        {
            RequestDuration = Level.TimeSeconds-StartRequestTime;
            OnComplete(self);
        }
    }
    else {
        CurRedir++;
        if (iMaxRedir >= CurRedir) Logf("MaxRedir reached", Utils.LOGWARN, iMaxRedir, CurRedir);
        i = RequestHistory.Length-1;
        if (!OnFollowRedirect(self, CurrentURL)) return;
        AddHeader("Host", CurrentURL.hostname); // make sure the new host is set
        AddHeader("Referer", Utils.xURLtoString(RequestHistory[i].URL));
        OpenConnection();
    }
}

/** create the socket, if required */
function bool CreateSocket()
{
    if (HttpLink != none) return true;
    if (HttpLinkClass == none)
    {
        Logf("Error creating link class", Utils.LOGERR, HttpLinkClass);
        return false;
    }
    HttpLink = spawn(HttpLinkClass);
    HttpLink.setSocket(self);
    Logf("Socket created", Utils.LOGINFO, HttpLink);
    return true;
}

/** destroy the current socket, should only be called in case of a timeout */
function CloseSocket()
{
    if (HttpLink.IsConnected()) HttpLink.Close();
    HttpLink.Shutdown();
    HttpLink = none;
    Logf("Socket closed", Utils.LOGINFO);
}

/** called from HttpLink */
function ReceivedText( string Line )
{
    local array<string> tmp;
    local int i, datalen;

    curState = HTTPState_ReceivingData;
    if (Split(line, Chr(10), tmp) == 0) return;
    tmp[0] = inBuffer$tmp[0];
    for (i = 0; i < tmp.length-1; i++)
    {
        datalen = Len(tmp[i])+1;
        if (Right(tmp[i], 1) == Chr(13)) tmp[i] = Left(tmp[i], datalen-2); // trim trailing #13
        if (Left(tmp[i], 1) == Chr(13)) tmp[i] = Mid(tmp[i], 1); // trim leading #13
        ProcInput(tmp[i]);
        if (bIsChunked && !procHeader) chunkedCounter -= datalen; // +1 for the missing #10
    }
    if (tmp.length > 0) inBuffer = tmp[tmp.length-1];
}

/**
    Process the input
*/
protected function ProcInput(string inline)
{
    Logf("Received data", Utils.LOGDATA, procHeader@len(inline), inline);
    if (procHeader)
    {
        if (inline == "")
        {
            procHeader = false;
            ProcHeaders();
        }
        else {
            if (Left(inline, 5) ~= "date:") // make "date:" header 2nd in line
            {
                ReturnHeaders.Insert(1,1);
                ReturnHeaders[1] = inline;
            }
            else ReturnHeaders[ReturnHeaders.length] = inline;
        }
    }
    else {
        if (bIsChunked && (chunkedCounter <= 0))
        {
            chunkedCounter = Utils.HexToDec(inline);
            Logf("Next chunk", Utils.LOGINFO, chunkedCounter);
        }
        else {
            if (OnResponseBody(self, inline))
                ReturnData[ReturnData.length] = inline;
        }
    }
}

/**
    Will be called by ProcInput after all headers have been received
*/
protected function ProcHeaders()
{
    local int i, j;
    local string lhs, rhs;
    local array<string> tmp;

    // first entry is the HTTP response code
    Split(ReturnHeaders[0], " ", tmp);
    LastStatus = int(tmp[1]);
    // squad response code
    if (Utils.HTTPResponseCode(LastStatus) == "")
    {
        LastStatus = (LastStatus/100)*100;
        if ((LastStatus > 500) || (LastStatus < 100)) LastStatus = 500;
        Logf("Received unknown HTTP response code", Utils.LOGINFO, tmp[1], LastStatus);
    }
    if (ShouldFollowRedirect(LastStatus, RequestMethod))
    {
        Logf("Redirecting", Utils.LOGINFO, LastStatus);
        FollowingRedir = true;
    }
    RequestHistory[RequestHistory.Length-1].HTTPresponse = LastStatus;
                   // code  description  http/1.1
    OnReturnCode(self, LastStatus, tmp[2], tmp[0]);

    for (i = 1; i < ReturnHeaders.length; i++ )
    {
        if (!Divide(ReturnHeaders[i], ":", lhs, rhs)) continue;

        if (lhs ~= "set-cookie")
        {
            if (bProcCookies && (Cookies != none))
            {
                Cookies.ParseCookieData(rhs, CurrentURL.hostname, CurrentURL.location, now(), true, TZoffset);
            }
        }
        else if (lhs ~= "date")
        {
            // calculate timezone offset
            j = Utils.stringToTimestamp(Utils.trim(rhs), 0);
            Logf("Server date", Utils.LOGINFO, j, Utils.timestampToString(j));
            if (j != 0)
            {
                TZoffset = (now()-j)/3600;
                Logf("Timezone offset", Utils.LOGINFO, TZoffset);
            }
        }
        else if (lhs ~= "transfer-encoding")
        {
            bIsChunked = InStr(Caps(rhs), "CHUNKED") > -1;
            if (bIsChunked) Logf("Body is chunked", Utils.LOGINFO, bIsChunked);
        }
        else if (lhs ~= "www-authenticate")
        {
            ProccessWWWAuthenticate(rhs, false);
        }
        else if (lhs ~= "proxy-authorization")
        {
            ProccessWWWAuthenticate(rhs, true);
        }
    }
}

/**
    returns true when a redirect should be followed, also updates headers for
    the next request.
*/
protected function bool ShouldFollowRedirect(int retc, string method)
{
    local int i;
    local string tmp;

    if (!bFollowRedirect) return false;
    if ((method == HTTP_HEAD) || (method == HTTP_TRACE)) return false;
    if (iMaxRedir < CurRedir) return false;
    switch (retc)
    {
        case 300: // "Multiple Choices"; find prefered location
            for (i = 0; i < ReturnHeaders.length; i++)
            {
                if (left(ReturnHeaders[i], 9) ~= "location:")
                {
                    break;
                }
            }
            if (i == ReturnHeaders.length)
            {
                Logf("Did not receive a prefered choice for HTTP code 300", Utils.LOGINFO, RequestMethod);
                return false;
            }
        case 303: // "See Other"; transform into POST into GET
            if (RequestMethod != HTTP_GET) // redir is always a GET
            {
                Logf("Changing request method to GET for redirection", Utils.LOGWARN, RequestMethod);
                RequestMethod = HTTP_GET;
            }
        case 301: // "Moved Permanently";
        case 302: // "Found";
            if (!bRfcCompliantRedirect)
            {
                if (RequestMethod != HTTP_GET) // redir is always a GET
                {
                    Logf("Changing request method to GET for redirection", Utils.LOGWARN, RequestMethod);
                    RequestMethod = HTTP_GET;
                }
            }
        // semi blind redirects (no additional logic needed)
        case 201: // "Created";
        case 307: // "Temporary Redirect";
            // find the Location: field
            for (i = 0; i < ReturnHeaders.length; i++)
            {
                if (left(ReturnHeaders[i], 9) ~= "location:")
                {
                    tmp = Utils.Trim(mid(ReturnHeaders[i], 9));
                    if (Left(tmp, 1) == "/")
                    {   // a dirty trick
                        CurrentURL.location = tmp;
                        CurrentURL.query = "";
                        CurrentURL.hash = "";
                        tmp = Utils.xURLtoString(CurrentURL);
                    }

                    if (!Utils.parseUrl(tmp, CurrentURL))
                    {
                        Logf("Invalid redirection URL", Utils.LOGWARN, tmp);
                        return false;
                    }
                    return true;
                }
            }
            return false;
        case 305: // "Use Proxy"; proxy host is in location
            for (i = 0; i < ReturnHeaders.length; i++)
            {
                if (left(ReturnHeaders[i], 9) ~= "location:")
                {
                    tmp = Utils.Trim(mid(ReturnHeaders[i], 9));
                    if (Utils.parseUrl(tmp, TempProxy))
                    {
                        if (TempProxy.protocol != "http")
                        {
                            Logf("Unsupported temporary proxy", Utils.LOGWARN, tmp);
                            return false;
                        }
                        bUseTempProxy = true;
                        return true;
                    }
                    Logf("Invalid temporary proxy location", Utils.LOGWARN, tmp);
                    break;
                }
            }
            return false;
    }
    return false;
}

/**
    Send data buffered <br />
    if bFlush it will flush all remaining data (should be used for the last call)
*/
protected function SendData(string data, optional bool bFlush)
{
    Logf("Send data", Utils.LOGDATA, bFlush@len(data), data);
    if (Len(outBuffer)+len(data) > BUFFERSIZE)
    {
        HttpLink.SendText(outBuffer);
        outBuffer = "";
    }
    while (len(data) > BUFFERSIZE)
    {
        HttpLink.SendText(Left(data, BUFFERSIZE));
        data = Mid(data, BUFFERSIZE);
    }
    outBuffer = outBuffer$data$CRLF;
    if (bFlush)
    {
        HttpLink.SendText(outBuffer);
        outBuffer = "";
    }
}

/**
    Process the header data of a WWW-Authenticate or Proxy-Authorization header
*/
protected function ProccessWWWAuthenticate(string HeaderData, bool bProxyAuth)
{
    local array<string> elements;
    local string k,v;
    local int i;

    Divide(Utils.Trim(HeaderData), " ", k, HeaderData);
    if (bProxyAuth) ProxyAuthMethod = StrToAuthMethod(k);
    else AuthMethod = StrToAuthMethod(k);
    Utils.AdvSplit(Utils.Trim(HeaderData), ", ", elements, "\"");
    if (bProxyAuth) ProxyAuthInfo.length = 0;
    else AuthInfo.Length = 0;
    if (elements.Length == 0)
    {
        if (!bProxyAuth) Logf("Invalid WWW-Authenticate data", Utils.LOGERR, HeaderData);
        else Logf("Invalid Proxy-Authorization data", Utils.LOGERR, HeaderData);
        return;
    }
    else {

        for (i = 0; i < elements.length; i++)
        {
            Divide(elements[i], "=", k, v);
            if (bProxyAuth)
            {
                ProxyAuthInfo.length = ProxyAuthInfo.length+1;
                ProxyAuthInfo[ProxyAuthInfo.length-1].Key = k;
                ProxyAuthInfo[ProxyAuthInfo.length-1].Value = v;
            }
            else {
                AuthInfo.length = AuthInfo.length+1;
                AuthInfo[AuthInfo.length-1].Key = k;
                AuthInfo[AuthInfo.length-1].Value = v;
            }
        }
    }
    if (bProxyAuth)
    {
        if (!IsAuthMethodSupported(ProxyAuthMethod))
            Logf("Unsupported Proxy-Authorization method required", Utils.LOGWARN, GetEnum(enum'EAuthMethod', ProxyAuthMethod));
        else if (LastStatus == 407) OnRequireProxyAuthorization(self, ProxyAuthMethod, ProxyAuthInfo);
    }
    else {
        if (!IsAuthMethodSupported(AuthMethod))
            Logf("Unsupported WWW-Authenticate method required", Utils.LOGWARN, GetEnum(enum'EAuthMethod', AuthMethod));
        else if (LastStatus == 401)
        {
            OnRequireAuthorization(self, AuthMethod, AuthInfo);
            bAuthTrap = (CurrentURL.username != "");
            if (RequestHistory.length > 1)
            {
                i = RequestHistory.length-1;
                if ((RequestHistory[i].URL.username == RequestHistory[i-1].URL.username)
                    &&
                    (RequestHistory[i].URL.password == RequestHistory[i-1].URL.password)
                    )
                {
                    Logf("No auth retry with the same login info", Utils.LOGINFO);
                    bAuthTrap = false;
                }
            }
        }
    }
}

/**
    generate the authentication data, depending on the method it will be either
    a Basic or Digest response
*/
function string genAuthorization(EAuthMethod method, string Username, string Password, array<GameInfo.KeyValuePair> Info)
{
    if (method == AM_Basic) return genBasicAuthorization(Username, Password);
    else if (method == AM_Digest) return genDigestAuthorization(Username, Password, Info);
    return "";
}

/**
    Generated a basic authentication response
*/
protected function string genBasicAuthorization(string Username, string Password)
{
    local array<string> res;
    if (authBasicLookup.length == 0) Utils.Base64EncodeLookupTable(authBasicLookup);
    res[0] = Username$":"$Password;
    res = Utils.Base64Encode(res, authBasicLookup);
    Logf("Base 64 encoding", Utils.LOGINFO, Username$":"$Password, res[0]);
    return "Basic"@res[0];
}

/** generate the Digest authorization data string */
protected function string genDigestAuthorization(string Username, string Password, array<GameInfo.KeyValuePair> Info)
{
    local string a1, a2, qop, alg, cnonce;
    local string result, tmp, rLoc;

    result = "Digest username=\""$Username$"\", ";
    tmp = GetValue("realm", info);
    if (tmp != "") Result = result$"realm=\""$GetValue("realm", Info)$"\", ";
    tmp = GetValue("nonce", info);
    if (tmp != "") result = result$"nonce=\""$tmp$"\", ";
    rLoc = Utils.xURLtoLocation(CurrentURL);
    result = result$"uri=\""$rLoc$"\", ";
    tmp = GetValue("opaque", info);
    if (tmp != "") result = result$"opaque=\""$tmp$"\", ";

    qop = GetValue("qop", info); // to be used for the digest-response

    if (qop != "")
    {
        cnonce = randString();
        result = result$"cnonce=\""$cnonce$"\", ";
        result = result$"nc=00000001, "; // always 1st request
        result = result$"qop=\""$qop$"\", ";
    }

    alg = Caps(GetValue("algorithm", info, "MD5"));
    if (alg ~= "MD5" || alg ~= "MD5-SESS")
    {
        // A1
        if (alg == "MD5") a1 = Utils.MD5String(Username$":"$GetValue("realm", info)$":"$Password);
        else if (alg == "MD5-SESS")
        {
            a1 = Utils.MD5String(Username$":"$GetValue("realm", info)$":"$Password);
            a1 = a1$":"$GetValue("nonce", info)$":"$cnonce;
        }
        // A2
        if (qop == "" || qop ~= "auth") a2 = Utils.MD5String(Caps(RequestMethod)$":"$rLoc);
        else if (qop ~= "auth-int")
        {
            a2 = Utils.MD5Stringarray(RequestData, CRLF);
            a2 = Utils.MD5String(Caps(RequestMethod)$":"$rLoc$":"$a2);
        }
        // KD
        if (qop == "") tmp = Utils.MD5String(a1$":"$GetValue("nonce", info)$":"$a2);
        else if (qop ~= "auth" || qop ~= "auth-int")
        {
            tmp = Utils.MD5String(a1$":"$GetValue("nonce", info)$":00000001:"$cnonce$":"$qop$":"$a2);
        }
        result = result$"response=\""$tmp$"\"";
    }
    else {
        Logf("Unknown digest algorithm", Utils.LOGWARN, alg);
    }
    return result;
}

defaultproperties
{
    EXTENTION=""
    iVerbose=-1
    iLocalPort=0
    bFollowRedirect=true
    bRfcCompliantRedirect=true
    curState=HTTPState_Closed
    iMaxRedir=5
    HTTPVER="1.1"
    DefaultAccept="text/*"
    bSendCookies=true
    bProcCookies=true
    bUseProxy=false
    fConnectTimout=60
    HttpLinkClass=class'HttpLink'
    HttpCookieClass=class'HttpCookies'
    TransferMode=TM_Normal
    iMaxIterationsPerTick=32
    iMaxBytesPerTick=4096
    AuthMethod=AM_None
    bAutoAuthenticate=true
}
