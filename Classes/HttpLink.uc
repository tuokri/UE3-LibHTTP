/*******************************************************************************
	HttpLink                                                                    <br />
	The actual internet link of the HttpSock object. Because connection timeouts
	can't be handled properly from within the TCPLink this object is used
	internally <br />

	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
																				<br />
	Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
																				<br />
	Copyright  2004 Michiel "El Muerte" Hendriks                                <br />
	Released under the Lesser Open Unreal Mod License                           <br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense

	<!-- $Id: HttpLink.uc,v 1.7 2005/08/13 14:57:33 elmuerte Exp $ -->
*******************************************************************************/

class HttpLink extends IpDrv.TcpLink;

/** the owning HttpSock */
var protected HttpSock HttpSock;

/** set the socket component */
function setSocket(HttpSock Sock)
{
	if (HttpSock != none) return;
	HttpSock = Sock;
}

/** call this to destroy the socket */
function Shutdown()
{
	HttpSock = none;
	Destroy();
}

/** @ignore */
event Resolved( IpAddr Addr )
{
	if (HttpSock == none) return;
	HttpSock.InternalResolved(Addr);
}

/** @ignore */
event ResolveFailed()
{
	if (HttpSock == none) return;
	HttpSock.ResolveFailed();
}

/** @ignore */
event Opened()
{
	if (HttpSock == none) return;
	HttpSock.Opened();
}

/** @ignore */
event ReceivedText( string Line )
{
	if (HttpSock == none) return;
	HttpSock.ReceivedText(Line);
}

/** @ignore */
event Closed()
{
	local string data;
	if (HttpSock == none) return;
	if (ReceiveMode == RMODE_Manual && IsDataPending())
	{    // should never happen, but just in case
		ReadText(data);
		HttpSock.ReceivedText(data);
	}
	HttpSock.ReceivedText(chr(10)); // to flush buffered data
	HttpSock.Closed();
}

event Tick(float delta)
{
	super.Tick(delta);
	if (ReceiveMode != RMODE_Manual) return;
	if (!IsConnected()) return;
	FastTransfer();
}

/** will be called when ReceiveMode is RMODE_Manual (e.g. TM_Fast) */
protected function FastTransfer()
{
	local string data;
	local int MaxIt, CurCount, i;
	if (HttpSock == none) return;

	CurCount = 0;
	MaxIt = HttpSock.iMaxIterationsPerTick;
	while (IsDataPending())
	{
		if (MaxIt <= 0)
		{
			HttpSock.Logf("Reached maximum iteration count", class'HttpUtil'.default.LOGINFO, HttpSock.iMaxIterationsPerTick);
			break;
		}
		if (CurCount > HttpSock.iMaxBytesPerTick)
		{
			HttpSock.Logf("Reached maximum bytes per tick", class'HttpUtil'.default.LOGINFO, CurCount, HttpSock.iMaxBytesPerTick);
			break;
		}
		i = ReadText(data);
		if (i == 0) MaxIt--;
		else {
			CurCount += i;
			HttpSock.ReceivedText(data);
		}
	}
}
