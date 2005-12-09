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

    <!-- $Id: HttpCache.uc,v 1.9 2005/12/09 08:31:11 elmuerte Exp $ -->
*******************************************************************************/

class HttpCache extends Engine.Info
    config(HttpCache)
    ParseConfig
    dependsOn(HttpUtil);

/**  */
var class<HttpSock> HttpSockClass;
/**  */
var class<HttpCacheObject> HttpCacheObjectClass;

/** maximum cache size (entries?) */
var(Options) globalconfig int iCacheLimit;

/**
   Reasons for a failure
*/
enum ECacheFailError
{
    CF_None,        /* no error, won't be used anyway */
    CF_BadRequest,  /* the get request isn't valid */
    CF_AuthRequired,/* authentication required, you may not use that */
    CF_Timeout,     /* timeout connecting to the server to get initial data */
    CF_ResolveFailed,/* hostname couldn't be resolved */
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
    /** the request URL */
    var HttpUtil.xURL URL;
    /** hash used for record info */
    var int Hash;
    /** last datazie */
    var int DataSize;
    /** last update */
    var int LastUpdate;
    /** index in the CacheObjectList, volatile */
    var int colidx;
};

/** cache list, each entry is an URL */
var protected config array<CacheInfoRecord> CacheList;

/** the spawned cache objects */
var protected array<HttpCacheObject> CacheObjectList;

struct CacheRequest
{
    var HttpSock Socket;
    var int idx;
};
/** running requests */
var protected array<CacheRequest> Requests;

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
delegate OnComplete(HttpCache Sender, HttpCacheObject Data, EDataOrigin origin);

/**
    failed to complete the request, will be called when everything fails
*/
delegate OnFail(HttpCache Sender, int idx, ECacheFailError reason);

/**
    Will be called after the HttpSock instance has been created. Use it to set
    certain variables and delegates for the HttpSock. <br />
    Note: You shouldn't set any delegates in the sccket, most will be
    overwritten anyway.
*/
delegate OnCreateSock(HttpCache Sender, HttpSock Socket);

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
    local int idx, i;
    local HttpUtil.xURL xloc;
    local HttpCacheObject co;

    if (!class'HttpUtil'.static.parseUrl(location, xloc))
    {
        OnFail(self, -1, CF_BadRequest);
        return -1;
    }
    //TODO: check http, etc.
    xloc.hostname = Locs(xloc.hostname);
    location = class'HttpUtil'.static.xUrlToString(xloc, true);
    hash = createHash(location);
    idx = findCacheRecord(hash);
    if (idx == -1)
    {
        idx = CacheList.length;
        CacheList.length = idx+1;
        CacheList[idx].URL = xloc;
        CacheList[idx].hash = hash;
        CacheList[idx].colidx = -1;
    }
    co = getCacheObject(idx);
    if (co.bBusy)
    {
        OnFail(self, -1, CF_Busy);
        return -1;
    }
    co.URL = location;
    co.bBusy = true;
    if (co.ExpiresOn > class'HttpUtil'.static.timestamp(Level.Year, Level.Month, Level.Day, Level.Hour, Level.Minute, Level.Second))
    {
        // content not yet expired
        OnComplete(self, co, DO_Cache);
        return idx; // no need to save anything
    }
    // find free sock
    for (i = 0; i < Requests.length; i++)
    {
        if (Requests[i].idx == -1) break;
    }
    if (i == Requests.length)
    {
        Requests.length = i+1;
        Requests[i].Socket = spawn(HttpSockClass);
        OnCreateSock(self, Requests[i].Socket);
        Requests[i].Socket.OnComplete = DownloadComplete;
        Requests[i].Socket.OnError = DownloadError;
        Requests[i].Socket.OnConnectionTimeout = DownloadTimeout;
        Requests[i].Socket.OnResolveFailed = ResolveFailed;
    }
    Requests[i].idx = idx;
    Requests[i].Socket.ClearRequestData();
    if (co.LastModification > 0)
        Requests[i].Socket.AddHeader("If-Modified-Since", class'HttpUtil'.static.timestampToString(co.LastModification));
    if (!Requests[i].Socket.get(location))
    {
        OnFail(self, -1, CF_BadRequest);
        return -1;
    }
    return idx;
}

/**
    Returns true when the location is cached
*/
function bool isCached(string location)
{
    local int i;
    local HttpUtil.xURL xloc;
    if (!class'HttpUtil'.static.parseUrl(location, xloc)) return false;
    xloc.hostname = Locs(xloc.hostname);
    for (i = 0; i < CacheList.length; i++)
    {
        if (CacheList[i].URL == xloc) return true;
    }
    return false;
}

