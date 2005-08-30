/*******************************************************************************
    HttpCache                                                                   <br />
    Disk\Memory cache for LibHTTP, it will handle caching of data. To use it
    simply create a HttpCache object and use it's get() request to get updated
    documents. Don't use a HttpSock instance for this.                          <br />
    When using this class it will perform a specially constructed get request
    when it's needed, it will try to satisfy the caching headers returned by the
    server. Ihis class is only usefull if you know the remote server returns
    correct cachable data. By default most dynamic pages (ASP, PHP, Perl, CGI)
    will return non-cachable pages.                                             <br />

                                                                                <br />
    Dcoumentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2005 Michiel "El Muerte" Hendriks                                 <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense                <br />

    <!-- $Id: HttpCache.uc,v 1.5 2005/08/30 18:15:29 elmuerte Exp $ -->
*******************************************************************************/

class HttpCache extends Engine.Info config(HttpCache) ParseConfig;

/**
    Our HttpSock class, unless it's assigned it will create it's own on the
    first get() request. So if you have a custom HttpSock class set it before
    requesting a document.
*/
var HttpSock HttpSock;
/** handle to the last cache hit  */
var HttpCacheObject LastHit;

/**  */
var class<HttpCacheObject> HttpCacheObjectClass;

/** maximum cache size (entries?) */
var(Options) config int iCacheLimit;

/**
   Reasons for a failure
*/
enum ECacheFailError
{
    CF_None,        /* no error, won't be used anyway */
    CF_BadRequest,  /* the get request isn't valid */
    CF_AuthRequired,/* authentication required, you may not use that */
    CF_Timeout,     /* timeout connecting to the server to get initial data */
    CF_Busy,        /* already busy performing a refresh of this request */

    CF_Unknown,     /* something serious happened */
};

/**
    Hints where the data came from
*/
enum EDataOrigin
{
    DO_Unknown,     /* yeah right */
    DO_Cache,       /* straight from the cache */
    DO_Initial,     /* initial retrieval of the data */
    DO_Refresh,     /* refreshed the data in the cache */
};

/** records of the cached entries */
struct CacheInfoRecord
{
    var string URL;
    /** hash used for record info */
    var int Hash;
    /** index in the CacheObjectList */
    var int colidx;
};

/** cache list, each entry is an URL */
var protected config array<CacheInfoRecord> CacheList;

/** the spawned cache objects */
var protected array<HttpCacheObject> CacheObjectList;

struct CacheRequest
{
    var HttpSock Socket;
    var int ID;
};
/** running requests */
var protected array<CacheRequest> Requests;
/** urls and ids */
var protected array<string> URLs;

////////////////////////////////////////////////////////////////////////////////
//
//   Delegates
//
////////////////////////////////////////////////////////////////////////////////

/**
    Will be called in case of an internal error.
*/
delegate OnError(HttpCache Sender, string ErrorMessage, optional string Param1, optional string Param2);

/**
    Will be called when the operation was completed successfully.
*/
delegate OnComplete(HttpLink Sender, HttpCacheObject Data, EDataOrigin origin);

/**
    failed to complete the request, will be called when everything fails
*/
delegate OnFail(HttpLink Sender, int id, ECacheFailError reason);

/**
    cache hit
*/
delegate OnCacheHit(HttpCache Sender, int id);
/**
    cache fail, get fresh info
*/
delegate OnCacheFail(HttpCache Sender, int id);

/**
    Will be called after the HttpSock instance has been created. Use it to set
    certain variables and delegates for the HttpSock. <br />
    Note: some delegates in HttpSock will always be assigned to this actor.
*/
delegate OnCreateSock(HttpCache Sender, HttpSock Socket, int id);

////////////////////////////////////////////////////////////////////////////////
//
//   Public functions
//
////////////////////////////////////////////////////////////////////////////////

/**
    Performs a get request. Returns the ID of the request. This Id can be used
    in to retrieve the URL in the future
*/
function int get(string location)
{
    local int hash;
    local int idx;
    //TODO: fix location; hostname is case insensitive
    //TODO: parse URL
    hash = createHash(location);
    idx = findCacheRecord(hash);
    if (idx == -1)
    {
        idx = CacheList.length;
        CacheList[idx].URL = location;
        CacheList[idx].hash = hash;
    }
    return idx;
}

/**
    Returns true when the location is cached
*/
function bool isCached(string location)
{
    return false;
}

/**
    Returns the URL for a certain ID. Result will be false when the ID is no
    longer valid.
*/
function bool getURLbyId(int id, out string URL)
{

    return false;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Private functions
//
////////////////////////////////////////////////////////////////////////////////

/** return the hash of the URL */
static final function int createHash(string URL)
{
    local int result;
    local int i, g;
    result = 0x12345670;
    for (i = 0; i < len(url); ++i)
    {
        result = (result << 4) + asc(mid(url, i, 1));
        g = result & 0xf0000000;
        if (g > 0) result = result | (g >> 24) | g;
    }
    return result;
}

protected function int findCacheRecord(int hash)
{
    local int i;
    for (i = 0; i < CacheList.length; i++)
    {
        if (CacheList[i].Hash == hash) return i;
    }
    return -1;
}

protected function HttpCacheObject getCacheObject(int idx)
{
    local int lidx;
    if (idx < 0 || idx >= CacheList.length) return none;
    if ((CacheList[idx].colidx > -1) && (CacheList[idx].colidx < CacheObjectList.length))
    {
        return CacheObjectList[CacheList[idx].colidx];
    }
    lidx = CacheObjectList.length;
    CacheList[idx].colidx = lidx;
    CacheObjectList[lidx] = new(self, "h"$string(CacheList[idx].Hash)) HttpCacheObjectClass;
    return CacheObjectList[lidx];
}

defaultproperties
{
    HttpCacheObjectClass=class'HttpCacheObject'
}
