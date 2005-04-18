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

	<!-- $Id: HttpCache.uc,v 1.1 2005/04/18 08:18:22 elmuerte Exp $ -->
*******************************************************************************/

class HttpCache extends Engine.Info config;

/**
    Our HttpSock class, unless it's assigned it will create it's own on the
    first get() request. So if you have a custom HttpSock class set it before
    requesting a document.
*/
var HttpSock HttpSock;
/** handle to the last cache hit  */
var HttpCacheObject LastHit;

//TODO:
var string HttpCacheINI;
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

/** cache list, each entry is an URL */
var protected array<string> CacheList;
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
delegate OnFail(HttpLink Sender, ECacheFailError reason)

// cache hit
delegate OnCacheHit();
// cache fail, get fresh info
delegate OnCacheFail();


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
}

/**
    Returns true when the location is cached
*/
function bool isCached(string location)
{

}

////////////////////////////////////////////////////////////////////////////////
//
//   Private functions
//
////////////////////////////////////////////////////////////////////////////////

event PreBeginPlay()
{
    GetPerObjectNames(HttpCacheINI, string(HttpCacheObjectClass));
}


defaultproperties
{
    HttpCacheINI="HttpCache"
    HttpCacheObjectClass=class'HttpCacheObject'
}
