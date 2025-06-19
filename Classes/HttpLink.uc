/*
 * MIT License
 *
 * Copyright (c) 2025 Tuomo Kriikkula
 * Copyright (c) 2003-2005 Michiel Hendriks
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

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
simulated function Shutdown()
{
    HttpSock = none;
    Close();
    // Destroy();
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

    // `log(self @ GetFuncName() @ Line);
}

/** @ignore */
event Closed()
{
    local string data;
    // local int i;
    if (HttpSock == none) return;

    // `log(self @ GetFuncName() @ DataPending @ IsDataPending());

    if (ReceiveMode == RMODE_Manual && IsDataPending())
    {    // should never happen, but just in case
        // i = ReadText(data);
        ReadText(data);
        // `log(self @ GetFuncName() @ "i:" @ i);
        HttpSock.ReceivedText(data);
        // SetTimer(0.01, False, NameOf(Closed));
        // return;
    }

    // if (IsDataPending())
    // {
    //     SetTimer(0.01, False, NameOf(Closed));
    //     return;
    // }

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
        // `log(self @ GetFuncName() @ DataPending @ IsDataPending());

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
        // `log(self @ GetFuncName() @ "i:" @ i @ "data:" @ data @ "MaxIt:" @ MaxIt @ "CurCount:" @ CurCount);

        if (i == 0)
        {
            MaxIt--;
        }
        else
        {
            CurCount += i;
            HttpSock.ReceivedText(data);
        }
    }
}
