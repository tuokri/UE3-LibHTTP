/**
	HttpCookies
	Cookie management system. Part of [[LibHTTP]].

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: HttpCookies.uc,v 1.2 2003/07/29 14:13:21 elmuerte Exp $
*/

class HttpCookies extends Object config;

struct HTTPCookie
{
	var string name;
	var string value;
	var int expires;
	var string domain;
	var string path;
};

/** the cookie data */
var config array<HTTPCookie> CookieData;

/**
	Clean up cookie data
*/
event Created()
{
	local int i;
	for (i = CookieData.length-1; i > 0; i--)
	{
		if (CookieData[i].Expires <= 0)
		{
			CookieData.remove(i, 1);
			continue;
		}
	}
	SaveConfig();
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
	CookieData[i].Name = cname;
	CookieData[i].Value = value;
	CookieData[i].Expires = expires;
	CookieData[i].Domain = Domain;
	CookieData[i].Path = Path;
}

/**
	Create a cookie string
*/
function string GetCookieString(string Domain, string Path, int CurrentTimeStamp)
{
	local int i;
	local string res;
	for (i = CookieData.Length-1; i > 0 ; i--)
	{
		if ((CookieData[i].Expires <= CurrentTimeStamp) && (CookieData[i].Expires > 0))
		{
			CookieData.remove(i, 1);
			continue;
		}
		if (Right(Domain, Len(CookieData[i].Domain)) ~= CookieData[i].Domain) // case insensitive
		{
			if (Left(Path, Len(CookieData[i].Path)) == CookieData[i].Path) // case sensitive
			{
				if (res != "") res = res$";";
				res = res@CookieData[i].Name$"="$CookieData[i].Value;
			}
		}
	}
	return res;
}
