/*******************************************************************************
	HttpSock																	<br />
	Base of [[LibHTTP]] this implements the main network methods for connecting
	to a webserver and retreiving data from it. Binary data is not supported.	<br />
																				<br />
	Features:																	<br />
	* GET/POST support															<br />
	* Supports transparent redirecting											<br />
	* Basic Authentication support												<br />
	* Header management															<br />
	* Cookie management															<br />
	* Support for HTTP Proxy													<br />
																				<br />
	new in version 200:															<br />
	* Supports HTTP 1.1															<br />
	* Cached resolves															<br />
	* Redirection history														<br />
	* Chuncked encoding automatically decoded									<br />
	* Added connection timeout													<br />
	* More delegates															<br />
																				<br />
	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP								<br />
																				<br />
	Authors:	Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;	<br />
																				<br />
	Copyright 2003, 2004 Michiel "El Muerte" Hendriks							<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpSock.uc,v 1.18 2004/03/26 15:29:05 elmuerte Exp $ -->
*******************************************************************************/

class HttpSock extends Info config;

/** LibHTTP version number */
const VERSION = 201;

/** the output buffer size */
const BUFFERSIZE = 2048;

/** constant CR LF */
var protected string CRLF;

/** The HTTP version to use, 1.0 adviced */
var protected string HTTPVER;

/* config variables */

/** the remote host, can be passed in the url */
var(URL) config string sHostname;
/** the remote port, can be passed in the url */
var(URL) config int iPort;
/** the local port, leave zero to use a random port (adviced) */
var(URL) config int iLocalPort;
/** the username and password to use when authentication is required */
var(URL) config string sAuthUsername, sAuthPassword;
/** the default value for the Accept header, we only support "text / *" */
var(URL) config string DefaultAccept;

/** log verbosity */
var(Options) config int iVerbose;
/** when set to false it won't follow redirects */
var(Options) config bool bFollowRedirect;
/** Maximum redirections to follow */
var(Options) config int iMaxRedir;
/** Send cookie data, defaults to true */
var(Options) config bool bSendCookies;
/** Process incoming cookies, defaults to false */
var(Options) config bool bProcCookies;
/** connection timeout */
var(Options) config float fConnectTimout;

/** Use a proxy server */
var(Proxy) config bool bUseProxy;
/** The hostname of the proxy */
var(Proxy) config string sProxyHost;
/** The proxy port */
var(Proxy) config int iProxyPort;

/* local variables */

/** the requested location */
var string RequestLocation;
/** the request method */
var string RequestMethod;
/** the request headers */
var array<string> RequestHeaders;
/** the return headers */
var array<string> ReturnHeaders;
/** the request data */
var array<string> RequestData;
/** the return data */
var array<string> ReturnData;
/** the cookie data instance */
var HTTPCookies Cookies;
/** The last returned HTTP status code */
var int LastStatus;

struct RequestHistoryEntry
{
	var string Method;
	var string Hostname;
	var string Location;
	var int HTTPresponse;
};
/** history with requests for a single request, will contain more then one entry
	when redirections are followed */
var array<RequestHistoryEntry> RequestHistory;

/** the link class to use */
var protected string HttpLinkClass;
/** @ignore */
var protected HttpLink HttpLink;
/** @ignore */
var protected string inBuffer, outBuffer;
/** @ignore */
var protected bool procHeader;

/** @ingore */
var protected InternetLink.IpAddr LocalLink;
/** the port we are connected to */
var protected int BoundPort;

/** @ingore */
var protected bool FollowingRedir, RedirTrap;
/** @ingore */
var protected int CurRedir;

/** @ingore */
var protected array<string> authBasicLookup;

/** Timezone Offset, dynamically calculated from the server's time */
var protected int TZoffset;

/** @ignore */
var protected int chunkedCounter; // to count the current chunk
/** @ignore */
var protected bool bIsChunked; // if Transfer-Encoding: chunked
/** @ignore */
var protected bool bTimeout;

