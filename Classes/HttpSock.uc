/**
	HttpSock
	Base of [[LibHTTP]] this implements the main network methods for connecting to a
	webserver and retreiving data from it

	Features:
	* GET/POST support
	* Supports transparent redirecting
	* Basic Authentication support
	* Header management
	* Cookie management

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: HttpSock.uc,v 1.6 2003/07/29 14:13:21 elmuerte Exp $
*/

class HttpSock extends TcpLink config;

/** LibHTTP version number */
const VERSION = 102;

/** the output buffer size */
const BUFFERSIZE = 2048;

/** constant CR LF */
var protected string CRLF;

/** The HTTP version to use, 1.0 adviced */
var string HTTPVER;

/* config variables */

/** the remote host */
var config string sHostname;
/** the remote port */
var config int iPort;
/** the local port, leave zero to use a random port (adviced) */
var config int iLocalPort;
/** when set to false it won't follow redirects */
var config bool bFollowRedirect;
/** the username and password to use when authentication is required */
var config string sAuthUsername, sAuthPassword;
/** log verbosity */
var config int iVerbose;
/** Maximum redirections to follow */
var config int iMaxRedir;
/** Send cookie data, defaults to true */
var config bool bSendCookies;
/** Process incoming cookies, defaults to false */
var config bool bProcCookies;

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

/** @ignore */
var protected string inBuffer, outBuffer;
/** @ignore */
var protected bool procHeader;

/** @ingore */
var IpAddr LocalLink;

/** @ingore */
var protected bool FollowingRedir, RedirTrap;
/** @ingore */
var protected int CurRedir;

/** @ingore */
var protected array<string> authBasicLookup;

/* log levels */
const LOGERR = 0;
const LOGWARN = 1;
const LOGINFO = 2;

enum HTTPState {
		HTTPState_Resolving,
		HTTPState_Connecting,
		HTTPState_ReceivingData,
		HTTPState_Closed,
};
/** The current state of the socket */
var HTTPState curState;

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

/**
	will be called when the operation was complete
*/
delegate OnComplete();

/**
	Start the HTTP request
	location can be a fully qualified url, or just the location on the configured server
	Method defaults to GET
	Headers are additional headers to send, adviced is to use AddHeader
*/
function bool HttpRequest(string location, optional string Method, optional array<string> Headers, optional HTTPCookies CookieData)
{
	local int i, j;
	if (curState != HTTPState_Closed)
	{
		Logf("HttpSock not closed", LOGERR, curState);
		return false;
	}

	if (Method == "") Method = "GET";
	RequestMethod = Caps(Method);
	If (!IsSupportedMethod()) return false;

	if (Left(location, 4) ~= "http") ParseRequestUrl(location, Method);
	else if (Left(location, 1) != "/")
	{
		Logf("Unsupported location", LOGERR, location);
		return false;
	}
	else RequestLocation = location;	
	if (sHostname == "")
	{
		Logf("No remote hostname", LOGERR);
		return false;
	}
	if ((iPort <= 0) || (iPort >= 65536))
	{
		Logf("Chaning remote port to default", LOGWARN, iPort);
		iPort = 80;
	}
	// Add default headers
	AddHeader("Host", sHostname);
	AddHeader("User-Agent", UserAgent());
	AddHeader("Connection", "close");
	// Add aditional headers
	for (i = 0; i < headers.length; i++)
	{
		j = InStr(headers[i], ":");
		if (j > 0)
		{
			AddHeader(Left(headers[i], j-1), Mid(headers[i], j));
		}
	}
	if (sAuthUsername != "") AddHeader("Authorization", genBasicAuthorization(sAuthUsername, sAuthPassword));
	if ((Method ~= "POST") && (InStr(RequestLocation, "?") > -1 ))
	{
		RequestData.length = 1;
		Divide(RequestLocation, "?", RequestLocation, RequestData[0]);
		AddHeader("Content-Type", "application/x-www-form-urlencoded");
	}
	// start resolve
	curState = HTTPState_Resolving;
	CurRedir = 0;
	Cookies = CookieData;
	CRLF = Chr(13)$Chr(10);
	Resolve(sHostname);
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
		case HTTPState_ReceivingData: if (IsConnected()) return Close();
	}
	return false;
}

