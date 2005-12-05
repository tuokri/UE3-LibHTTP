/*******************************************************************************
    NewsFeed                                                                    <br />
    RSS\RDF Porcessing. Part of [[LibHTTP]].
    Either RSS or RDF format is accepted.                                       <br />
    ''Note:'' the HTML special chars are NOT fixed, you have to do this yourself<br />
    ''Note:'' Don't pound the webserver with requests, cache your results       <br />
                                                                                <br />
    Dcoumentation and Information:
        http://wiki.beyondunreal.com/wiki/LibHTTP                               <br />
                                                                                <br />
    Authors:    Michiel 'El Muerte' Hendriks &lt;elmuerte@drunksnipers.com&gt;  <br />
                                                                                <br />
    Copyright 2003, 2004 Michiel "El Muerte" Hendriks                           <br />
    Released under the Lesser Open Unreal Mod License                           <br />
    http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense

    <!-- $Id: NewsFeed.uc,v 1.14 2005/12/05 10:03:41 elmuerte Exp $ -->
*******************************************************************************/

class NewsFeed extends Core.Object PerObjectConfig;

/** name of this object */
var(Config) config string rssHost;
/** download location */
var(Config) config string rssLocation;
/** true if this feed is enabled */
var(Config) config bool rssEnabled;
/** minutes between updates, make this a nice value like 45 minutes */
var(Config) config int rssUpdateInterval;

/** Last time this source had been fetched, you have to do this yourself */
var(Config) config int LastUpdate;

/** Channel title as defined in the RSS file */
var(RSSContent) config string ChannelTitle;
/** Channel description as defined in the RSS file */
var(RSSContent) config string ChannelDescription;
/** Channel link as defined in the RSS file */
var(RSSContent) config string ChannelLink;

/** RDF\RSS item record */
struct RDFRentry
{
    /** title of the RDF Entry */
    var string Title;
    /** link of the RDF Entry */
    var string Link;
    /** description of the RDF Entry */
    var string Desc;
};
/** the current content */
var(RSSContent) config array<RDFRentry> Entries;

/** if set to false it will not strip the entry size to 512 bytes */
var bool bSizeBugFix;

/** @ignore */
var protected array<string> data, line;
/** @ignore */
var protected int lineno, wordno;

/** Main function to parse the input data */
function int ParseRDFData(array<string> inp)
{
    lineno = 0;
    wordno = 0;
    data = inp;
    line.length = 0;
    ChannelTitle = "";
    ChannelDescription = "";
    ChannelLink = "";
    Entries.length = 0;
    _rdf();
    return Entries.length;
}

/** get another word from the buffer */
protected function string getWord()
{
    local string res;
    while (res == "")
    {
        if (wordno >= line.length) if (!getLine()) return "";
        res = line[wordno];
        wordno++;
    }
    return res;
}

/** fill the line buffer */
protected function bool getLine()
{
    local string tmp;
    if (lineno >= data.length) return false;
    tmp = data[lineno];
    class'HttpUtil'.static.ReplaceChar(tmp, Chr(9), " ");
    class'HttpUtil'.static.ReplaceChar(tmp, "<", " <");
    class'HttpUtil'.static.ReplaceChar(tmp, ">", "> ");
    split(tmp, " ", line);
    lineno++;
    wordno = 0;
    return true;
}

/** retreive a tag with arguments */
protected function string getTag(out array<string> Args)
{
    local string s, t;
    s = getWord();
    if (Left(s, 1) == "<")
    {
        s = Mid(s, 1);
        Args.length = 0;
        if (Right(s, 1) != ">")
        {
            t = getWord();
            while (Right(t, 1) != ">")
            {
                Args[Args.length] = t;
                t = getWord();
                if (t == "") return "";
            }
            Args[Args.length] = Left(t, Len(t)-1);
        }
        else s = Left(s, Len(s)-1);
    }
    return Caps(s);
}

protected function string getToNextTag()
{
    local string res, s;
    local bool cdata;

    cdata = false;
    s = getWord();
    if (Left(s, 9) == "<![CDATA[")
    {
        cdata = true;
        s = Mid(s, 9);
    }
    while (Left(s, 1) != "<")
    {
        if (res != "") res = res$" ";
        if (cdata && (right(s, 3) == "]]>")) s = Left(s, Len(s)-3);
        res = res$s;
        s = getWord();
        if (s == "") return "";
    }
    wordno--;
    return class'HttpUtil'.static.trim(res);
}

protected function bool _rdf()
{
    local string tag;
    local array<string> args;
    tag = getTag(args);
    while ((tag != "RSS") && (tag != "RDF:RDF"))
    {
        tag = getTag(args);
        if (tag == "") return false;
    }

    while ((tag != "/RSS") && (tag != "/RDF:RDF"))
    {
        tag = getTag(args);
        if (tag ~= "CHANNEL")
        {
            if (!_channel(args)) return false;
        }
        else if (tag ~= "ITEM")
        {
            if (!_item(args)) return false;
        }
        if (tag == "") return false;
    }
    return true;
}

protected function bool _channel(array<string> Args)
{
    local string tag;
    while (tag != "/CHANNEL")
    {
        tag = getTag(args);
        if (tag ~= "TITLE")
        {
            ChannelTitle = getToNextTag();
            tag = getTag(args);
        }
        else if (tag ~= "DESCRIPTION")
        {
            ChannelDescription = getToNextTag();
            if (bSizeBugFix) ChannelDescription = Left(ChannelDescription, 512);
            tag = getTag(args);
        }
        else if (tag ~= "LINK")
        {
            ChannelLink = getToNextTag();
            tag = getTag(args);
        }
        else if (tag ~= "ITEM")
        {
            if (!_item(args)) return false;
        }
        if (tag == "") return false;
    }
    return true;
}

protected function bool _item(array<string> Args)
{
    local string tag;
    local int n;
    n = Entries.length;
    Entries.length = n+1;
    while (tag != "/ITEM")
    {
        tag = getTag(args);
        if (tag ~= "TITLE")
        {
            Entries[n].Title = getToNextTag();
            tag = getTag(args);
        }
        else if (tag ~= "LINK")
        {
            Entries[n].Link = getToNextTag();
            tag = getTag(args);
        }
        else if (tag ~= "DESCRIPTION")
        {
            Entries[n].Desc = getToNextTag();
            if (bSizeBugFix) Entries[n].Desc = Left(Entries[n].Desc, 512);
            tag = getTag(args);
        }
        if (tag == "") return false;
    }
    return true;
}

defaultproperties
{
    bSizeBugFix=true
}