enum HTTPState
{
		HTTPState_Resolving,
		HTTPState_Connecting,
		HTTPState_SendingRequest,
		HTTPState_ReceivingData,
		HTTPState_Closed,
};
/** The current state of the socket */
var HTTPState curState;

/** resolve chache entry to speed up subsequent request */
struct ResolveCacheEntry
{
	/** the hostname */
	var string Hostname;
	/** the address information */
	var InternetLink.IpAddr Address;
};
/** Resolve cache, already resolved hostnames are not looked up.
	You have to keep the actor alive in order to use this feature */
var protected array<ResolveCacheEntry> ResolveCache;
/** the hostname being resolved, used to add to the resolve cache */
var protected string ResolveHostname;

/**
	will be called when the return code has been received;
*/
delegate OnReturnCode(int ReturnCode, string ReturnMessage, string HttpVer);

/**
	will be called in case of an internal error
*/
delegate OnError(string ErrorMessage, optional string Param1, optional string Param2);

/**
	will be called when the host name is resolved
	return true to continue, or false to abort
*/
delegate bool OnResolved()
{
	return true;
}

/** called when the resolved failed, hostname is the hostname that could not be resolved */
delegate OnResolveFailed(string hostname);

/** called when the connection has timed out (e.g. open() failed after a set time) */
delegate OnConnectionTimeout();

/**
	will be called when the operation was complete
*/
delegate OnComplete();

/**
	Called before the connection is established
*/
delegate OnPreConnect();

/**
	Called when Open() fails
*/
delegate OnConnectError();

/**
	Called before the redirection is followed, return false to prevernt following
	the	redirection
*/
delegate bool OnFollowRedirect()
{
	return true;
}

/**
	Start the HTTP request
	location can be a fully qualified url, or just the location on the configured server
	Method defaults to GET
*/
function bool HttpRequest(string location, optional string Method, optional HTTPCookies CookieData)
{
	if (curState != HTTPState_Closed)
	{
		Logf("HttpSock not closed", class'HttpUtil'.default.LOGERR, curState);
		return false;
	}
	RequestHistory.length = 0;

	if (Method == "") Method = "GET";
	RequestMethod = Caps(Method);
	If (!IsSupportedMethod()) return false;

	if (Left(location, 4) ~= "http") ParseRequestUrl(location, Method);
	else if (Left(location, 1) != "/")
	{
		Logf("Unsupported location", class'HttpUtil'.default.LOGERR, location);
		return false;
	}
	else RequestLocation = location;
	if (sHostname == "")
	{
		Logf("No remote hostname", class'HttpUtil'.default.LOGERR);
		return false;
	}
	if ((iPort <= 0) || (iPort >= 65536))
	{
		Logf("Changing remote port to default (80)", class'HttpUtil'.default.LOGWARN, iPort);
		iPort = 80;
	}
	// Add default headers
	AddHeader("Host", sHostname);
	AddHeader("User-Agent", UserAgent());
	AddHeader("Connection", "close");
	AddHeader("Accept", DefaultAccept);
	if (sAuthUsername != "") AddHeader("Authorization", genBasicAuthorization(sAuthUsername, sAuthPassword));
	if ((Method ~= "POST") && (InStr(RequestLocation, "?") > -1 ))
	{
		RequestData.length = 1;
		Divide(RequestLocation, "?", RequestLocation, RequestData[0]);
		AddHeader("Content-Type", "application/x-www-form-urlencoded");
	}
	// start resolve
	CurRedir = 0;
	if (CookieData != none) Cookies = CookieData;
	CRLF = Chr(13)$Chr(10);

	return OpenConnection();
}

