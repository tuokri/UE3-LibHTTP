/**
	HttpUtil
	Static functions used in all libraries

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: HttpUtil.uc,v 1.1 2003/07/29 14:03:43 elmuerte Exp $
*/

class HttpUtil extends Object;

/**
	Encode special characters, you should not use this function, it's slow and not
	secure, so try to avoid it.
	";", "/", "?", ":", "@", "&", "=", "+", ",", "$" and " "
*/
static function string RawUrlEncode(string instring)
{
	ReplaceChar(instring, ";", "%3B");
	ReplaceChar(instring, "/", "%2F");
	ReplaceChar(instring, "?", "%3F");
	ReplaceChar(instring, ":", "%3A");
	ReplaceChar(instring, "@", "%40");
	ReplaceChar(instring, "&", "%26");
	ReplaceChar(instring, "=", "%3D");
	ReplaceChar(instring, "+", "%2B");
	ReplaceChar(instring, ",", "%2C");
	ReplaceChar(instring, "$", "%24");
	ReplaceChar(instring, " ", "%20");
	return instring;
}

/**
	replace part of a string
*/
static function ReplaceChar(out string instring, string from, string to)
{
	local int i;
	i = InStr(instring, from);
	while (i > 0)
	{
		instring = Left(instring, i)$to$Mid(instring, i+Len(from));
	}
}

/**
	base64 encode an input array
*/
static function array<string> Base64Encode(array<string> indata, out array<string> B64Lookup)
{
	local array<string> result;
	local int i, dl, n;
	local string res;
	local array<byte> inp;
	local array<string> outp;

	if (B64Lookup.length != 64) Base64LookupTable(B64Lookup);

	// convert string to byte array
	for (n = 0; n < indata.length; n++)
	{
		res = indata[n];
		for (i = 0; i < len(res); i++)
		{
			inp[inp.length] = Asc(Mid(res, i, 1));
		}
	}
	dl = inp.length;
	// fix byte array
	if ((dl%3) == 1) 
	{
		inp[inp.length] = 0; 
		inp[inp.length] = 0;
	}
	if ((dl%3) == 2) 
	{
		inp[inp.length] = 0;
	}
	i = 0;
	while (i < dl)
	{
		outp[outp.length] = B64Lookup[(inp[i] >> 2)];
		outp[outp.length] = B64Lookup[((inp[i]&3)<<4) | (inp[i+1]>>4)];
		outp[outp.length] = B64Lookup[((inp[i+1]&15)<<2) | (inp[i+2]>>6)];
		outp[outp.length] = B64Lookup[(inp[i+2]&63)];
		if ((i%57)==54) 
		{
			res = "";
			for (i = 0; i < outp.length; i++)
			{
				res = res$outp[i];
			}
			result[result.length] = res;
			outp.length = 0;
		}
		i += 3;
	}
	// pad result
	if ((dl%3) == 1) 
	{
		outp[outp.length-1] = "="; 
		outp[outp.length-2] = "=";
	}
	if ((dl%3) == 2) 
	{
		outp[outp.length-1] = "=";
	}
	res = "";
	for (i = 0; i < outp.length; i++)
	{
		res = res$outp[i];
	}
	result[result.length] = res;

	return result;
}

/**
	Generated the base 64 lookup table
*/
static function Base64LookupTable(out array<string> LookupTable)
{
	local int i;
	for (i = 0; i < 26; i++)
	{
		LookupTable[i] = Chr(i+65);
	}
	for (i = 0; i < 26; i++)
	{
		LookupTable[i+26] = Chr(i+97);
	}
	for (i = 0; i < 10; i++)
	{
		LookupTable[i+52] = Chr(i+48);
	}
	LookupTable[62] = "+";
	LookupTable[63] = "/";
}

/**
	Create a UNIX timestamp
*/
static final function int timestamp(int year, int mon, int day, int hour, int min, int sec)
{
	mon -= 2;
	if (mon <= 0) {	/* 1..12 -> 11,12,1..10 */
		mon += 12;	/* Puts Feb last since it has leap day */
		year -= 1;
	}
	return (((
	    (year/4 - year/100 + year/400 + 367*mon/12 + day) +
	      year*365 - 719499
	    )*24 + (hour-1) /* now have hours */
	   )*60 + min  /* now have minutes */
	  )*60 + sec; /* finally seconds */
}