/**
	HttpSock
	Base of LibHTTP this implements the main network methods for connecting to a
	webserver and retreiving data from it

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: HttpSock.uc,v 1.2 2003/07/29 01:35:56 elmuerte Exp $
*/

class HttpSock extends TcpLink config;

/** LibHTTP version number */
const VERSION = 100;

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

/** @ignore */
var private string buffer;
/** @ignore */
var private bool procHeader;

/** @ingore */
var IpAddr LocalLink;

/** @ingore */
var bool FollowingRedir, RedirTrap;
/** @ingore */
var int CurRedir;

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
function bool HttpRequest(string location, optional string Method, optional array<string> Headers)
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
	// start resolve
	curState = HTTPState_Resolving;
	CurRedir = 0;
	Resolve(sHostname);
}

/**
	Add a header, case insensitive
	set bNoReplace to false to not overwrite the old header
*/
function AddHeader(string hname, string value, optional bool bNoReplace)
{
	local int i;
	if (hname ~= "Connection")
	{
		Logf("Can't change 'Connection' header", LOGINFO);
		return;
	}
	for (i = 0; i < RequestHeaders.length; i++)
	{
		if (Left(RequestHeaders[i], InStr(RequestHeaders[i], ":")) ~= hname)
		{
			if (bNoReplace) return;
			RequestHeaders.remove(i, 1);
			break;
		}
	}
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
	Encode special characters to an url format
*/
static function string RawUrlEncode(string instring)
{
	return instring;
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
private function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	if (level == LOGERR) OnError(Message, Param1, Param2);
	if (level <= iVerbose) Log(Name$":"@message@chr(9)@param1@chr(9)@Param2, 'LibHTTP');
}

/** Returns the useragent string we use */
private function string UserAgent()
{
	return "LibHTTP/"$VERSION@"(Unreal Engine"@Level.EngineVersion$"; http://wiki.beyondunreal.com/wiki/LibHTML )";
}

/** Returns true when the request method is supported */
private function bool IsSupportedMethod()
{
	if (RequestMethod ~= "GET") return true;
	else if (RequestMethod ~= "HEAD") return true;
	//else if (Method ~= "POST") return true;
	Logf("Unsupported method", LOGERR, RequestMethod);
	return false;
}

/** Parses the fully qualified URL */
private function ParseRequestUrl(string location, string Method)
{
	local int i, j;
	location = Mid(location, InStr(location, ":")+3); // trim leading http://
	i = InStr(location, "/");
	if (i > 0)
	{
		RequestLocation = Mid(location, i);
		location = Left(location, i);
		//TODO: if Method == POST move query
	}
	else RequestLocation = "/"; // get index
	Logf("ParseRequestUrl", LOGINFO, "RequestLocation", RequestLocation);
	i = InStr(location, "@");
	if (i > -1)
	{
		sAuthUsername = Mid(location, i);
		location = Left(location, i);
		j = InStr(location, ":");
		if ((j > -1) && (j < i))
		{
			Logf("ParseRequestUrl", LOGINFO, "sAuthPassword", sAuthPassword);
			sAuthPassword = Mid(sAuthUsername, j);
			sAuthUsername = Left(sAuthUsername, j);
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
  LinkMode = MODE_Line;
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
	buffer = ""; // clear buffer
	SendText(RequestMethod@RequestLocation@"HTTP/1.0"); // currently only HTTP/1.0 supported
  for (i = 0; i < RequestHeaders.length; i++)
	{
		SendText(RequestHeaders[i]);
	}
	SendText(""); // the empty line
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

event ReceivedLine( string Line )
{
	local array<string> tmp, tmp2;
	local int i, retc;

	curState = HTTPState_ReceivingData;
	line = buffer$line;
	if (Split(line, Chr(10), tmp) == 0) return;
	for (i = 0; i < tmp.length-1; i++)
	{
		if (Right(tmp[i], 1) == Chr(13)) tmp[i] = Left(tmp[i], Len(tmp[i])-1); // trim trailing #13
		Logf("Received data", LOGINFO+1, tmp[i], procHeader);
		if (procHeader)
		{
			if (ReturnHeaders.length == 0) 
			{
				Split(tmp[i], " ", tmp2);
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
			ReturnHeaders[ReturnHeaders.length] = tmp[i];

			// if following redirection find new location
			if (FollowingRedir)
			{
				retc = InStr(tmp[i], ":");
				if (Left(tmp[i], retc) ~= "location")
				{
					Logf("Redirect Location", LOGINFO, tmp[i]);
					RequestLocation = Trim(Mid(tmp[i], retc+1));
					if (Left(RequestLocation, 4) ~= "http") ParseRequestUrl(RequestLocation, RequestMethod);
					AddHeader("Host", sHostname); // make sure the new host is set
					RedirTrap = true;
				}
			}
			if (tmp[i] == "") procHeader = false;
		}
		else {
			ReturnData[ReturnData.length] = tmp[i];
		}
	}
  buffer = tmp[tmp.length-1];
}

// Trim leading and trailing spaces
static final function string Trim(coerce string S)
{
    while (Left(S, 1) == " ") S = Right(S, Len(S) - 1);
		while (Right(S, 1) == " ") S = Left(S, Len(S) - 1);
    return S;
}

defaultproperties
{
	iVerbose=-1
	iLocalPort=0
	bFollowRedirect=true
	curState=HTTPState_Closed
	iMaxRedir=5
}