/**
	Add a header, case insensitive
	set bNoReplace to false to not overwrite the old header
*/
function AddHeader(string hname, string value, optional bool bNoReplace)
{
	local int i;
	for (i = RequestHeaders.length-1; i >= 0; i--)
	{
		if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
		{
			if (bNoReplace) return;
			RequestHeaders.remove(i, 1);
			break;
		}
	}
	if (value == "") return;
	RequestHeaders[RequestHeaders.length] = hname$":"@value;
}

/**
	Remove a header, case insensitive
	Returns true when the header is deleted
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
function string GetRequestHeader(string hname, optional string def)
{
	local int i, j;
	for (i = 0; i < RequestHeaders.length; i++)
	{
		j = InStr(RequestHeaders[i], ":");
		if (Left(RequestHeaders[i], j) ~= hname)
		{
			return Mid(RequestHeaders[i], j+1);
		}
	}
	return def;
}

/**
	Returns the value of the returned header, or default if not found
*/
function string GetReturnHeader(string hname, optional string def)
{
	local int i, j;
	for (i = 0; i < RequestHeaders.length; i++)
	{
		j = InStr(ReturnHeaders[i], ":");
		if (Left(ReturnHeaders[i], j) ~= hname)
		{
			return Mid(ReturnHeaders[i], j+1);
		}
	}
	return def;
}

/**
	Abort the current request, if possible
*/
function bool Abort()
{
	switch (curState)
	{
		case HTTPState_Connecting:
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

/* Internal routines */

/** manage logging */
protected function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	if (level == class'HttpUtil'.default.LOGERR) OnError(Message, Param1, Param2);
	if (level <= iVerbose) class'HttpUtil'.static.Logf(Name, Message, Level, Param1, Param2);
}

/** Returns the useragent string we use */
protected function string UserAgent()
{
	return "LibHTTP/"$VERSION@"(UnrealEngine2; build "@Level.EngineVersion$"; http://wiki.beyondunreal.com/wiki/LibHTTP )";
}

/** return the actual data size of a string array, it appends sizeof(CRLF) for each line */
protected function int DataSize(out array<string> data)
{
	local int i, res;
	res = 0;
	for (i = 0; i < data.length; i++)
	{
		res += Len(data[i])+2; // 2 = the CRLF
	}
	return res;
}

/** Returns true when the request method is supported */
protected function bool IsSupportedMethod()
{
	if (RequestMethod ~= "GET") return true;
	else if (RequestMethod ~= "HEAD") return true;
	else if (RequestMethod ~= "POST") return true;
	Logf("Unsupported method", class'HttpUtil'.default.LOGERR, RequestMethod);
	return false;
}

/** Parses the fully qualified URL */
protected function ParseRequestUrl(string location, string Method)
{
	local int i, j;
	location = Mid(location, InStr(location, ":")+3); // trim leading http://
	i = InStr(location, "/");
	if (i > 0)
	{
		RequestLocation = Mid(location, i);
		location = Left(location, i);
	}
	else RequestLocation = "/"; // get index
	Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "RequestLocation", RequestLocation);
	i = InStr(location, "@");
	if (i > -1)
	{
		sAuthUsername = Left(location, i);
		location = Mid(location, i+1);
		j = InStr(sAuthUsername, ":");
		if (j > -1)
		{
			sAuthPassword = Mid(sAuthUsername, j+1);
			sAuthUsername = Left(sAuthUsername, j);
			Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sAuthPassword", sAuthPassword);
		}
		Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sAuthUsername", sAuthUsername);
	}
	i = InStr(location, ":");
	if (i > -1)
	{
		iPort = int(Mid(iPort, i));
		Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "iPort", iPort);
		location = Left(location, i);
	}
	sHostname = location;
	Logf("ParseRequestUrl", class'HttpUtil'.default.LOGINFO, "sHostname", sHostname);
}

