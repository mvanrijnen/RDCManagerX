unit RdcmX.Tests.Lang;

(*
  UI language: parsing of the .po catalogue, and the real catalogue Source\Lang\en.po (found by walking up from
  the exe, like the samples). Without an active catalogue _ returns the Dutch source text.
*)

interface

uses
  System.Generics.Collections, System.IOUtils, System.SysUtils,
  DUnitX.TestFramework,
  RdcmX.Lang;

type
  [TestFixture]
  TLangTests = class
  private
    function FindCatalogue: string;
  public
    [Test]
    procedure ParsesEntriesAndEscapes;
    [Test]
    procedure SkipsHeaderAndEmptyTranslations;
    [Test]
    procedure WithoutCatalogueReturnsSource;
    [Test]
    procedure LanguageNames;
    [Test]
    procedure RealCatalogueIsComplete;
  end;

implementation

const
  cSample =
    '# comment'#13#10 +
    'msgid ""'#13#10 +
    'msgstr ""'#13#10 +
    '"Content-Type: text/plain; charset=UTF-8\n"'#13#10 +
    #13#10 +
    '#: Source/RdcmX.UI.Main.dfm'#13#10 +
    'msgid "Verbinden\tEnter"'#13#10 +
    'msgstr "Connect\tEnter"'#13#10 +
    #13#10 +
    'msgid ""'#13#10 +
    '"Regel een\n"'#13#10 +
    '"Regel \"twee\""'#13#10 +
    'msgstr ""'#13#10 +
    '"Line one\n"'#13#10 +
    '"Line \"two\" \\ end"'#13#10 +
    #13#10 +
    'msgid "Nog niet vertaald"'#13#10 +
    'msgstr ""'#13#10;

function TLangTests.FindCatalogue: string;
var
  lDir: string;
begin
  lDir := ExtractFilePath(ParamStr(0));
  while lDir <> '' do
  begin
    Result := TPath.Combine(lDir, 'Source\Lang\en.po');
    if TFile.Exists(Result) then
      Exit;
    if TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(lDir)) = ExcludeTrailingPathDelimiter(lDir) then
      Break;
    lDir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(lDir));
  end;
  Result := '';
end;

procedure TLangTests.ParsesEntriesAndEscapes;
var
  lCatalogue: TDictionary<string, string>;
begin
  lCatalogue := TDictionary<string, string>.Create;
  try
    ParsePoCatalogue(cSample, lCatalogue);
    Assert.AreEqual('Connect'#9'Enter', lCatalogue['Verbinden'#9'Enter']);
    Assert.AreEqual('Line one'#10'Line "two" \ end', lCatalogue['Regel een'#10'Regel "twee"']);
  finally
    lCatalogue.Free;
  end;
end;

procedure TLangTests.SkipsHeaderAndEmptyTranslations;
var
  lCatalogue: TDictionary<string, string>;
begin
  lCatalogue := TDictionary<string, string>.Create;
  try
    ParsePoCatalogue(cSample, lCatalogue);
    Assert.AreEqual(2, Integer(lCatalogue.Count));
    Assert.IsFalse(lCatalogue.ContainsKey(''));
    Assert.IsFalse(lCatalogue.ContainsKey('Nog niet vertaald'));
  finally
    lCatalogue.Free;
  end;
end;

procedure TLangTests.WithoutCatalogueReturnsSource;
begin
  // The test exe has no LANG_EN resource: English falls back to Dutch.
  SetUiLanguage('en');
  try
    Assert.AreEqual('nl', UiLanguageCode);
    Assert.AreEqual('Verbinden', _('Verbinden'));
  finally
    SetUiLanguage('nl');
  end;
end;

procedure TLangTests.LanguageNames;
begin
  Assert.AreEqual(Ord(rlEnglish), Ord(RdcLanguageFromName('EN')));
  Assert.AreEqual(Ord(rlDutch), Ord(RdcLanguageFromName('nl')));
  Assert.AreEqual(Ord(rlSystem), Ord(RdcLanguageFromName('')));
  Assert.AreEqual('en', ResolveLanguageCode(rlEnglish));
  Assert.AreEqual('nl', ResolveLanguageCode(rlDutch));
end;

procedure TLangTests.RealCatalogueIsComplete;
var
  lCatalogue: TDictionary<string, string>;
  lFile: string;
begin
  lFile := FindCatalogue;
  if lFile = '' then
  begin
    Assert.Pass('Source\Lang\en.po not found');
    Exit;
  end;
  lCatalogue := TDictionary<string, string>.Create;
  try
    ParsePoCatalogue(TFile.ReadAllText(lFile, TEncoding.UTF8), lCatalogue);
    Assert.IsTrue(lCatalogue.Count > 100, 'catalogue has too few translations');
    Assert.AreEqual('Connect'#9'Enter', lCatalogue['Verbinden'#9'Enter']);
  finally
    lCatalogue.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLangTests);

end.