/* Internal routines */

protected function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	if (level == LOGERR) OnError(Message, Param1, Param2);
	if (level <= iVerbose) 
	{
		message = message@chr(9)@param1@chr(9)@Param2;
		if (Len(message) > 512) message = Left(message, 512)@"..."; // trim message (crash protection)
		Log(Name$":"@message, 'LibHTTP');
	}
}

/** Returns the useragent string we use */
protected function string UserAgent()
{
	return "LibHTTP/"$VERSION@"(Unreal Engine"@Level.EngineVersion$"; http://wiki.beyondunreal.com/wiki/LibHTML )";
}

protected function int DataSize(array<string> data)
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
	Logf("Unsupported method", LOGERR, RequestMethod);
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
	Logf("ParseRequestUrl", LOGINFO, "RequestLocation", RequestLocation);
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
			Logf("ParseRequestUrl", LOGINFO, "sAuthPassword", sAuthPassword);
		}
		Logf("ParseRequestUrl", LOGINFO, "sAuthUsername", sAuthUsername);
	}
	i = InStr(location, ":");
	if (i > -1)
	{
		iPort = int(Mid(iPort, i));
		Logf("ParseRequestUrl", LOGINFO, "iPort", iPort);
		location = Left(location, i);
	}
	sHostname = location;
	Logf("ParseRequestUrl", LOGINFO, "sHostname", sHostname);
}

/** hostname has been resolved */
event Resolved( IpAddr Addr )
{
	local int i;
	LocalLink.Addr = Addr.Addr;
	LocalLink.Port = iPort;
	if (!OnResolved()) 
	{
		Logf("Request aborted", LOGWARN, "OnResolved() == false");
		curState = HTTPState_Closed;
		return;
	}
	if (iLocalPort > 0) 
	{
		i = BindPort(iLocalPort, true);
		if (i != iLocalPort) Logf("Could not bind preference port", LOGWARN, iLocalPort);
	}
	else BindPort();
  LinkMode = MODE_Text;
  ReceiveMode = RMODE_Event;
	curState = HTTPState_Connecting;
  if (!Open(LocalLink))
	{
		Logf("Open() failed", LOGERR);
		curState = HTTPState_Closed;
	}
}

event ResolveFailed()
{
  Logf("Resolve failed", LOGERR, sHostname);
	curState = HTTPState_Closed;
}

event Opened()
{
	local int i;
  Logf("Connection established", LOGINFO);
	inBuffer = ""; // clear buffer
	outBuffer = ""; // clear buffer
	SendData(RequestMethod@RequestLocation@"HTTP/"$HTTPVER);
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
	Logf("Request send", LOGINFO);
}

event Closed()
{
	FollowingRedir = RedirTrap;
	if (Len(inBuffer) > 0) ProcInput(inBuffer);
	if (!FollowingRedir)
	{
		Logf("Connection closed", LOGINFO);
		curState = HTTPState_Closed;
		OnComplete();
	}
	else {
		CurRedir++;
		if (iMaxRedir == CurRedir) Logf("MaxRedir reached", LOGWARN, iMaxRedir, CurRedir);
		Resolve(sHostname);
	}
}

event ReceivedText( string Line )
{
	local array<string> tmp;
	local int i;

	curState = HTTPState_ReceivingData;
	if (Split(line, Chr(10), tmp) == 0) return;
	tmp[0] = inBuffer$tmp[0];
	for (i = 0; i < tmp.length-1; i++)
	{
		if (Right(tmp[i], 1) == Chr(13)) tmp[i] = Left(tmp[i], Len(tmp[i])-1); // trim trailing #13
		ProcInput(tmp[i]);
	}
  inBuffer = tmp[tmp.length-1]; // FIXME: ?? could be real last line
}

