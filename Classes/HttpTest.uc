/*******************************************************************************
	Test Package for LibHTTP													<br />
																				<br />
	Copyright 2003, 2004 Michiel "El Muerte" Hendriks							<br />
	Released under the Lesser Open Unreal Mod License							<br />
	http://wiki.beyondunreal.com/wiki/LesserOpenUnrealModLicense				<br />

	<!-- $Id: HttpTest.uc,v 1.7 2004/09/30 15:58:55 elmuerte Exp $ -->
*******************************************************************************/
class HttpTest extends Engine.Info;

/** various tests */
enum EHttpTests
{
	HT_GET,
	HT_HEAD,
	HT_POST,
	HT_AUTH,
	HT_FASTGET,
	HT_TRACE,
	HT_PROXY,
};
var config array<EHttpTests> Tests;

/** urls used for testing */
var config array<string> GetUrls, HeadUrls, FastUrls;

/** POST test data */
struct PostDataEntry
{
	var string url;
	var array<GameInfo.KeyValuePair> Data;
};
/** POST request tests */
var config array<PostDataEntry> PostData;

/**
	auth request data, can be either basic or digest, because this will be
	retried when authorization is required.
*/
struct AuthEntry
{
	var string url;
	var string username;
	var string password;
};
/** auth tests */
var config array<AuthEntry> AuthUrls;

struct ProxyConfig
{
	/** proxy host */
	var string host;
	/** proxy port */
	var int port;
	/** proxy username */
	var string username;
	/** proxy password */
	var string password;
	/** url to fetch via the proxy */
	var string url;
};
/** proxy tests */
var config array<ProxyConfig> ProxyTests;

/** current test */
var int TestId;

/** test iteration */
var int TestIteration;

/** our test socket */
var HttpSock sock;

event PostBeginPlay()
{
	sock = spawn(class'HttpSock');
	sock.iVerbose = class'HttpUtil'.default.LOGDATA; // set the verbosity very high to see what happens (for debugging)
	sock.OnComplete = DownloadComplete;
	sock.Cookies = new class'HttpCookies';
	sock.Cookies.iVerbose = class'HttpUtil'.default.LOGINFO; // for debugging

	TestId = 0;
	TestIteration = 0;
	RunTest();
}

/** execute the next test set in line */
function NextTest()
{
	TestId++;
	TestIteration = 0;
	RunTest();
}

/** run the test */
function RunTest()
{
	if (TestId >= Tests.length) return;
	log("==> Executing test #"$TestId$"."$TestIteration);
	sock.TransferMode = TM_Normal; // reset
	sock.AuthMethod = AM_None; // reset
	sock.ClearRequestData();
	sock.bUseProxy = false;
	switch (Tests[TestId])
	{
		case HT_GET:
			testGet();
			break;
		case HT_HEAD:
			testHead();
			break;
		case HT_POST:
			testPost();
			break;
		case HT_AUTH:
			testAuth();
			break;
		case HT_FASTGET:
			testFastGet();
			break;
		case HT_TRACE:
			testTrace();
			break;
		case HT_PROXY:
			testProxy();
			break;
	}
}

/** will be called when the download is complete, dump the data to a file */
function DownloadComplete(HttpSock Sender)
{
	local FileLog f;
	local int i;
	f = spawn(class'FileLog');
	f.OpenLog("LibHTTP3-"$GetEnum(enum'EHttpTests', Tests[TestId])$"-"$TestIteration, "html", true);
	f.logf("<!-- ");
	for (i = 0; i < sock.RequestHistory.length-1; i++)
	{
		f.logf("Hostname:"@sock.RequestHistory[i].Hostname);
		f.logf("Location:"@sock.RequestHistory[i].Location);
		f.logf("Method:"@sock.RequestHistory[i].Method);
		f.logf("Response:"@sock.RequestHistory[i].HTTPresponse);
		f.logf("");
	}
	f.logf("Hostname:"@sock.sHostname);
	f.logf("Location:"@sock.RequestLocation);
	f.logf("Method:"@sock.RequestMethod);
	f.logf("RequestDuration:"@sock.RequestDuration);
	f.logf("");
	for (i = 0; i < sock.ReturnHeaders.length; i++)
	{
		f.Logf(sock.ReturnHeaders[i]);
	}
	f.logf("-->");
	for (i = 0; i < sock.ReturnData.length; i++)
	{
		if (len(sock.ReturnData[i]) > 1024)
		{
			f.Logf(Left(sock.ReturnData[i], 1024));
			f.Logf(Mid(sock.ReturnData[i], 1024));
		}
		else f.Logf(sock.ReturnData[i]);
	}
	f.Destroy();
	RunTest();
}

/** normal get request tests */
function testGet()
{
	if (TestIteration >= GetUrls.Length)
	{
		NextTest();
		return;
	}
	sock.get(GetUrls[TestIteration++]);
}

/** normal head request tests */
function testHead()
{
	if (TestIteration >= HeadUrls.Length)
	{
		NextTest();
		return;
	}
	sock.head(HeadUrls[TestIteration++]);
}

/** normal post request tests */
function testPost()
{
	local int i;
	if (TestIteration >= PostData.Length)
	{
		NextTest();
		return;
	}
	sock.clearFormData();
	for (i = 0; i < PostData[TestIteration].Data.length; i++)
	{
		sock.setFormData(PostData[TestIteration].Data[i].Key, PostData[TestIteration].Data[i].Value);
	}
	sock.post(PostData[TestIteration].url);
	TestIteration++;
}

/** basic and digest auth tests */
function testAuth()
{
	if (TestIteration >= AuthUrls.Length)
	{
		NextTest();
		return;
	}
	sock.OnRequireAuthorization = AuthRequired;
	sock.sAuthUsername = AuthUrls[TestIteration].username;
	sock.sAuthPassword = AuthUrls[TestIteration].password;
	sock.get(AuthUrls[TestIteration].url);
	TestIteration++;
}

/** will be called when authentication is required */
function AuthRequired(HttpSock Sender, HttpSock.EAuthMethod method, array<GameInfo.KeyValuePair> info)
{
	sock.OnComplete = AuthRetry;
}

/** retry when authentication failed */
function AuthRetry(HttpSock Sender)
{
	sock.OnComplete = DownloadComplete;
	TestIteration--;
	testAuth();
}

/** fast get request tests */
function testFastGet()
{
	if (TestIteration >= GetUrls.Length)
	{
		NextTest();
		return;
	}
	sock.TransferMode = TM_Fast;
	sock.get(FastUrls[TestIteration++]);
}

/** fast get request tests */
function testTrace()
{
	if (TestIteration >= GetUrls.Length)
	{
		NextTest();
		return;
	}
	sock.httrace(FastUrls[TestIteration++]);
}

/** proxy test, will automatically use AM_Basic if a username is set */
function testProxy()
{
	if (TestIteration >= ProxyTests.Length)
	{
		NextTest();
		return;
	}
	sock.sProxyHost = ProxyTests[TestIteration].host;
	sock.iProxyPort = ProxyTests[TestIteration].port;
	sock.sProxyUser = ProxyTests[TestIteration].username;
	sock.sProxyPass = ProxyTests[TestIteration].password;
	sock.bUseProxy = true;
	if (sock.sProxyUser != "") sock.ProxyAuthMethod = AM_Basic;
	sock.get(ProxyTests[TestIteration].url);
	TestIteration++;
}

defaultproperties
{
	Tests=(HT_GET,HT_HEAD,HT_POST,HT_AUTH,HT_FASTGET,HT_TRACE,HT_PROXY)
}
