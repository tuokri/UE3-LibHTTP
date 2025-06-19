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
    HttpUtil                                                                    <br />
    Miscellaneous static functions. Part of [[LibHTTP]].                        <br />
    Contains various algorithms, under which [[Base64]] encoding and [[MD5]]
    hash generation.                                                            <br />
    [[MD5]] code by Petr Jelinek ( http://wiki.beyondunreal.com/wiki/MD5 )      <br />
                                                                                <br />
    Documentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2003, 2004 Michiel "El Muerte" Hendriks                           <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense

    <!-- $Id: HttpUtil.uc,v 1.21 2005/12/13 11:36:08 elmuerte Exp $ -->
*******************************************************************************/

class HttpUtil extends Core.Object;

/* log levels */
var const int LOGERR;
var const int LOGWARN;
var const int LOGINFO;
var const int LOGDATA;

/** Month names to use for date string generation */
var const string MonthNames[13];
/** names of the days, 0 = sunday */
var const string DayNamesLong[7], DayNamesShort[7];
/** days offsets for each Month*/
var const int MonthOffset[13], MonthOffsetLeap[13];

struct DateTime
{
    var int Year;
    var int Month;
    var int Day;
    var int WeekDay;
    var int Hour;
    var int Minute;
    var int Second;
};

/** MD5 Context */
struct MD5_CTX
{
    /** State (ABCD) */
    var array<int> State;
    /** number of bits, modulo 2^64 (lsb first) */
    var array<int> Count;
    /** Input Buffer */
    var array<byte> Buffer;
};

/** a better URL structure that contains all elements */
struct xURL
{
    /**
        protocol used, like http:/ /, https:/ /, ftp:/ /. But without the ':/ /'
        part. (ignore the space between the two slashes, it's required because of
        a bug in UE2)
    */
    var string protocol;
    /** username that was provided in the URL */
    var string username;
    /** possible password that was in the url */
    var string password;
    /** the hostname */
    var string hostname;
    /** the port number specified in the URL */
    var int port;
    /** the location field, all from the hostname up to the query or hash string, includes leading / */
    var string location;
    /** the part after the ?, without the leading ? */
    var string query;
    /** the part after the #, without the leading # */
    var string hash;
};

/** URL delimiter */
const TOKEN_PATH = "/";
/** URL delimiter */
const TOKEN_HASH = "#";
/** URL delimiter */
const TOKEN_QUERY = "?";
/** URL delimiter; to seperate protocol from the rest */
const TOKEN_PROTOCOL = "://";
/** URL delimiter */
const TOKEN_USER = "@";
/** URL delimiter; to seperate the user and pass from the url */
const TOKEN_USERPASS = ":";
/** URL delimiter */
const TOKEN_PORT = ":";

/** URL escape token */
const URL_ESCAPE = "%";

/**
    Encode special characters, you should not use this function, it's slow and not
    secure, so try to avoid it.
    ";", "/", "?", ":", "@", "&", "=", "+", ",", "$" and " "
*/
static final function string RawUrlEncode(string instring)
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
    This will decode URL encoded elements. If bIgnorePlus is set to true '+' will
    not be changed to a space
*/
static final function string RawUrlDecode(string instring, optional bool bIgnorePlus)
{
    local int i;
    local string char;

    if (!bIgnorePlus) ReplaceChar(instring, "+", " ");
    i = InStr(instring, URL_ESCAPE);
    while (i > -1)
    {
        char = mid(instring, i+1, 2);
        char = chr(HexToDec(char));
        if (char == "%") char = chr(1);
        instring = Left(instring, i)$char$Mid(instring, i+3);
        i = InStr(instring, URL_ESCAPE);
    }
    ReplaceChar(instring, chr(1), URL_ESCAPE); // % was replace with \1
    return instring;
}

/** parses the inURL to an xURL structure, return true when succesful */
static final function bool parseUrl(string inURL, out xURL outURL)
{
    local int i, j;
    i = InStr(inURL, TOKEN_PROTOCOL);
    if (i == -1) return false;
    if (i == 0) return false; // empty protocol
    outURL.protocol = Left(inURL, i);
    inURL = mid(inURL, i+Len(TOKEN_PROTOCOL));
    i = InStr(inURL, TOKEN_USER);
    if (i == -1)
    {
        outURL.username = "";
        outURL.password = "";
    }
    else {
        outURL.username = Left(inURL, i);
        inURL = mid(inURL, i+Len(TOKEN_USER));
        i = InStr(outURL.username, TOKEN_USERPASS);
        if (i == -1)
        {
            outURL.password = "";
        }
        else {
            outURL.password = Mid(outURL.username, i+Len(TOKEN_USERPASS));
            outURL.username = Left(outURL.username, i);
        }
        outURL.username = RawUrlDecode(outURL.username);
        outURL.password = RawUrlDecode(outURL.password);
    }
    if (inURL == "") return false;
    i = InStr(inURL, TOKEN_PATH);
    if (i == -1) // just protocol://hostname
    {
        outURL.hostname = inURL;
        outURL.hash = "";
        outURL.query = "";
        outURL.location = TOKEN_PATH;
        return true;
    }
    if (i == 0) return false; // e.g. http:///, also traps file:/// but we don't give a crap about that
    outURL.hostname = Left(inURL, i);
    inURL = mid(inURL, i); // now it contains location(\?query)?(#hash)?
    i = InStr(outURL.hostname, TOKEN_PORT);
    if (i == 0) return false; // http://:80/ !?
    outURL.port = -1;
    if (i > 0)
    {
        j = int(mid(outURL.hostname, i+1));
        if (outURL.port == 0) // invalid port no
        {
            return false;
        }
        else if (j != getPortByProtocol(outURL.protocol)) {
            outURL.port = j;
        }
        outURL.hostname = Left(outURL.hostname, i);
    }
    i = InStr(inURL, TOKEN_HASH);
    if (i != -1)
    {
        outURL.hash = Mid(inURL, i+Len(TOKEN_HASH));
        inURL = left(inURL, i);
    }
    else outURL.hash = "";
    i = InStr(inURL, TOKEN_QUERY);
    if (i != -1)
    {
        outURL.query = Mid(inURL, i+Len(TOKEN_QUERY));
        inURL = left(inURL, i);
    }
    else outURL.query = "";
    outURL.location = inURL;
    return true;
}

/** converts a xURL to a string. bIncludePassword defaults to false */
static final function string xURLtoString(xURL inURL, optional bool bIncludePassword = False)
{
    local string r;
    r = inURL.protocol$TOKEN_PROTOCOL;
    if (inURL.username != "")
    {
        r $= RawUrlEncode(inURL.username);
        if (inURL.password != "" && bIncludePassword) r $= TOKEN_USERPASS$RawUrlEncode(inURL.password);
        r $= TOKEN_USER;
    }
    r $= inURL.hostname;
    if (inURL.port != -1) r $= TOKEN_PORT$string(inURL.port);
    if (inURL.location == "") inURL.location = TOKEN_PATH;
    r $= inURL.location;
    if (inURL.query != "") r $= TOKEN_QUERY$inURL.query;
    if (inURL.hash != "") r $= TOKEN_HASH$inURL.hash;
    return r;
}

/** convert a xURL to a location string, just the location+query+hash */
static final function string xURLtoLocation(const out xURL inURL, optional bool bIncludePassword)
{
    local string r;
    r = inURL.location;
    if (inURL.query != "") r $= TOKEN_QUERY$inURL.query;
    if (inURL.hash != "") r $= TOKEN_HASH$inURL.hash;
    return r;
}

/** return the default port based on the protocol */
static final function int getPortByProtocol(string protocol)
{
    switch (protocol)
    {
        /*
        case "ftp":     return 21;
        case "ssh":     return 22;
        case "telnet":  return 23;
        case "gopher":  return 70;
        */
        case "http":    return 80;
        case "https":   return 443;
    }
    return 0;
}

/**
    replace part of a string
*/
static final function ReplaceChar(out string instring, string from, string to)
{
    //#ifdef UE2
    local int i;
    local string Src;
    Src = instring;
    instring = "";
    i = InStr(Src, from);
    while (i > -1)
    {
        instring = instring$Left(Src, i)$to;
        Src = Mid(Src, i+Len(from));
        i = InStr(Src, from);
    }
    instring = instring$Src;
    //#endif
    //#ifdef UE5
    //instring = repl(instring, from, to);
    //#endif
}

/**
    base64 encode an Input array
*/
static final function array<string> Base64Encode(const out array<string> InData, out array<string> B64Lookup)
{
    local array<string> Result;
    local int i, dl, n;
    local string res;
    local array<byte> inp;
    local array<string> outp;

    if (B64Lookup.length != 64) Base64EncodeLookupTable(B64Lookup);

    // convert string to byte array
    for (n = 0; n < InData.length; n++)
    {
        res = InData[n];
        outp.length = 0;
        inp.length = 0;
        for (i = 0; i < Len(res); i++)
        {
            inp[inp.length] = Asc(Mid(res, i, 1));
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
            i += 3;
        }
        // pad Result
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
        Result[Result.length] = res;
    }

    return Result;
}

/**
    Decode a base64 encoded string
*/
static final function array<string> Base64Decode(const out array<string> InData)
{
    local array<string> Result;
    local int i, dl, n, padded;
    local string res;
    local array<byte> inp;
    local array<string> outp;

    // convert string to byte array
    for (n = 0; n < InData.length; n++)
    {
        res = InData[n];
        outp.length = 0;
        inp.length = 0;
        padded = 0;
        for (i = 0; i < Len(res); i++)
        {
            dl = Asc(Mid(res, i, 1));
            // convert base64 ascii to base64 Index
            if ((dl >= 65) && (dl <= 90)) dl -= 65; // cap alpha
            else if ((dl >= 97) && (dl <= 122)) dl -= 71; // low alpha
            else if ((dl >= 48) && (dl <= 57)) dl += 4; // digits
            else if (dl == 43) dl = 62;
            else if (dl == 47) dl = 63;
            else if (dl == 61) padded++;
            inp[inp.length] = dl;
        }

        dl = inp.length;
        i = 0;
        while (i < dl)
        {
            outp[outp.length] = Chr((inp[i] << 2) | (inp[i+1] >> 4));
            outp[outp.length] = Chr(((inp[i+1]&15)<<4) | (inp[i+2]>>2));
            outp[outp.length] = Chr(((inp[i+2]&3)<<6) | (inp[i+3]));
            i += 4;
        }
        outp.length = outp.length-padded;

        res = "";
        for (i = 0; i < outp.length; i++)
        {
            res = res$outp[i];
        }
        Result[Result.length] = res;
    }

    return Result;
}

/**
    Generate the base 64 encode lookup table
*/
static final function Base64EncodeLookupTable(out array<string> LookupTable)
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
    Create a UNIX timestamp. <br />
    Warning: Assumes info is passed in GMT. So make sure you correct the timezone
    if you are going to send a timestamp generated with this function to an other
    server.
*/
static final function int UnixTimestamp(int Year, int mon, int Day, int Hour, int min, int sec)
{
    /*
        Origin of the algorithm below:
        Linux Kernel <time.h>
    */
    mon -= 2;
    if (mon <= 0) {    /* 1..12 -> 11,12,1..10 */
        mon += 12;    /* Puts Feb last since it has leap Day */
        Year -= 1;
    }
    return (((
        (Year/4 - Year/100 + Year/400 + 367*mon/12 + Day) +
          Year*365 - 719499
        )*24 + Hour /* now have hours */
       )*60 + min  /* now have minutes */
      )*60 + sec; /* finally seconds */
}

/**
    Parse a string to a timestamp
    The date string is formatted as: Wdy, DD-Mon-YYYY HH:MM:SS GMT
    TZOffset is the local offset to GMT
*/
static final function int stringToTimestamp(string DateString, optional int TZOffset)
{
    local array<string> Data, DatePart, TimePart;
    local int i;
    local float TZOff;

    DateString = Trim(DateString);

    ParseStringIntoArray(DateString, Data, " ", false);

    if (Data.length == 6) // date is in spaced format
    {
        Data[1] = Data[1]$"-"$Data[2]$"-"$Data[3];
        Data[2] = Data[4];
        Data[3] = Data[5];
        Data.length = 4;
    }
    if (Data.length == 4)
    {
        ParseStringIntoArray(Data[1], DatePart, "-", False);
        if (DatePart.length != 3) return 0;

        ParseStringIntoArray(Data[2], TimePart, "-", False);
        if (DatePart.length != 3) return 0;

        // find Month offset
        for (i = 1; i < ArrayCount(default.MonthNames); i++)
        {
            if (default.MonthNames[i] ~= DatePart[1])
            {
                DatePart[1] = string(i);
                break;
            }
        }
        if (Len(DatePart[2]) == 2) DatePart[2] = "20"$DatePart[2];
        TZOff = TZtoOffset(Data[3]);
        return UnixTimestamp(int(DatePart[2]), int(DatePart[1]), int(DatePart[0]),
            int(TimePart[0])+TZOffset+int(TZOff), int(TimePart[1])+(TZOff%1*60), int(TimePart[2]));
    }
    return 0;
}

/** Returns if Year is a leap Year */
static final function bool IsLeapYear(int Year)
{
    return (Year) % 4 == 0 && ((Year) % 100 != 0 || (Year) % 400 == 0);
}

/** returns the number of days in a Year */
static final function int DaysInYear(int Year)
{
    const DAYS_PER_YEAR = 365;
    const DAYS_PER_LEAP_YEAR = 366;
    if (IsLeapYear(Year)) return DAYS_PER_LEAP_YEAR;
    else return DAYS_PER_YEAR;
}

static final function int LeapsThruEndOf(int y)
{
    return ((y / 4) - (y / 100) + (y / 400));
}

// /** the float % operator is broken for our needs (numbers >2^24) */
// static final operator(18) int % ( int x, int y )
// {
//     return x-(x/y*y);
// }

/** converts a timestamp to a DateTime record */
static final function DateTime TimestampToDatetime(int timestamp)
{
    /*
        Origin of the algorithm below:
        GNU C Library <offtime.c>
    */
    const SECS_PER_DAY = 86400;
    const SECS_PER_HOUR = 3600;
    local int days, rem, yg;
    local DateTime dt;

    days = timestamp / SECS_PER_DAY;
    rem = timestamp % SECS_PER_DAY;
    while (rem < 0)
    {
        rem += SECS_PER_DAY;
        --days;
    }
    while (rem >= SECS_PER_DAY)
    {
        rem -= SECS_PER_DAY;
        ++days;
    }
    dt.Hour = rem / SECS_PER_HOUR;
    rem = rem % SECS_PER_HOUR;
    dt.Minute = rem / 60;
      dt.Second  = rem % 60;
      /* January 1, 1970 was a Thursday.  */
    dt.WeekDay = (4 + days) % 7;
    if (dt.WeekDay < 0) dt.WeekDay += 7;
     dt.Year = 1970;

     while (days < 0 || days >= DaysInYear(dt.Year))
    {
        /* Guess a corrected Year, assuming 365 days per Year.  */
        yg = dt.Year + days / DAYS_PER_YEAR - int(days % DAYS_PER_YEAR < 0);
        /* Adjust DAYS and Y to match the guessed Year.  */
        days -= ((yg - dt.Year) * DAYS_PER_YEAR + LeapsThruEndOf(yg - 1) - LeapsThruEndOf(dt.Year - 1));
        dt.Year = yg;
    }
    if (IsLeapYear(dt.Year))
    {
        for (yg = 11; days < default.MonthOffsetLeap[yg]; --yg) continue;
        dt.Month = yg;
        days -= default.MonthOffsetLeap[yg];
    }
    else {
        for (yg = 11; days < default.MonthOffset[yg]; --yg) continue;
        dt.Month = yg;
        days -= default.MonthOffset[yg];
    }
    dt.Day = days + 1;
    return dt;
}

/**
    convert a timestamp into a string. <br />
    Format can be one of the following strings: <br />
    "822", "1123" : RFC 822, updated by RFC 1123 (default), timezone is the TZ CODE <br />
    "850", "1036" : RFC 850, obsoleted by RFC 1036, timezone is the TZ CODE  <br />
    "2822" : RFC 2822, timezone is a +0000 like string <br />
    "asctime": ANSI C's asctime() format, timezone is an integer that will increment the Hour
*/
static final function string timestampToString(int timestamp, optional string Timezone, optional string format)
{
    local DateTime dt;
    dt = TimestampToDatetime(timestamp);
    switch (format)
    {
        case "850":
        case "1036":
            if (Timezone == "") Timezone = "GMT";
            format = default.DayNamesLong[dt.WeekDay]$", "$Right("0"$dt.Day, 2)$"-"$default.MonthNames[dt.Month+1]$"-"$dt.Year@Right("0"$dt.Hour, 2)$":"$Right("0"$dt.Minute, 2)$":"$Right("0"$dt.Second, 2)@Timezone;
            return format;
        case "asctime":
            dt.Hour += int(Timezone);
            dt.Minute += int(float(Timezone) % 1 * 60);
            format = default.DayNamesShort[dt.WeekDay]@default.MonthNames[dt.Month+1]@Right(" "$dt.Day, 2)@Right("0"$dt.Hour, 2)$":"$Right("0"$dt.Minute, 2)$":"$Right("0"$dt.Second, 2)@dt.Year;
            return format;
        case "2822":
            if (Timezone == "") Timezone = "+0000";
            format = default.DayNamesShort[dt.WeekDay]$", "$Right("0"$dt.Day, 2)@default.MonthNames[dt.Month+1]@dt.Year@Right("0"$dt.Hour, 2)$":"$Right("0"$dt.Minute, 2)$":"$Right("0"$dt.Second, 2)@Timezone;
            return format;
        // case: 822
        // case: 1123
        default:
            if (Timezone == "") Timezone = "GMT";
            format = default.DayNamesShort[dt.WeekDay]$", "$Right("0"$dt.Day, 2)@default.MonthNames[dt.Month+1]@dt.Year@Right("0"$dt.Hour, 2)$":"$Right("0"$dt.Minute, 2)$":"$Right("0"$dt.Second, 2)@Timezone;
            return format;
    }
}

/**
    Converts a timezone code to an offset.
*/
static final function float TZtoOffset(string TZ)
{
    TZ = Caps(TZ);
    switch (TZ)
    {
        case "GMT":         // Greenwich Mean
        case "UT":          // Universal (Coordinated)
        case "UTC":
        case "WET":         // Western European
            return 0;
        case "WAT":         // West Africa
        case "AT":          // Azores
            return -1;
        //case "BST":       // Brazil Standard
        //case "GST":       // Greenland Standard
        //case "NFT":       // Newfoundland
        //case "NST":       // ewfoundland Standard
        //    return -3;
        case "AST":         // Atlantic Standard
            return -4;
        case "EST":         // Eastern Standard
            return -5;
        case "CST":         // Central Standard
            return -6;
        case "MST":         // Mountain Standard
            return -7;
        case "PST":         // acific Standard
            return -8;
        case "YST":         // Yukon Standard
            return -9;
        case "HST":         // Hawaii Standard
        case "CAT":         // Central Alaska
        case "AHST":        // Alaska-Hawaii Standard
            return -10;
        case "NT":          // Nome
            return -11;
        case "IDLW":        // International Date Line West
            return -12;
        case "CET":         // Central European
        case "MET":         // Middle European
        case "MEWT":        // Middle European Winter
        case "SWT":         // Swedish Winter
        case "FWT":         // French Winter
            return 1;
        case "CEST":        // Central European Summer
        case "EET":         // Eastern Europe, USSR Zone 1
            return 2;
        case "BT":          // Baghdad, USSR Zone 2
            return 3;
        //case "IT":        // Iran
        //    return 3.5;
        case "ZP4":         // USSR Zone 3
            return 4;
        case "ZP5":         // USSR Zone 4
            return 5;
        case "IST":         // Indian Standard
            return 5.5;
        case "ZP6":         // USSR Zone 5
            return 6;
        //case "NST":       // North Sumatra
        //    return 6.5;
        //case "SST":       // South Sumatra, USSR Zone 6
        case "WAST":        // West Australian Standard
            return 7;
        //case "JT":        // ava (3pm in Cronusland!)
        //    return 7.5;
        case "CCT":         // China Coast, USSR Zone 7
            return 8;
        case "JST":         // Japan Standard, USSR Zone 8
            return 9;
        //case "CAST":      // Central Australian Standard
        //    return 9.5;
        case "EAST":        // Eastern Australian Standard
        case "GST":         // Guam Standard, USSR Zone 9
            return 10;
        case "NZT":         // New Zealand
        case "NZST":        // New Zealand Standard
        case "IDLE":        // International Date Line East
            return 12;

    }
    return int(tz);

}

/** Trim leading and trailing spaces */
static final function string Trim(coerce string S)
{
    while (Left(S, 1) == " ") S = Right(S, Len(S) - 1);
        while (Right(S, 1) == " ") S = Left(S, Len(S) - 1);
    return S;
}

/** Write a log entry */
static final function Logf(name Comp, coerce string message, optional int level, optional coerce string Param1, optional coerce string Param2)
{
    message = message @ chr(9) @ param1 @ chr(9) @ Param2;
    if (Len(message) > 512)
    {
        message = Left(message, 512) @ "..."; // Trim message (crash protection)
    }

    `log(Comp $ "[" $ level $ "] :" @ message,, 'LibHTTP');
}

/** get the dirname of a filename, with traling slash */
static final function string dirname(string filename)
{
    local array<string> parts;
    local int i;

    ParseStringIntoArray(filename, parts, "/", False);

    filename = "";
    for (i = 0; i < parts.length-1; i++)
    {
        filename = filename$parts[i]$"/";
    }
    return filename;
}

/** get the base filename */
static final function string basename(string filename)
{
    local array<string> parts;

    ParseStringIntoArray(filename, parts, "/", false);
    if (parts.length > 0)
    {
        return parts[parts.length-1];
    }
    return filename;
}

/** convert a hexadecimal number to the integer counterpart */
static final function int HexToDec(string hexcode)
{
    local int res, i, cur;

    res = 0;
    hexcode = Caps(hexcode);
    for (i = 0; i < Len(hexcode); i++)
    {
        cur = Asc(Mid(hexcode, i, 1));
        if (cur == 32) return res;
        cur -= 48; // 0 = ascii 30
        if (cur > 9) cur -= 7;
        if ((cur > 15) || (cur < 0)) return -1; // not possible
        res = res << 4;
        res += cur;
    }
    return res;
}

/** return the description of a HTTP response code*/
static final function string HTTPResponseCode(int code)
{
    switch (code)
    {
        case 100: return "continue";
        case 101: return "Switching Protocols";
        case 200: return "OK";
        case 201: return "Created";
        case 202: return "Accepted";
        case 203: return "Non-Authoritative Information";
        case 204: return "No Content";
        case 205: return "Reset Content";
        case 206: return "Partial Content";
        case 300: return "Multiple Choices";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 303: return "See Other";
        case 304: return "Not Modified";
        case 305: return "Use Proxy";
        case 307: return "Temporary Redirect";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 402: return "Payment Required";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 406: return "Not Acceptable";
        case 407: return "Proxy Authentication Required";
        case 408: return "Request Time-out";
        case 409: return "Conflict";
        case 410: return "Gone";
        case 411: return "Length Required";
        case 412: return "Precondition Failed";
        case 413: return "Request Entity Too Large";
        case 414: return "Request-URI Too Large";
        case 415: return "Unsupported Media Type";
        case 416: return "Requested range not satisfiable";
        case 417: return "Expectation Failed";
        case 500: return "Internal Server Error";
        case 501: return "Not Implemented";
        case 502: return "Bad Gateway";
        case 503: return "Service Unavailable";
        case 504: return "Gateway Time-out";
    }
    return "";
}

/**
    Split a string with quotes, quotes may appear anywhere in the string, escape
    the quote char with a \ to use a literal. <br />
    Quotes are removed from the Result, and escaped quotes are used as normal
    quotes.
*/
static function int AdvSplit(string Input, string Delim, out array<string> Elm, optional string QuoteChar)
{
    local int di, qi;
    local int DelimLen, QuoteLen;
    local string Tmp;

    // if quotechar is empty use the faster split method
    if (QuoteChar == "")
    {
        ParseStringIntoArray(Input, Elm, Delim, False);
        return Elm.Length;
    }

    DelimLen = Len(Delim);
    QuoteLen = Len(QuoteChar);
    ReplaceChar(Input, "\\"$QuoteChar, chr(1)); // replace escaped quotes
    while (Len(Input) > 0)
    {
        di = InStr(Input, Delim);
        qi = InStr(Input, QuoteChar);

        if (di == -1 && qi == -1) // neither found
        {
            ReplaceChar(Input, chr(1), QuoteChar);
            Elm[Elm.length] = Input;
            Input = "";
        }
        else if ((di < qi) && (di != -1) || (qi == -1)) // Delim before a quotechar
        {
            Tmp = Left(Input, di);
            ReplaceChar(Tmp, chr(1), QuoteChar);
            Elm[Elm.length] = Tmp;
            Input = Mid(Input, di+DelimLen);
        }
        else {
            Tmp = "";
            // everything before the quote
            if (qi > 0)    Tmp = Left(Input, qi);
            Input = mid(Input, qi+QuoteLen);
            // up to the next quote
            qi = InStr(Input, QuoteChar);
            if (qi == -1) qi = Len(Input);
            Tmp = Tmp$Left(Input, qi);
            Input = mid(Input, qi+QuoteLen);
            // everything after the quote till Delim
            di = InStr(Input, Delim);
            if (di > -1)
            {
                Tmp = Tmp$Left(Input, di);
                Input = mid(Input, di+DelimLen);
            }
            ReplaceChar(Tmp, chr(1), QuoteChar);
            Elm[Elm.length] = Tmp;
        }
    }
    return Elm.length;
}

/*
    UnrealScript MD5 routine by Petr Jelinek (PJMODOS)
    http://wiki.beyondunreal.com/wiki/MD5
    Code used for the Digest authentication method.
    One change has been made: the md5 returned is lowercase
*/

/** return the MD5 of the Input string */
static final function string MD5String (string str)
{
    local MD5_CTX Context;
    local array<byte> Digest;
    local string Hex;
    local int i;

    MD5Init (Context);
    MD5Update (Context, str, Len(str));
    Digest.Length = 16;
    MD5Final (Digest, Context);

    for (i = 0; i < 16; i++)
        Hex = Hex $ DecToHex(Digest[i], 1);

    return Hex;
}

/**
    Return the MD5 of the Input string array.
    Concat is added after each line.
*/
static final function string MD5StringArray(const out array<string> StrArray, optional string Concat)
{
    local MD5_CTX Context;
    local array<byte> Digest;
    local string Hex, str;
    local int i;

    MD5Init (Context);
    for (i = 0; i < StrArray.length; i++)
    {
        str = StrArray[i]$concat;
        MD5Update (Context, str, Len(str));
    }
    Digest.Length = 16;
    MD5Final (Digest, Context);

    for (i = 0; i < 16; i++)
        Hex = Hex $ DecToHex(Digest[i], 1);

    return Hex;
}

/** initialize the MD5 Context */
static final function MD5Init(out MD5_CTX Context)
{
    Context.Count.Length = 2;
    Context.Count[0] = 0;
    Context.Count[1] = 0;
    Context.State.Length = 4;
    Context.State[0] = 0x67452301;
    Context.State[1] = 0xefcdab89;
    Context.State[2] = 0x98badcfe;
    Context.State[3] = 0x10325476;
    Context.Buffer.Length = 64;
}

static final function MD5Transform(out array<int> Buf, const out array<byte> Block)
{
    local int A,B,C,D;
    local array<int> x;

    A = Buf[0];
    B = Buf[1];
    C = Buf[2];
    D = Buf[3];

    x.Length = 16;

    MD5Decode (x, Block, 64);

    /* Round 1 */
    FF (a, b, c, d, x[ 0],  7, 0xd76aa478); /* 1 */
    FF (d, a, b, c, x[ 1], 12, 0xe8c7b756); /* 2 */
    FF (c, d, a, b, x[ 2], 17, 0x242070db); /* 3 */
    FF (b, c, d, a, x[ 3], 22, 0xc1bdceee); /* 4 */
    FF (a, b, c, d, x[ 4],  7, 0xf57c0faf); /* 5 */
    FF (d, a, b, c, x[ 5], 12, 0x4787c62a); /* 6 */
    FF (c, d, a, b, x[ 6], 17, 0xa8304613); /* 7 */
    FF (b, c, d, a, x[ 7], 22, 0xfd469501); /* 8 */
    FF (a, b, c, d, x[ 8],  7, 0x698098d8); /* 9 */
    FF (d, a, b, c, x[ 9], 12, 0x8b44f7af); /* 10 */
    FF (c, d, a, b, x[10], 17, 0xffff5bb1); /* 11 */
    FF (b, c, d, a, x[11], 22, 0x895cd7be); /* 12 */
    FF (a, b, c, d, x[12],  7, 0x6b901122); /* 13 */
    FF (d, a, b, c, x[13], 12, 0xfd987193); /* 14 */
    FF (c, d, a, b, x[14], 17, 0xa679438e); /* 15 */
    FF (b, c, d, a, x[15], 22, 0x49b40821); /* 16 */

    /* Round 2 */
    GG (a, b, c, d, x[ 1],  5, 0xf61e2562); /* 17 */
    GG (d, a, b, c, x[ 6],  9, 0xc040b340); /* 18 */
    GG (c, d, a, b, x[11], 14, 0x265e5a51); /* 19 */
    GG (b, c, d, a, x[ 0], 20, 0xe9b6c7aa); /* 20 */
    GG (a, b, c, d, x[ 5],  5, 0xd62f105d); /* 21 */
    GG (d, a, b, c, x[10],  9,  0x2441453); /* 22 */
    GG (c, d, a, b, x[15], 14, 0xd8a1e681); /* 23 */
    GG (b, c, d, a, x[ 4], 20, 0xe7d3fbc8); /* 24 */
    GG (a, b, c, d, x[ 9],  5, 0x21e1cde6); /* 25 */
    GG (d, a, b, c, x[14],  9, 0xc33707d6); /* 26 */
    GG (c, d, a, b, x[ 3], 14, 0xf4d50d87); /* 27 */
    GG (b, c, d, a, x[ 8], 20, 0x455a14ed); /* 28 */
    GG (a, b, c, d, x[13],  5, 0xa9e3e905); /* 29 */
    GG (d, a, b, c, x[ 2],  9, 0xfcefa3f8); /* 30 */
    GG (c, d, a, b, x[ 7], 14, 0x676f02d9); /* 31 */
    GG (b, c, d, a, x[12], 20, 0x8d2a4c8a); /* 32 */

    /* Round 3 */
    HH (a, b, c, d, x[ 5],  4, 0xfffa3942); /* 33 */
    HH (d, a, b, c, x[ 8], 11, 0x8771f681); /* 34 */
    HH (c, d, a, b, x[11], 16, 0x6d9d6122); /* 35 */
    HH (b, c, d, a, x[14], 23, 0xfde5380c); /* 36 */
    HH (a, b, c, d, x[ 1],  4, 0xa4beea44); /* 37 */
    HH (d, a, b, c, x[ 4], 11, 0x4bdecfa9); /* 38 */
    HH (c, d, a, b, x[ 7], 16, 0xf6bb4b60); /* 39 */
    HH (b, c, d, a, x[10], 23, 0xbebfbc70); /* 40 */
    HH (a, b, c, d, x[13],  4, 0x289b7ec6); /* 41 */
    HH (d, a, b, c, x[ 0], 11, 0xeaa127fa); /* 42 */
    HH (c, d, a, b, x[ 3], 16, 0xd4ef3085); /* 43 */
    HH (b, c, d, a, x[ 6], 23,  0x4881d05); /* 44 */
    HH (a, b, c, d, x[ 9],  4, 0xd9d4d039); /* 45 */
    HH (d, a, b, c, x[12], 11, 0xe6db99e5); /* 46 */
    HH (c, d, a, b, x[15], 16, 0x1fa27cf8); /* 47 */
    HH (b, c, d, a, x[ 2], 23, 0xc4ac5665); /* 48 */

    /* Round 4 */
    II (a, b, c, d, x[ 0],  6, 0xf4292244); /* 49 */
    II (d, a, b, c, x[ 7], 10, 0x432aff97); /* 50 */
    II (c, d, a, b, x[14], 15, 0xab9423a7); /* 51 */
    II (b, c, d, a, x[ 5], 21, 0xfc93a039); /* 52 */
    II (a, b, c, d, x[12],  6, 0x655b59c3); /* 53 */
    II (d, a, b, c, x[ 3], 10, 0x8f0ccc92); /* 54 */
    II (c, d, a, b, x[10], 15, 0xffeff47d); /* 55 */
    II (b, c, d, a, x[ 1], 21, 0x85845dd1); /* 56 */
    II (a, b, c, d, x[ 8],  6, 0x6fa87e4f); /* 57 */
    II (d, a, b, c, x[15], 10, 0xfe2ce6e0); /* 58 */
    II (c, d, a, b, x[ 6], 15, 0xa3014314); /* 59 */
    II (b, c, d, a, x[13], 21, 0x4e0811a1); /* 60 */
    II (a, b, c, d, x[ 4],  6, 0xf7537e82); /* 61 */
    II (d, a, b, c, x[11], 10, 0xbd3af235); /* 62 */
    II (c, d, a, b, x[ 2], 15, 0x2ad7d2bb); /* 63 */
    II (b, c, d, a, x[ 9], 21, 0xeb86d391); /* 64 */

    Buf[0] += A;
    Buf[1] += B;
    Buf[2] += C;
    Buf[3] += D;
}

/** update MD5 Context */
static final function MD5Update(out MD5_CTX Context, string Data, int InputLen)
{
    local int i, Index, PartLen;
    local array<byte> TmpBuf;

    TmpBuf.Length = 64;
    Index = ((Context.Count[0] >>> 3) & 0x3F);
    if ((Context.Count[0] += (InputLen << 3)) < (InputLen << 3))
        Context.Count[1]++;
    Context.Count[1] += (InputLen >>> 29);
    partLen = 64 - Index;

    if (InputLen >= partLen)
    {
        MD5Move(Data, 0, Context.Buffer, Index, partLen);
        MD5Transform (Context.State, Context.Buffer);
        for (i = partLen; i + 63 < InputLen; i += 64)
        {
            MD5Move(Data, i, TmpBuf, 0, 64);
            MD5Transform (Context.State, TmpBuf);
        }
        Index = 0;
    }
    else
        i = 0;

    MD5Move(Data, i, Context.Buffer, Index, InputLen-i);
}

/** finalize the MD5 Context */
static final function MD5Final(out array<byte> Digest, out MD5_CTX Context)
{
    local array<byte> bits;
    local int i, Index, padLen;
    local string strbits;
    local string PADDING;

    PADDING = chr(0x80);
    for (i = 1; i < 64; i++)
        PADDING = PADDING$chr(0);

    MD5Encode (bits, Context.Count, 8);

    Index = ((Context.Count[0] >>> 3) & 0x3f);
    if (Index < 56)
        padLen = (56 - Index);
    else
        padLen = (120 - Index);
    MD5Update (Context, PADDING, padLen);
    strbits = "";
    for (i=0;i<8;i++)
        strbits = strbits$Chr(bits[i]);
    MD5Update (Context, strbits, 8);
    MD5Encode (Digest, Context.State, 16);

    for (i = 0; i < 64; i++)
    {
        Context.Buffer[i] = 0;
    }
}

static final function MD5Encode (out array<byte> Output, const out array<int> Input, int Len)
{
    local int i, j;

    i = 0;
    for (j = 0; j < Len; j += 4)
    {
        Output[j] = (Input[i] & 0xff);
        Output[j+1] = ((Input[i] >> 8) & 0xff);
        Output[j+2] = ((Input[i] >> 16) & 0xff);
        Output[j+3] = ((Input[i] >> 24) & 0xff);
        i++;
    }
}


static final function MD5Decode(out array<int> Output, const out array<byte> Input, int Len)
{
    local int i, j;

    i = 0;
    for (j = 0; j < Len; j += 4)
    {
        Output[i] = ((Input[j]) | (int(Input[j+1]) << 8) | (int(Input[j+2]) << 16) | (int(Input[j+3]) << 24));
        i++;
    }
}


static final function MD5Move(string Src, int SrcIndex, out array<byte> Buffer, int BufIndex, int Len)
{
    local int i,j;

    j = BufIndex;
    for (i = SrcIndex; i < SrcIndex+Len; i++)
    {
        Buffer[j] = Asc(Mid(Src, i, 1));
        j++;
        if (j == 64)
            break;
    }
}


static final function int ROTATE_LEFT (int x, int n)
{
    return (((x) << (n)) | ((x) >>> (32-(n))));
}

static final function int F (int x, int y, int z)
{
    return (((x) & (y)) | ((~x) & (z)));
}

static final function int G (int x, int y, int z)
{
    return ((x & z) | (y & (~z)));
}

static final function int H (int x, int y, int z)
{
    return (x ^ y ^ z);
}

static final function int I (int x, int y, int z)
{
    return (y ^ (x | (~z)));
}

static final function FF(out int a, int b, int c, int d, int x, int s, int ac)
{
    a += F(b, c, d) + x + ac;
    a = ROTATE_LEFT (a, s);
    a += b;
}

static final function GG(out int a, int b, int c, int d, int x, int s, int ac)
{
    a += G(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

static final function HH(out int a, int b, int c, int d, int x, int s, int ac)
{
    a += H(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

static final function II(out int a, int b, int c, int d, int x, int s, int ac)
{
    a += I(b, c, d) + x + ac;
    a = rotate_left (a, s) +b;
}

/** convert a decimal to hexadecimal notation */
static final function string DecToHex(int dec, int size)
{
    const hex = "0123456789abcdef";
    local string s;
    local int i;

    for (i = 0; i < size*2; i++)
    {
        s = mid(hex, dec & 0xf, 1) $ s;
        dec = dec >>> 4;
    }

    return s;
}

static final function bool Divide(coerce string Src, string Divider, out string LeftPart, out string RightPart)
{
    local int i;

    i = InStr(Src, Divider);
    if (i == INDEX_NONE)
    {
        return false;
    }

    LeftPart = Left(Src, i);
    RightPart = Right(Src, Len(Src) - i - 1);

    return true;
}

defaultproperties
{
    LOGERR=0
    LOGWARN=1
    LOGINFO=2
    LOGDATA=3

    MonthNames[1]="Jan"
    MonthNames[2]="Feb"
    MonthNames[3]="Mar"
    MonthNames[4]="Apr"
    MonthNames[5]="May"
    MonthNames[6]="Jun"
    MonthNames[7]="Jul"
    MonthNames[8]="Aug"
    MonthNames[9]="Sep"
    MonthNames[10]="Oct"
    MonthNames[11]="Nov"
    MonthNames[12]="Dec"

    DayNamesShort[0]="Sun"
    DayNamesShort[1]="Mon"
    DayNamesShort[2]="Tue"
    DayNamesShort[3]="Wed"
    DayNamesShort[4]="Thu"
    DayNamesShort[5]="Fri"
    DayNamesShort[6]="Sat"

    DayNamesLong[0]="Sunday"
    DayNamesLong[1]="Monday"
    DayNamesLong[2]="Tuesday"
    DayNamesLong[3]="Wednesday"
    DayNamesLong[4]="Thursday"
    DayNamesLong[5]="Friday"
    DayNamesLong[6]="Saturday"

    MonthOffset[0]=0
    MonthOffset[1]=31
    MonthOffset[2]=59
    MonthOffset[3]=90
    MonthOffset[4]=120
    MonthOffset[5]=151
    MonthOffset[6]=181
    MonthOffset[7]=212
    MonthOffset[8]=243
    MonthOffset[9]=273
    MonthOffset[10]=304
    MonthOffset[11]=334
    MonthOffset[12]=365

    MonthOffsetLeap[0]=0
    MonthOffsetLeap[1]=31
    MonthOffsetLeap[2]=60
    MonthOffsetLeap[3]=91
    MonthOffsetLeap[4]=121
    MonthOffsetLeap[5]=152
    MonthOffsetLeap[6]=182
    MonthOffsetLeap[7]=213
    MonthOffsetLeap[8]=244
    MonthOffsetLeap[9]=274
    MonthOffsetLeap[10]=305
    MonthOffsetLeap[11]=335
    MonthOffsetLeap[12]=366
}