/** start the download */
protected function bool OpenConnection()
{
	local int i;
	i = RequestHistory.Length;
	RequestHistory.Length = i+1;
	RequestHistory[i].Hostname = sHostname;
	RequestHistory[i].Method = RequestMethod;
	RequestHistory[i].Location = RequestLocation;
	RequestHistory[i].HTTPresponse = 0; // none yet

	if (!CreateSocket()) return false;

	if (bUseProxy)
	{
		if (sProxyHost == "")
		{
			Logf("No remote hostname", class'HttpUtil'.default.LOGERR);
			return false;
		}
		if ((iProxyPort <= 0) || (iProxyPort >= 65536))
		{
			Logf("Chaning proxy port to default (80)", class'HttpUtil'.default.LOGWARN, iProxyPort);
			iProxyPort = 80;
		}
		if (!CachedResolve(sProxyHost))
		{
			curState = HTTPState_Resolving;
			ResolveHostname = sProxyHost;
			HttpLink.Resolve(sProxyHost);
		}
	}
	else {
		if (!CachedResolve(sHostname))
		{
			curState = HTTPState_Resolving;
			ResolveHostname = sHostname;
			HttpLink.Resolve(sHostname);
		}
	}
	return true;
}

/** lookup a chached resolve and connect if found */
protected function bool CachedResolve(coerce string hostname, optional bool bDontConnect)
{
	local int i;
	for (i = 0; i < ResolveCache.Length; i++)
	{
		if (ResolveCache[i].Hostname ~= hostname)
		{
			Logf("Resolve cache hit", class'HttpUtil'.default.LOGINFO, hostname, HttpLink.IpAddrToString(ResolveCache[i].Address));
			ResolveHostname = hostname;
			if (!bDontConnect) InternalResolved(ResolveCache[i].Address, true);
			return true;
		}
	}
	return false;
}

/** hostname has been resolved */
function InternalResolved( InternetLink.IpAddr Addr , optional bool bDontCache)
{
	local int i;
	Logf("Host resolved succesfully", class'HttpUtil'.default.LOGINFO, ResolveHostname);
	if (!bDontCache)
	{
		ResolveCache.Length = ResolveCache.Length+1;
		ResolveCache[ResolveCache.length-1].Hostname = ResolveHostname;
		ResolveCache[ResolveCache.length-1].Address = Addr;
	}
	LocalLink.Addr = Addr.Addr;
	if (bUseProxy) LocalLink.Port = iProxyPort;
		else LocalLink.Port = iPort;
	if (!OnResolved())
	{
		Logf("Request aborted", class'HttpUtil'.default.LOGWARN, "OnResolved() == false");
		curState = HTTPState_Closed;
		return;
	}
	if (iLocalPort > 0)
	{
		BoundPort = HttpLink.BindPort(iLocalPort, true);
		if (i != iLocalPort) Logf("Could not bind preference port", class'HttpUtil'.default.LOGWARN, iLocalPort);
	}
	else BoundPort = HttpLink.BindPort();

	if (BoundPort > 0) Logf("Local port succesfully bound", class'HttpUtil'.default.LOGINFO, BoundPort);
	else {
		Logf("Error binding local port", class'HttpUtil'.default.LOGERR, BoundPort );
		CloseSocket();
		return;
	}

	HttpLink.LinkMode = MODE_Text;
	HttpLink.ReceiveMode = RMODE_Event;

	OnPreConnect();
	curState = HTTPState_Connecting;
	bTimeout = false;
	SetTimer(fConnectTimout, false);
	Logf("Opening connection", class'HttpUtil'.default.LOGINFO);
	if (!HttpLink.Open(LocalLink))
	{
		Logf("Open() failed", class'HttpUtil'.default.LOGERR, HttpLink.GetLastError());
		curState = HTTPState_Closed;
		OnConnectError();
	}
}

/** will be called from HttpLink when the resolve failed */
function ResolveFailed()
{
	curState = HTTPState_Closed;
	Logf("Resolve failed", class'HttpUtil'.default.LOGERR, ResolveHostname);
	OnResolveFailed(ResolveHostname);
}