/**
	Process the input
*/
protected function ProcInput(string inline)
{
	local array<string> tmp2;
	local int retc;
	Logf("Received data", LOGINFO+1, inline, procHeader);
	if (procHeader)
	{
		if (ReturnHeaders.length == 0) 
		{
			Split(inline, " ", tmp2);
			retc = int(tmp2[1]);
			if (bFollowRedirect && ((retc == 301) || (retc == 302)) && (iMaxRedir > CurRedir))
			{
				Logf("Redirecting", LOGINFO, retc);
				FollowingRedir = true;
				RedirTrap = false;
			}
									// code       description    http/1.0
			OnReturnCode(retc, tmp2[2], tmp2[0]);
		}
		ReturnHeaders[ReturnHeaders.length] = inline;

		// if following redirection find new location
		if (FollowingRedir)
		{
			retc = InStr(inline, ":");
			if (Left(inline, retc) ~= "location")
			{
				Logf("Redirect Location", LOGINFO, inline);
				RequestLocation = Trim(Mid(inline, retc+1));
				if (Left(RequestLocation, 4) ~= "http") ParseRequestUrl(RequestLocation, RequestMethod);
				AddHeader("Host", sHostname); // make sure the new host is set
				if (RequestMethod ~= "POST") // can't redir a post request
				{
					Logf("Changing request method to post", LOGWARN);
					RequestMethod = "GET";
				}
				RedirTrap = true;
			}
		}
		if (inline == "") procHeader = false;
	}
	else {
		ReturnData[ReturnData.length] = inline;
	}
}

/**	Trim leading and trailing spaces */
static final function string Trim(coerce string S)
{
    while (Left(S, 1) == " ") S = Right(S, Len(S) - 1);
		while (Right(S, 1) == " ") S = Left(S, Len(S) - 1);
    return S;
}

/**
	Send data buffered
	if bFlush it will flush all remaining data (should be used for the last call)
*/
protected function SendData(string data, optional bool bFlush)
{
	if (Len(outBuffer) > BUFFERSIZE)
	{
		SendText(outBuffer);
		outBuffer = "";
	}
	outBuffer = outBuffer$data$CRLF;
	if (bFlush)
	{
		SendText(outBuffer);
		outBuffer = "";
	}
}

/**
	Generated a basic authentication
*/
protected function string genBasicAuthorization(string Username, string Password)
{
	local int i, dl;
	local string res;
	local array<byte> inp;
	local array<string> outp;
	if (authBasicLookup.length == 0) class'HttpUtil'.static.Base64LookupTable(authBasicLookup);
	res = Username$":"$Password;
	// convert string to byte array
	for (i = 0; i < len(res); i++)
	{
		inp[i] = Asc(Mid(res, i, 1));
	}
	dl = inp.length;
	// fix byte array
	if ((dl%3) == 1) 
	{
		inp[inp.length] = 0; 
		inp[inp.length] = 0;
	}
	if ((dl%3) == 2) 
	{
		inp[inp.length] = 0;
	}
	i = 0;
	while (i < dl)
	{
		outp[outp.length] = authBasicLookup[(inp[i] >> 2)];
		outp[outp.length] = authBasicLookup[((inp[i]&3)<<4) | (inp[i+1]>>4)];
		outp[outp.length] = authBasicLookup[((inp[i+1]&15)<<2) | (inp[i+2]>>6)];
		outp[outp.length] = authBasicLookup[(inp[i+2]&63)];
		i += 3;
	}
	// pad result
	if ((dl%3) == 1) 
	{
		outp[outp.length-1] = "="; 
		outp[outp.length-2] = "=";
	}
	if ((dl%3) == 2) 
	{
		outp[outp.length-1] = "=";
	}
	res = "";
	for (i = 0; i < outp.length; i++)
	{
		res = res$outp[i];
	}	
	Logf("Base 64 encoding", LOGINFO, Username$":"$Password, res);
	return "Basic"@res;
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
	HTTPVER="1.0"
	bSendCookies=true
	bProcCookies=false
}