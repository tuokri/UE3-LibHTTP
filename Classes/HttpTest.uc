class HttpTest extends Info;

const BASURL = "http://el-muerte.student.utwente.nl/test/__php_info.php";

var HttpSock sock;

var int TestId;

event PreBeginPlay()
{
	sock = spawn(class'HttpSock');
	sock.iVerbose = class'HttpUtil'.default.LOGDATA;
	sock.OnComplete = DownloadComplete;
	sock.Cookies = new class'HttpCookies';
	sock.Cookies.iVerbose = class'HttpUtil'.default.LOGINFO;

	TestId = 9; //...
	NextTest();
}

function DownloadComplete()
{
	local FileLog f;
	local int i;
	f = spawn(class'FileLog');
	f.OpenLog("LibHTTP3-test"$TestId, "html", true);
	f.logf("<!-- ");
	f.logf("RequestDuration:"@sock.RequestDuration);
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
	NextTest();
}

function NextTest()
{
	TestId++;
	sock.TransferMode = TM_Normal; // reset
	switch(TestId)
	{
		case 1: testGet(); break;
		case 2: testGet2(); break;
		case 3: testHead(); break;
		case 4: testHead2(); break;
		case 5: testPost(); break;
		case 6: testPost2(); break;
		case 7: testPost3(); break;
		case 8: testFastGet(); break;
		case 9: testAuthBasic(); break;
		case 10: testAuthDigest1(); break;
		case 11: testAuthDigest2(); break;
	}
}

function testGet()
{
	sock.get(BASURL);
}

function testGet2()
{
	sock.get(BASURL$"?name1=value1&name2=value%202&this_is_a_test=this+is+a+test");
}

function testHead()
{
	sock.head(BASURL);
}

function testHead2()
{
	sock.head(BASURL$"?name1=value1&name2=value%202&this_is_a_test=this+is+a+test");
}

function testPost()
{
	sock.post(BASURL);
}

function testPost2()
{
	local array<string> PostData;
	PostData[0] = "<html><body><pre>Multi line crap";
	PostData[1] = "will be posted as a couple of lines";
	PostData[2] = "-- elmuerte</pre></body></html>";
	sock.clearFormData();
	sock.setFormData("name1", "value1");
	sock.setFormData("name2", "value2");
	sock.setFormDataEx("multiline", PostData, "text/html");
	sock.post(BASURL);
}

function testPost3()
{
	sock.post(BASURL$"?name1=value1&name2=value%202&this_is_a_test=this+is+a+test");
}

function testFastGet()
{
	sock.TransferMode = TM_Fast;
	sock.get(BASURL);
}

function testAuthBasic()
{
	sock.sAuthUsername = "test";
	sock.sAuthPassword = "test";
	sock.get("http://el-muerte.student.utwente.nl/test/htpass/basic/");
}

function testAuthDigest1()
{
	sock.AuthMethod = AM_Unknown;
	sock.get("http://el-muerte.student.utwente.nl/test/htpass/digest/");
}

function testAuthDigest2()
{
	sock.sAuthUsername = "test";
	sock.sAuthPassword = "test";
	sock.get("http://el-muerte.student.utwente.nl/test/htpass/digest/");
}
