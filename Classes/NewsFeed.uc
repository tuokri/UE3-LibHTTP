/**
	NewsFeed
	RSS\RDF Porcessing. Part of [[LibHTTP]].
	Either RSS or RDF format is accepted. 
	''Note:'' the HTML special chars are NOT fixed, you have to do this yourself
	''Note:'' Don't pound the webserver with requests, cache your results

	Dcoumentation and Information:
		http://wiki.beyondunreal.com/wiki/LibHTTP

	Authors:	Michiel 'El Muerte' Hendriks <elmuerte@drunksnipers.com>

	$Id: NewsFeed.uc,v 1.3 2003/07/30 19:39:34 elmuerte Exp $
*/

class NewsFeed extends Object;

var string ChannelTitle;
var string ChannelDescription;
var string ChannelLink;

struct RDFRentry
{
	var string Title;
	var string Link;
};
var array<RDFRentry> Entries;

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
	log(">>"@tmp);
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
	s = getWord();
	while (Left(s, 1) != "<") 
	{
		if (res != "") res = res$" ";
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
			ChannelDescription = getToNextTag();
			tag = getTag(args);
		}
		else if (tag ~= "DESCRIPTION")
		{
			ChannelTitle = getToNextTag();
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
		if (tag == "") return false;
	}
	return true;
}
