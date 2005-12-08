/*******************************************************************************
    HttpCacheObject                                                             <br />
    Physical storage of the cached data.
                                                                                <br />
    Dcoumentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2005 Michiel "El Muerte" Hendriks                                 <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense                <br />

    <!-- $Id: HttpCacheObject.uc,v 1.4 2005/12/08 18:53:01 elmuerte Exp $ -->
*******************************************************************************/

class HttpCacheObject extends Core.Object
    PerObjectConfig
    config(HttpCache);

/** the request URL */
var config string URL;
/** last modification timestamp */
var config int LastModification;
/** timestamp this content expires, if provided by the server */
var config int ExpiresOn;
/** the content mime type */
var config string ContentType;
/** the content body */
var config array<string> Data;

/** this object is currently being refreshed */
var bool bBusy;

function int GetSize()
{
    local int size, i;
    size = 0;
    for (i = 0; i < Data.length; i++)
    {
        size += Len(data[i]);
    }
    return size;
}

defaultproperties
{
    ExpiresOn=-1
    LastModification=-1
}