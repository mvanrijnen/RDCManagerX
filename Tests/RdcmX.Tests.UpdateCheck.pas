unit RdcmX.Tests.UpdateCheck;

{
  Tests for the update check (RdcmX.UpdateCheck): parsing the GitHub answer and comparing versions. No network.
}

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.UpdateCheck;

type
  [TestFixture]
  TUpdateCheckTests = class
  public
    [Test]
    procedure ParsesTagAndReleasePage;
    [Test]
    procedure ForeignPageUrlIsReplaced;
    [Test]
    procedure InvalidTagsAreRefused;
    [Test]
    procedure VersionsCompareNumerically;
  end;

implementation

procedure TUpdateCheckTests.ParsesTagAndReleasePage;
var
  lRelease: TRdcLatestRelease;
begin
  Assert.IsTrue(RdcParseLatestRelease('{"tag_name":"v2026.11.26.067","html_url":"https://github.com/mvanrijnen/RDCManagerX/releases/tag/v2026.11.26.067","name":"x"}', lRelease));
  Assert.AreEqual('2026.11.26.067', lRelease.Version);
  Assert.AreEqual('https://github.com/mvanrijnen/RDCManagerX/releases/tag/v2026.11.26.067', lRelease.PageUrl);
end;

procedure TUpdateCheckTests.ForeignPageUrlIsReplaced;
var
  lRelease: TRdcLatestRelease;
begin
  // The page from the answer is opened in the browser: only the release page of this repository.
  Assert.IsTrue(RdcParseLatestRelease('{"tag_name":"v2026.11.26.067","html_url":"https://evil.example/RDCManagerX/releases/tag/v2026.11.26.067"}', lRelease));
  Assert.AreEqual(cRdcReleasesUrl + '/latest', lRelease.PageUrl);
  Assert.IsTrue(RdcParseLatestRelease('{"tag_name":"v2026.11.26.067","html_url":"https://github.com/mvanrijnen/RDCManagerX/releases/tag/v2026.11.26.067/../../x"}', lRelease));
  Assert.AreEqual(cRdcReleasesUrl + '/latest', lRelease.PageUrl);
  Assert.IsTrue(RdcParseLatestRelease('{"tag_name":"v2026.11.26.067"}', lRelease));
  Assert.AreEqual(cRdcReleasesUrl + '/latest', lRelease.PageUrl);
end;

procedure TUpdateCheckTests.InvalidTagsAreRefused;
var
  lRelease: TRdcLatestRelease;
begin
  Assert.IsFalse(RdcParseLatestRelease('{"tag_name":"2026.11.26.067"}', lRelease), 'no v');
  Assert.IsFalse(RdcParseLatestRelease('{"tag_name":"v1.2.3"}', lRelease), 'three parts');
  Assert.IsFalse(RdcParseLatestRelease('{"tag_name":"v2026.11.26.0x7"}', lRelease), 'not numeric');
  Assert.IsFalse(RdcParseLatestRelease('{"message":"Not Found"}', lRelease));
  Assert.IsFalse(RdcParseLatestRelease('not json', lRelease));
  Assert.IsFalse(RdcParseLatestRelease('[1,2]', lRelease));
end;

procedure TUpdateCheckTests.VersionsCompareNumerically;
begin
  Assert.IsTrue(RdcCompareVersions('2026.11.26.067', '2026.11.26.059') > 0);
  Assert.IsTrue(RdcCompareVersions('2026.11.26.067', '2026.11.27.001') < 0);
  Assert.IsTrue(RdcCompareVersions('2026.12.01.001', '2026.11.30.120') > 0);
  Assert.AreEqual(0, RdcCompareVersions('2026.11.26.067', '2026.11.26.67'));
  Assert.IsTrue(RdcCompareVersions('2027.01.01.001', '2026.12.31.999') > 0);
  Assert.IsTrue(RdcIsVersion('2026.11.26.067'));
  Assert.IsFalse(RdcIsVersion('2026.11.26'));
  Assert.IsFalse(RdcIsVersion('versie 2026.11.26.067'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUpdateCheckTests);

end.
