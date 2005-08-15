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

	<!-- $Id: HttpCache.uc,v 1.3 2005/08/15 08:50:14 elmuerte Exp $ -->
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
    var string Hash;
    /** index in the CacheObjectList */
    var int idx;
};

/** cache list, each entry is an URL */
var protected config array<CacheInfoRecord> CacheList;

/** the spawned cache objects */
var protected array<HttpCacheObject> CacheObjectList;

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

// failed to complete the request, will be called when everything fails
delegate OnFail(HttpLink Sender, ECacheFailError reason);

// cache hit
delegate OnCacheHit(HttpCache Sender);
// cache fail, get fresh info
delegate OnCacheFail(HttpCache Sender);

/**
	Will be called after the HttpSock instance has been created. Use it to set
	certain variables and delegates for the HttpSock. <br />
	Note: some delegates in HttpSock will always be assigned to this actor.
*/
delegate OnCreateSock(HttpCache Sender);

////////////////////////////////////////////////////////////////////////////////
//
//   Public functions
//
////////////////////////////////////////////////////////////////////////////////

/**
	// TODO:
*/
function bool get(string location)
{
	// TODO:
	return true;
}

/**
	Returns true when the location is cached
*/
function bool isCached(string location)
{
	return false;
}

////////////////////////////////////////////////////////////////////////////////
//
//   Private functions
//
////////////////////////////////////////////////////////////////////////////////

/** return the hash of the URL */
protected function string createHash(string URL)
{
    return "";
}

protected function int findCacheRecord(string hash)
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
    if ((CacheList[idx].idx > -1) && (CacheList[idx].idx < CacheObjectList.length))
    {
        return CacheObjectList[CacheList[idx].idx];
    }
    lidx = CacheObjectList.length;
    CacheList[idx].idx = lidx;
    CacheObjectList[lidx] = new(self, CacheList[idx].Hash) HttpCacheObjectClass;
    return CacheObjectList[lidx];
}

defaultproperties
{
	HttpCacheObjectClass=class'HttpCacheObject'
}
