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

	<!-- $Id: HttpLink.uc,v 1.2 2004/03/26 22:38:44 elmuerte Exp $ -->
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
	if (HttpSock == none) return;
	HttpSock.Closed();
}

