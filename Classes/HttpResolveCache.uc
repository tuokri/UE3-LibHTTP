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
    HttpResolveCache                                                            <br />
    Object that holds cached resolves. this is used by multiple HttpSock
    instances
                                                                                <br />
    Documentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2005 Michiel "El Muerte" Hendriks                                 <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense                <br />

    <!-- $Id: HttpResolveCache.uc,v 1.1 2005/05/29 20:07:52 elmuerte Exp $ -->
*******************************************************************************/

class HttpResolveCache extends Core.Object;

/** resolve cache entry to speed up subsequent request */
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

/** lookup a resolved address */
function bool ResolveAddress(string hostname, out InternetLink.IpAddr Address)
{
    local int i;
    for (i = 0; i < ResolveCache.Length; i++)
    {
        if (ResolveCache[i].Hostname ~= hostname)
        {
            Address = ResolveCache[i].Address;
            return true;
        }
    }
    return false;
}

/** add an entry */
function AddCacheEntry(string hostname, InternetLink.IpAddr Address)
{
    ResolveCache.Length = ResolveCache.Length+1;
    ResolveCache[ResolveCache.length-1].Hostname = hostname;
    ResolveCache[ResolveCache.length-1].Address = Address;
}
