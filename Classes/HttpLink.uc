/*******************************************************************************
	HttpLink																	<br />
	The actual internet link of the HttpSock object. Because connection timeouts
	can't be handled properly from within the TCPLink this object is used
	internally <br />

	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP								<br />
																				<br />
	Authors:	Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;	<br />
																				<br />
	Copyright  2004 Michiel "El Muerte" Hendriks								<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpLink.uc,v 1.3 2004/09/19 11:17:42 elmuerte Exp $ -->
*******************************************************************************/

class HttpLink extends TcpLink;

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
	{	// should never happen, but just in case
		ReadText(data);
		HttpSock.ReceivedText(data);
	}
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
			log("Reached maximum iteration count", name);
			break;
		}
		if (CurCount > HttpSock.iMaxBytesPerTick)
		{
			Log("Received max bytes per tick"@CurCount, name);
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
