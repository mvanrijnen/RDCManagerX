unit RdcmX.UI.Theme;

{
  Thema: Systeem (volgt Windows: "Kies je app-modus"), Licht (VCL-stijl "Windows11 Modern Light") of Donker
  ("Windows11 Modern Dark" indien aanwezig, anders "Windows10 Dark"). De .vsf-bestanden staan in Styles\ en
  worden via Custom_Styles in de dproj ingebouwd.

  Belangrijk: TStyleManager.SetStyle maakt ALLE vensters opnieuw aan (getest: form, panelen en kind-controls
  krijgen nieuwe handles). Een RDP-host met een nieuwe handle verliest zijn sessie. Daarom:
  - bij het opstarten wordt het thema gezet vóór er vensters zijn (ApplyStartupTheme in de dpr);
  - tijdens het draaien alleen omschakelen als er geen sessies (tabs) open zijn; anders bij de volgende start.

  RDP-host, sessiegebied en placeholder tekenen hun eigen (donkere) kleuren en hebben StyleElements = [].
}

interface

type
  TRdcTheme = (rtSystem, rtLight, rtDark);

const
  cRdcThemeNames: array[TRdcTheme] of string = ('system', 'light', 'dark');
  // Stijlen staan in Styles\ en worden via Custom_Styles in de dproj ingebouwd. De eerste die beschikbaar is, wint.
  // "Windows11 Modern Dark" komt uit GetIt; zolang die niet in Styles\ staat, wordt het Windows10 Dark.
  cRdcDarkStyleNames: array[0..1] of string = ('Windows11 Modern Dark', 'Windows10 Dark');
  cRdcLightStyleNames: array[0..1] of string = ('Windows11 Modern Light', 'Windows');

function RdcThemeFromName(const aName: string): TRdcTheme;
/// <summary>Windows-instelling "Kies je standaard-app-modus" = Donker.</summary>
function SystemUsesDarkTheme: Boolean;
function RdcThemeIsDark(aTheme: TRdcTheme): Boolean;
/// <summary>Zet de bijbehorende VCL-stijl. True als de stijl daadwerkelijk wisselde (dan zijn alle vensters opnieuw aangemaakt).</summary>
function ApplyTheme(aTheme: TRdcTheme): Boolean;
/// <summary>Thema uit de app-instellingen toepassen; aanroepen in de dpr vóór Application.CreateForm.</summary>
procedure ApplyStartupTheme;
/// <summary>Is de actieve weergave donker (op basis van de vensterkleur van de actieve stijl)?</summary>
function RdcActiveStyleIsDark: Boolean;

implementation

uses
  Winapi.Windows,
  System.SysUtils, System.Win.Registry,
  Vcl.Graphics, Vcl.Styles, Vcl.Themes, // Vcl.Styles registreert de stijl-engine en de ingebouwde VCLSTYLE-resources

  RdcmX.AppSettings;

function RdcThemeFromName(const aName: string): TRdcTheme;
begin
  for Result := Low(TRdcTheme) to High(TRdcTheme) do
    if SameText(cRdcThemeNames[Result], aName) then
      Exit;
  Result := rtSystem;
end;

function SystemUsesDarkTheme: Boolean;
var
  lRegistry: TRegistry;
begin
  Result := False;
  lRegistry := TRegistry.Create(KEY_READ);
  try
    lRegistry.RootKey := HKEY_CURRENT_USER;
    if lRegistry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and lRegistry.ValueExists('AppsUseLightTheme') then
      Result := lRegistry.ReadInteger('AppsUseLightTheme') = 0;
  finally
    lRegistry.Free;
  end;
end;

function RdcThemeIsDark(aTheme: TRdcTheme): Boolean;
begin
  case aTheme of
    rtDark:
      Result := True;
    rtLight:
      Result := False;
  else
    Result := SystemUsesDarkTheme;
  end;
end;

function FirstAvailableStyle(const aNames: array of string): string;
var
  lAvailable: string;
  lName: string;
begin
  for lName in aNames do
    for lAvailable in TStyleManager.StyleNames do
      if SameText(lAvailable, lName) then
        Exit(lAvailable);
  Result := 'Windows';
end;

function ApplyTheme(aTheme: TRdcTheme): Boolean;
var
  lStyleName: string;
begin
  if RdcThemeIsDark(aTheme) then
    lStyleName := FirstAvailableStyle(cRdcDarkStyleNames)
  else
    lStyleName := FirstAvailableStyle(cRdcLightStyleNames);
  Result := not SameText(TStyleManager.ActiveStyle.Name, lStyleName);
  if Result then
    Result := TStyleManager.TrySetStyle(lStyleName, False);
end;

function RdcActiveStyleIsDark: Boolean;
var
  lColor: TColorRef;
begin
  lColor := ColorToRGB(TStyleManager.ActiveStyle.GetSystemColor(clWindow));
  Result := (GetRValue(lColor) * 299 + GetGValue(lColor) * 587 + GetBValue(lColor) * 114) div 1000 < 128;
end;

procedure ApplyStartupTheme;
var
  lSettings: TRdcAppSettings;
begin
  lSettings := TRdcAppSettings.Create;
  try
    lSettings.Load;
    ApplyTheme(RdcThemeFromName(lSettings.Theme));
  finally
    lSettings.Free;
  end;
end;

end.