function Timer()
{
	if (curState == HTTPState_Connecting)
	{
		bTimeout = true;
		Logf("Connection timeout", class'HttpUtil'.default.LOGERR, fConnectTimout);
		CloseSocket();
		curState = HTTPState_Closed;
		OnConnectionTimeout();
	}
}

/** will be called from HttpLink */
function Opened()
{
	local int i;
	Logf("Connection established", class'HttpUtil'.default.LOGINFO);
	curState = HTTPState_SendingRequest;
	inBuffer = ""; // clear buffer
	outBuffer = ""; // clear buffer
	if (bUseProxy) SendData(RequestMethod@"http://"$sHostname$":"$string(iPort)$RequestLocation@"HTTP/"$HTTPVER);
		else SendData(RequestMethod@RequestLocation@"HTTP/"$HTTPVER);
	if ((RequestMethod ~= "POST") || (RequestMethod ~= "PUT"))
	{
		AddHeader("Content-Length", string(DataSize(RequestData)));
	}
	if (bSendCookies && (Cookies != none))
	{
		AddHeader("Cookie", Cookies.GetCookieString(sHostname, RequestLocation, now()));
	}
	for (i = 0; i < RequestHeaders.length; i++)
	{
		SendData(RequestHeaders[i]);
	}
	if ((RequestMethod ~= "POST") || (RequestMethod ~= "PUT"))
	{
		SendData("");
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
	RedirTrap = false;
	bIsChunked = false;
	chunkedCounter = 0;
	Logf("Request send", class'HttpUtil'.default.LOGINFO);
}

function Closed()
{
	local int i;
	FollowingRedir = RedirTrap;
	if (Len(inBuffer) > 0) ProcInput(inBuffer);
	if (!FollowingRedir)
	{
		Logf("Connection closed", class'HttpUtil'.default.LOGINFO);
		curState = HTTPState_Closed;
		if (!bTimeout) OnComplete();
	}
	else {
		if (!OnFollowRedirect()) return;
		CurRedir++;
		if (iMaxRedir == CurRedir) Logf("MaxRedir reached", class'HttpUtil'.default.LOGWARN, iMaxRedir, CurRedir);
		i = RequestHistory.Length;
		AddHeader("Referer", "http://"$RequestHistory[i].Hostname$RequestHistory[i].Location);
		OpenConnection();
	}
}

/** create the socket, if required */
function bool CreateSocket()
{
	local class<HttpLink> linkclass;
	if (HttpLink != none) return true;
	linkclass = class<HttpLink>(DynamicLoadObject(HttpLinkClass, class'Class', false));
	if (linkclass == none)
	{
		Logf("Error creating link class", class'HttpUtil'.default.LOGERR, HttpLinkClass);
		return false;
	}
	HttpLink = spawn(linkclass);
	HttpLink.setSocket(self);
	Logf("Socket created", class'HttpUtil'.default.LOGINFO, HttpLink);
	return true;
}

/** destroy the current socket */
function CloseSocket()
{
	if (HttpLink.IsConnected()) HttpLink.Close();
	HttpLink.Shutdown();
	HttpLink = none;
	Logf("Socket closed", class'HttpUtil'.default.LOGINFO);
}

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
	local array<string> tmp2;
	local int retc, i;
	Logf("Received data", class'HttpUtil'.default.LOGDATA, procHeader, len(inline)$"::"@inline);
	if (procHeader)
	{
		if (inline == "")
		{
			procHeader = false;
			return;
		}

		if (ReturnHeaders.length == 0)
		{
			Split(inline, " ", tmp2);
			retc = int(tmp2[1]);
			if (bFollowRedirect && ((retc == 301) || (retc == 302)) && (iMaxRedir > CurRedir))
			{
				Logf("Redirecting", class'HttpUtil'.default.LOGINFO, retc);
				FollowingRedir = true;
				RedirTrap = false;
			}
			RequestHistory[RequestHistory.Length-1].HTTPresponse = retc;
									// code       description    http/1.0
			OnReturnCode(retc, tmp2[2], tmp2[0]);
			LastStatus = retc;
		}
		ReturnHeaders[ReturnHeaders.length] = inline;

		// if following redirection find new location
		retc = InStr(inline, ":");
		if (FollowingRedir)
		{
			if (Left(inline, retc) ~= "location")
			{
				Logf("Redirect Location", class'HttpUtil'.default.LOGINFO, inline);
				RequestLocation = class'HttpUtil'.static.Trim(Mid(inline, retc+1));
				if (Left(RequestLocation, 4) ~= "http") ParseRequestUrl(RequestLocation, RequestMethod);
				AddHeader("Host", sHostname); // make sure the new host is set
				if (RequestMethod ~= "POST") // can't redir a post request
				{
					Logf("Changing request method to post", class'HttpUtil'.default.LOGWARN);
					RequestMethod = "GET";
				}
				RedirTrap = true;
			}
		}
		if (bProcCookies && (Cookies != none))
		{
			if (Left(inline, retc) ~= "set-cookie")
			{
				Cookies.ParseCookieData(Mid(inline, retc+1), sHostname, RequestLocation, now(), true, TZoffset);
			}
		}
		if (Left(inline, retc) ~= "date")
		{
			// calculate timezone offset
			i = class'HttpUtil'.static.stringToTimestamp(class'HttpUtil'.static.trim(Mid(inline, retc+1)));
			Logf("Server date", class'HttpUtil'.default.LOGINFO, i);
			if (i != 0)
			{
				TZoffset = (now()-i)/3600;
				Logf("Timezone offset", class'HttpUtil'.default.LOGINFO, TZoffset);
			}
		}
		if (Left(inline, retc) ~= "transfer-encoding")
		{
			bIsChunked = InStr(Caps(inline), "CHUNKED") > -1;
			Logf("Body is chunked", class'HttpUtil'.default.LOGINFO, bIsChunked);
		}
	}
	else {
		if (bIsChunked && (chunkedCounter <= 0))
		{
			chunkedCounter = class'HttpUtil'.static.HexToDec(inline);
			Logf("Next chunk", class'HttpUtil'.default.LOGINFO, chunkedCounter);
		}
		else ReturnData[ReturnData.length] = inline;
	}
}