/**
    Returns the URL for a certain ID. Result will be false when the ID is no
    longer valid.
*/
function bool getURLbyId(int id, out string URL)
{
    if ((id < 0) || (id > CacheList.length)) return false;
    URL = class'HttpUtil'.static.xUrlToString(CacheList[id].URL, true);
    return false;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Private functions
//
////////////////////////////////////////////////////////////////////////////////

event PreBeginPlay()
{
    local int i;
    CacheCleanup();
    for (i = 0; i < CacheList.length; i++)
    {
        CacheList[i].colidx = -1;
    }
}

/**
    Clean up the cache
*/
protected function CacheCleanup()
{
    local int i, cursize, oldest;
    local HttpCacheObject co;

    if (CacheList.length == 0) return;
    if (iCacheLimit == 0) return;

    cursize = 0;
    for (i = 0; i < CacheList.length; i++)
    {
        cursize += CacheList[i].DataSize;
    }
    while (cursize > iCacheLimit)
    {
        oldest = 0;
        for (i = 1; i < CacheList.length; i++)
        {
            if (CacheList[i].LastUpdate == 0) continue;
            if (CacheList[i].LastUpdate < CacheList[oldest].LastUpdate)
                oldest = i;
        }
        cursize -= CacheList[oldest].DataSize;
        co = getCacheObject(oldest);
        co.ClearConfig();
        // co isn't destroyed because there's no object cleanup anyway,
        // also we can't reuse it because of the PerObjectConfig
        CacheObjectList[CacheList[oldest].colidx] = none;
        CacheList[oldest].DataSize = 0;
        CacheList[oldest].colidx = -1;
        CacheList[oldest].LastUpdate = 0;
    }
    SaveConfig();
}

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

/** find an idx using a hash */
protected function int findCacheRecord(int hash)
{
    local int i;
    for (i = 0; i < CacheList.length; i++)
    {
        if (CacheList[i].Hash == hash) return i;
    }
    return -1;
}

/** get\create a CacheObject */
protected function HttpCacheObject getCacheObject(int idx)
{
    local int lidx;
    local HttpCacheObject co;

    if (idx < 0 || idx >= CacheList.length) return none;
    if ((CacheList[idx].colidx > -1) && (CacheList[idx].colidx < CacheObjectList.length))
    {
        return CacheObjectList[CacheList[idx].colidx];
    }
    lidx = CacheObjectList.length;
    CacheObjectList.length = lidx+1;
    CacheList[idx].colidx = lidx;
    co = new(None, "Cache_h"$string(CacheList[idx].Hash)) HttpCacheObjectClass;
    co.SaveConfig();
    CacheObjectList[lidx] = co;
    log("Created cache object "$co.name);
    return co;
}

protected function DownloadComplete(HttpSock Sender)
{
    local int idx, i;
    local HttpCacheObject co;
    local EDataOrigin origin;

    idx = -1;
    for (i = 0; i < Requests.Length; i++)
    {
        if (Requests[i].Socket == Sender)
        {
            idx = Requests[i].idx;
            Requests[i].idx = -1;
        }
    }
    if (idx == -1)
    {
        //error ?
        return;
    }
    co = getCacheObject(idx);
    co.bBusy = false;
    if (co.LastModification == -1) origin = DO_Initial;
    else if (Sender.LastStatus == 304) origin = DO_Cache;
    else origin = DO_Refresh;

    if (origin != DO_Cache)
    {
        co.Data = Sender.ReturnData;
        co.LastModification = class'HttpUtil'.static.stringToTimestamp(Sender.GetReturnHeader("Last-Modified", "0"), Sender.getTZoffset());
        co.ExpiresOn = class'HttpUtil'.static.stringToTimestamp(Sender.GetReturnHeader("Expires", "0"), Sender.getTZoffset());
        co.ContentType = class'HttpUtil'.static.trim(Sender.GetReturnHeader("Content-Type", ""));
        co.SaveConfig();
        CacheList[idx].DataSize = co.GetSize();
    }
    CacheList[idx].LastUpdate = class'HttpUtil'.static.timestamp(Level.Year, Level.Month, Level.Day, Level.Hour, Level.Minute, Level.Second);
    SaveConfig();
    OnComplete(self, co, origin);
}

protected function DownloadError(HttpSock Sender, string ErrorMessage, optional string Param1, optional string Param2)
{
    local int idx, i;
    local HttpCacheObject co;

    idx = -1;
    for (i = 0; i < Requests.Length; i++)
    {
        if (Requests[i].Socket == Sender)
        {
            idx = Requests[i].idx;
            Requests[i].idx = -1;
        }
    }
    if (idx == -1) return;
    co = getCacheObject(idx);
    co.bBusy = false;
    OnError(self, ErrorMessage, Param1, Param2);
}

protected function DownloadTimeout(HttpSock Sender)
{
    local int idx, i;
    idx = -1;
    for (i = 0; i < Requests.Length; i++)
    {
        if (Requests[i].Socket == Sender)
        {
            idx = Requests[i].idx;
        }
    }
    if (idx == -1) return;
    OnFail(self, idx, CF_Timeout);
}

protected function ResolveFailed(HttpSock Sender, string hostname)
{
    local int idx, i;
    idx = -1;
    for (i = 0; i < Requests.Length; i++)
    {
        if (Requests[i].Socket == Sender)
        {
            idx = Requests[i].idx;
        }
    }
    if (idx == -1) return;
    OnFail(self, idx, CF_ResolveFailed);
}

defaultproperties
{
    HttpSockClass=class'HttpSock'
    HttpCacheObjectClass=class'HttpCacheObject'
    // 512kb
    iCacheLimit=524288
}
