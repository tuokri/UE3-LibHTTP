/*******************************************************************************
	HttpCookies																	<br />
	Cookie management system. Part of [[LibHTTP]].								<br />
																				<br />
	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP								<br />
																				<br />
	Authors:	Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;	<br />
																				<br />
	Copyright 2003, 2004 Michiel "El Muerte" Hendriks							<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpCookies.uc,v 1.10 2004/09/30 15:58:55 elmuerte Exp $ -->
*******************************************************************************/

class HttpCookies extends Core.Object config parseconfig;

/** cookie entry */
struct HTTPCookie
{
	/** the cookie name */
	var string name;
	/** the current value */
	var string value;
	/** exprises timestamp */
	var int expires;
	/** available to domain */
	var string domain;
	/** path in the domain */
	var string path;
};

/** the cookie data */
var config array<HTTPCookie> CookieData;

/** log verbosity */
var config int iVerbose;

event Created()
{
	local int i;
	local bool bDirty;
	bDirty = false;
	// remove session cookies
	for (i = CookieData.length-1; i > 0; i--)
	{
		if (CookieData[i].Expires <= 0)
		{
			CookieData.remove(i, 1);
			bDirty = true;
			continue;
		}
	}
	if (bDirty) SaveConfig();
}

/**
	Add or overwrite a new cookie
	If value is empty the cookie will be deleted
	If expires is in the past the cookie will be deleted
*/
function AddCookie(string cname, string value, int CurrentTimeStamp, optional int expires, optional string domain, optional string path)
{
	local int i;
	for (i = 0; i < CookieData.length; i++)
	{
		if ((CookieData[i].Name == cname) && (CookieData[i].Domain ~= domain) && (CookieData[i].path == path))
		{
			break; // found old cookie, overwrite it
		}
	}
	if (value == "")
	{
		if (i < CookieData.length) CookieData.remove(i, 1);
		return;
	}
	if ((expires > 0) && (expires < CurrentTimeStamp))
	{
		if (i < CookieData.length) CookieData.remove(i, 1);
		return;
	}
	if (i >= CookieData.length) CookieData.length = i+1;
	CookieData[i].Name = cname;
	CookieData[i].Value = value;
	CookieData[i].Expires = expires;
	CookieData[i].Domain = Domain;
	CookieData[i].Path = Path;
	SaveConfig();
}

/**
	Return the value of a cookie
*/
function string GetCookie(string cname, string domain, string path, optional string defvalue)
{
	local int i;
	for (i = CookieData.Length-1; i > 0 ; i--)
	{
		if (Right(Domain, Len(CookieData[i].Domain)) ~= CookieData[i].Domain) // case insensitive
		{
			if (Left(Path, Len(CookieData[i].Path)) == CookieData[i].Path) // case sensitive
			{
				return CookieData[i].Value;
			}
		}
	}
	return defvalue;
}

/**
	Create a cookie string. TimeStamp should be the real current timestamp (not GMT corrected)
*/
function string GetCookieString(string Domain, string Path, int CurrentTimeStamp)
{
	local int i;
	local string res;
	local bool bDirty;

	bDirty = false;
	for (i = CookieData.Length-1; i >= 0 ; i--)
	{
		if ((CookieData[i].Expires <= CurrentTimeStamp) && (CookieData[i].Expires > 0))
		{
			CookieData.remove(i, 1);
			bDirty = true;
			continue;
		}
		if (Right(Domain, Len(CookieData[i].Domain)) ~= CookieData[i].Domain) // case insensitive
		{
			if (Left(Path, Len(CookieData[i].Path)) == CookieData[i].Path) // case sensitive
			{
				if (res != "") res = res$"; ";
				res = res$CookieData[i].Name$"="$CookieData[i].Value;
			}
		}
	}
	if (bDirty) SaveConfig();
	return res;
}

/**
	Parse a string to a cookie
	rDomain and rPath are use to check if the cookie domain/path are valid
	CurrentTimeStamp is required for adding
	if bAdd is true add it to the list
	returns true when the string is a valid cookie
*/
function bool ParseCookieData(string data, string rDomain, string rPath, optional int CurrentTimeStamp, optional bool bAdd, optional int TZoffset)
{
	local array<string> parts;
	local HTTPCookie c;
	local int i;
	local string n,v;

	if (split(data, ";", parts) > 0)
	{
		if (divide(parts[0], "=", c.Name, c.Value))
		{
			c.Name = class'HttpUtil'.static.trim(c.Name);
			c.Value = class'HttpUtil'.static.trim(c.Value);
			Logf("ParseCookieData - Got cookie", class'HttpUtil'.default.LOGINFO, c.Name, c.Value);
		}
		for (i = 1; i < parts.length; i++)
		{
			if (divide(parts[i], "=", n, v))
			{
				n = class'HttpUtil'.static.trim(n);
				v = class'HttpUtil'.static.trim(v);
				if (n ~= "expires")
				{
					// correct timestamp to our time
					c.Expires = class'HttpUtil'.static.stringToTimestamp(v, TZoffset);
					Logf("ParseCookieData - Got expires", class'HttpUtil'.default.LOGINFO, v, c.Expires);
				}
				else if (n ~= "domain")
				{
					if (!(Right(rDomain, Len(v)) ~= v)) return false;
					c.Domain = v;
					Logf("ParseCookieData - Got valid domain", class'HttpUtil'.default.LOGINFO, v);
				}
				else if (n ~= "path")
				{
					if (!(Left(rPath, Len(v)) == v)) return false;
					c.Path = v;
					Logf("ParseCookieData - Got valid path", class'HttpUtil'.default.LOGINFO, v);
				}
			}
		}
		if (bAdd)
		{
			if (c.Domain == "") c.Domain = rDomain;
			if (c.Path == "") c.Path = class'HttpUtil'.static.dirname(rPath);
			AddCookie(c.Name, c.Value, CurrentTimeStamp, c.Expires, c.Domain, c.Path);
		}
		return (c.Name != "");
	}
	else return false;
}

/* internal routines */

protected function Logf(coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
	if (level <= iVerbose) class'HttpUtil'.static.Logf(Name, Message, Level, Param1, Param2);
}

defaultproperties
{
	iVerbose=-1
}
