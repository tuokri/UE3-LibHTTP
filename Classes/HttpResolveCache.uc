/*******************************************************************************
    HttpResolveCache                                                            <br />
    Object that holds cached resolves. this is used by multiple HttpSock
    instances
                                                                                <br />
    Dcoumentation and Information:
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