/**
	Send data buffered
	if bFlush it will flush all remaining data (should be used for the last call)
*/
protected function SendData(string data, optional bool bFlush)
{
	if (Len(outBuffer) > BUFFERSIZE)
	{
		HttpLink.SendText(outBuffer);
		outBuffer = "";
	}
	outBuffer = outBuffer$data$CRLF;
	if (bFlush)
	{
		HttpLink.SendText(outBuffer);
		outBuffer = "";
	}
}

/**
	Generated a basic authentication
*/
protected function string genBasicAuthorization(string Username, string Password)
{
	local array<string> res;
	if (authBasicLookup.length == 0) class'HttpUtil'.static.Base64EncodeLookupTable(authBasicLookup);
	res[0] = Username$":"$Password;
	res = class'HttpUtil'.static.Base64Encode(res, authBasicLookup);
	Logf("Base 64 encoding", class'HttpUtil'.default.LOGINFO, Username$":"$Password, res[0]);
	return "Basic"@res[0];
}

/**
	Returns the current timestamp
*/
function int now()
{
	return class'HttpUtil'.static.timestamp(Level.Year, Level.Month, Level.Day, Level.Hour, Level.Minute, Level.Second);
}

defaultproperties
{
	iVerbose=-1
	iLocalPort=0
	bFollowRedirect=true
	curState=HTTPState_Closed
	iMaxRedir=5
	HTTPVER="1.1"
	DefaultAccept="text/*"
	bSendCookies=true
	bProcCookies=false
	bUseProxy=false
	fConnectTimout=60
	HttpLinkClass="LibHTTP2.HttpLink"
}
