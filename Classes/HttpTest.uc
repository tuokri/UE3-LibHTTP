/*******************************************************************************
	Test Package for LibHTTP
*******************************************************************************/
class HttpTest extends Info;

/** various tests */
enum EHttpTests
{
	HT_GET,
	HT_HEAD,
	HT_POST,
	HT_AUTH,
};
var config array<EHttpTests> Tests;

/** urls used for testing */
var config array<string> GetUrls, HeadUrls;

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

/** current test */
var int TestId;

/** test iteration */
var int TestIteration;

/** our test socket */
var HttpSock sock;

event PostBeginPlay()
{
	sock = spawn(class'HttpSock');
	sock.iVerbose = class'HttpUtil'.default.LOGDATA;
	sock.OnComplete = DownloadComplete;
	sock.Cookies = new class'HttpCookies';
	sock.Cookies.iVerbose = class'HttpUtil'.default.LOGINFO;
	TestId = 0; // so the first test would be #0
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
	}
}

function DownloadComplete()
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

/** normal get request tests */
function testHead()
{
	if (TestIteration >= HeadUrls.Length)
	{
		NextTest();
		return;
	}
	sock.head(HeadUrls[TestIteration++]);
}

/** normal get request tests */
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

/** normal get request tests */
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

function AuthRequired(HttpSock.EAuthMethod method, array<GameInfo.KeyValuePair> info)
{
	sock.OnComplete = AuthRetry;
}

function AuthRetry()
{
	sock.OnComplete = DownloadComplete;
	TestIteration--;
	testAuth();
}

defaultproperties
{
	GetUrls[0]="http://www.google.com" // set's cookie, and mostliky redirect
	GetUrls[1]="http://el-muerte.student.utwente.nl/test/__php_info.php"
	GetUrls[2]="http://r.elmuerte.com" // redirect
	GetUrls[3]="http://el-muerte.student.utwente.nl/test/__php_info.php?some=var&and=another+item&last=one%20the%20end"

	HeadUrls[0]="http://www.google.com"
	HeadUrls[1]="http://el-muerte.student.utwente.nl/test/__php_info.php"
	HeadUrls[2]="http://r.elmuerte.com"
	HeadUrls[3]="http://downloads.unrealadmin.org/UT2004/Patches/Windows/ut2004-winpatch3323.exe"

	PostData[0]=(url="http://el-muerte.student.utwente.nl/test/__php_info.php?data=on+the+url&will=move%20to%20body")
	PostData[1]=(url="http://el-muerte.student.utwente.nl/test/__php_info.php",data=((Key="data",Value="in the body"),(Key="MoreData",Value="alsdjh laskjh asdkjh asldk alskjfd"),(Key="Last",Value="-- the end -- elmuerte")))
	PostData[2]=(url="http://r.elmuerte.com/test/__php_info.php?data=will+be+lost+in+redir")

	AuthUrls[0]=(url="http://test:test@el-muerte.student.utwente.nl/test/htpass/basic/")
	AuthUrls[1]=(url="http://el-muerte.student.utwente.nl/test/htpass/basic/",username="test",password="test")
	AuthUrls[2]=(url="http://el-muerte.student.utwente.nl/test/htpass/digest/",username="test",password="test")
	AuthUrls[3]=(url="http://el-muerte.student.utwente.nl/test/htpass/digest2/",username="test",password="test")

	Tests[0]=HT_GET
	Tests[1]=HT_HEAD
	Tests[2]=HT_POST
	Tests[3]=HT_AUTH
}
