unit RdcmX.UI.Properties;

{
  Eigenschappen-dialoog voor bestand, groep en server.

  - Algemeen (naam, hostnaam, opmerking, Wake-on-LAN voor servers) en Aanmelden (eigen gebruikersnaam/domein of
    een credential-profiel uit het bestand) staan in de DFM.
  - Alle andere instellingssecties zijn generieke tabbladen (RdcmX.UI.SectionPage), hier in BuildSectionPages
    opgebouwd: per tabblad het vinkje "Overnemen van ..." en velden die 1-op-1 op RDCMan-elementen zitten.
  - Er wordt gewerkt op een kopie (FWork); pas bij OK gaat alles naar de node.
  - Wachtwoorden worden nooit opgeslagen en staan dus niet in deze dialoog (ook niet voor de gateway).
  - encryptionSettings heeft geen tabblad: zonder opgeslagen wachtwoorden heeft die sectie geen functie; hij gaat
    ongewijzigd mee bij opslaan.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.Generics.Collections, System.SysUtils, System.UITypes,
  Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.Model, RdcmX.UI.SectionPage;

type
  TRdcLogonChoice = record
    Custom: Boolean;
    Scope: TRdcProfileScope;
    ProfileName: string;
    Available: Boolean;
  end;

  TfrmProperties = class(TForm)
    pcPages: TPageControl;
    tsGeneral: TTabSheet;
    lblName: TLabel;
    edtName: TEdit;
    lblServer: TLabel;
    edtServer: TEdit;
    lblComment: TLabel;
    memComment: TMemo;
    gbWakeOnLan: TGroupBox;
    lblMac: TLabel;
    edtMac: TEdit;
    lblWolBroadcast: TLabel;
    edtWolBroadcast: TEdit;
    lblWolPort: TLabel;
    edtWolPort: TEdit;
    lblWolHint: TLabel;
    tsLogon: TTabSheet;
    chkLogonInherit: TCheckBox;
    lblProfile: TLabel;
    cbProfile: TComboBox;
    lblUser: TLabel;
    edtUser: TEdit;
    lblDomain: TLabel;
    edtDomain: TEdit;
    lblLogonHint: TLabel;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormShow(Sender: TObject);
    procedure edtNameChange(Sender: TObject);
    procedure edtServerChange(Sender: TObject);
    procedure chkLogonInheritClick(Sender: TObject);
    procedure cbProfileChange(Sender: TObject);
  private
    FNode: TRdcNode;
    FContext: TRdcGroup;
    FWork: TRdcNodeSettings;
    FPages: TObjectList<TRdcSectionPage>;
    FDisplayPage: TRdcSectionPage;
    FInitialDisplayMode: string;
    FLogonChoices: TArray<TRdcLogonChoice>;
    FLoading: Boolean;
    FServerFollowsName: Boolean;
    FSyncingServer: Boolean;
    procedure FocusFirstField;
    procedure SyncServerWithName;
    procedure ServerEditedByUser;
    function ValidateInput: Boolean;
    function ValidateGeneral: Boolean;
    function ValidatePages: Boolean;
    procedure ShowInvalid(aPage: TTabSheet; aControl: TWinControl; const aMessage: string);
    function InheritedGroup(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
    function InheritCaption: string;
    function ProfilesFile: TRdcFile;
    function AddPage(const aCaption: string; aClass: TRdcSettingsGroupClass): TRdcSectionPage;
    procedure BuildSectionPages;
    procedure BuildRoutePage;
    procedure ApplyFieldHints;
    procedure SyncRemoteDesktopWithDisplayMode;
    procedure LoadGeneral;
    procedure LoadWakeOnLan;
    procedure SaveGeneral;
    procedure SaveWakeOnLan;
    procedure BuildLogonChoices(aSettings: TRdcLogonCredentials);
    function SelectedLogonChoice: TRdcLogonChoice;
    procedure ShowLogon;
    procedure ShowLogonValues(aSettings: TRdcLogonCredentials);
    procedure LogonInheritChanged;
    procedure LogonChoiceChanged;
    procedure SaveLogon(aSettings: TRdcLogonCredentials);
    procedure SaveLogonSection;
    procedure LoadFromNode;
    procedure SaveToNode;
  public
    /// <summary>aContext: de groep waarvan geërfd wordt (bij een nieuwe node de toekomstige parent).</summary>
    class function Execute(aNode: TRdcNode; aContext: TRdcGroup): Boolean; static;
  end;

implementation

uses
  RdcmX.WakeOnLan;

{$R *.dfm}

function TryParseDesktopSize(const aText: string; out aWidth, aHeight: Integer): Boolean;
var
  lParts: TArray<string>;
begin
  // Zelfde notatie als RDCMan: "1920 x 1080".
  lParts := aText.ToLower.Split(['x']);
  Result := (Length(lParts) = 2) and TryStrToInt(Trim(lParts[0]), aWidth) and TryStrToInt(Trim(lParts[1]), aHeight) and (aWidth >= 200) and (aHeight >= 200) and (aWidth <= 8192) and (aHeight <= 8192);
end;

class function TfrmProperties.Execute(aNode: TRdcNode; aContext: TRdcGroup): Boolean;
var
  lForm: TfrmProperties;
begin
  lForm := TfrmProperties.Create(Application);
  try
    lForm.FNode := aNode;
    lForm.FContext := aContext;
    lForm.LoadFromNode;
    Result := lForm.ShowModal = mrOk;
    if Result then
      lForm.SaveToNode;
  finally
    lForm.Free;
  end;
end;

procedure TfrmProperties.FormCreate(Sender: TObject);
begin
  FWork := TRdcNodeSettings.Create(True);
  FPages := TObjectList<TRdcSectionPage>.Create(True);
  pcPages.ActivePage := tsGeneral;
end;

procedure TfrmProperties.FormDestroy(Sender: TObject);
begin
  FPages.Free;
  FWork.Free;
end;

procedure TfrmProperties.FormShow(Sender: TObject);
begin
  FocusFirstField;
end;

procedure TfrmProperties.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (ModalResult <> mrOk) or ValidateInput;
end;

procedure TfrmProperties.edtNameChange(Sender: TObject);
begin
  SyncServerWithName;
end;

procedure TfrmProperties.edtServerChange(Sender: TObject);
begin
  ServerEditedByUser;
end;

procedure TfrmProperties.chkLogonInheritClick(Sender: TObject);
begin
  LogonInheritChanged;
end;

procedure TfrmProperties.cbProfileChange(Sender: TObject);
begin
  LogonChoiceChanged;
end;

{ Algemeen }

procedure TfrmProperties.FocusFirstField;
begin
  // Altijd beginnen op het eerste veld (niet op de tabbladen).
  pcPages.ActivePage := tsGeneral;
  ActiveControl := edtName;
end;

procedure TfrmProperties.SyncServerWithName;
begin
  // Nieuwe server: de hostnaam loopt mee met de naam, tot de hostnaam zelf wordt aangepast.
  if FLoading or not FServerFollowsName then
    Exit;
  FSyncingServer := True;
  try
    edtServer.Text := edtName.Text;
  finally
    FSyncingServer := False;
  end;
end;

procedure TfrmProperties.ServerEditedByUser;
begin
  if not FLoading and not FSyncingServer then
    FServerFollowsName := False;
end;

function TfrmProperties.InheritedGroup(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
begin
  if FContext <> nil then
    Result := FContext.Effective(aClass)
  else
    Result := TRdcNode.AppDefaults.Find(aClass);
end;

function TfrmProperties.InheritCaption: string;
begin
  if FContext = nil then
    Result := 'Overnemen van standaardinstellingen'
  else
    Result := Format('Overnemen van bovenliggende groep (%s)', [FContext.Caption]);
end;

function TfrmProperties.ProfilesFile: TRdcFile;
begin
  // Bij een nieuwe node hangt die nog niet in de boom: dan het bestand van de toekomstige parent.
  if FContext <> nil then
    Result := FContext.RdcFile
  else
    Result := FNode.RdcFile;
end;

procedure TfrmProperties.LoadGeneral;
var
  lIsServer: Boolean;
begin
  lIsServer := FNode is TRdcServer;
  if FNode is TRdcFile then
    Caption := 'Eigenschappen van bestand'
  else if lIsServer then
    Caption := 'Eigenschappen van server'
  else
    Caption := 'Eigenschappen van groep';
  lblServer.Visible := lIsServer;
  edtServer.Visible := lIsServer;
  gbWakeOnLan.Visible := lIsServer;
  // Server: "Naam" = weergavenaam (optioneel), "Servernaam" = hostnaam. Groep: "Naam" = groepsnaam.
  if lIsServer then
  begin
    lblName.Caption := 'Weergavenaam';
    edtName.Text := TRdcServer(FNode).DisplayName;
    edtServer.Text := FNode.Name;
    FServerFollowsName := FNode.Name = ''; // nieuwe server
  end
  else
    edtName.Text := FNode.Name;
  memComment.Text := FNode.Comment;
  LoadWakeOnLan;
end;

procedure TfrmProperties.LoadWakeOnLan;
begin
  edtMac.Text := FWork.Host.MacAddress;
  edtWolBroadcast.Text := FWork.Host.WolBroadcast;
  edtWolPort.Text := IntToStr(FWork.Host.WolPort);
end;

procedure TfrmProperties.SaveGeneral;
begin
  if FNode is TRdcServer then
  begin
    FNode.Name := Trim(edtServer.Text);
    if SameText(Trim(edtName.Text), FNode.Name) then
      TRdcServer(FNode).DisplayName := ''
    else
      TRdcServer(FNode).DisplayName := Trim(edtName.Text);
    SaveWakeOnLan;
  end
  else
    FNode.Name := Trim(edtName.Text);
  FNode.Comment := memComment.Text;
end;

procedure TfrmProperties.SaveWakeOnLan;
var
  lHost: TRdcxHostSettings;
  lMac: TRdcMacAddress;
begin
  lHost := FWork.Host;
  if Trim(edtMac.Text) = '' then
  begin
    // Geen MAC-adres = geen eigen sectie (komt dan ook niet in de sidecar).
    lHost.Inherit := True;
    lHost.Clear;
    Exit;
  end;
  TRdcWakeOnLan.TryParseMac(edtMac.Text, lMac); // al gevalideerd
  lHost.Inherit := False;
  if lHost.MacAddress <> TRdcWakeOnLan.FormatMac(lMac) then
    lHost.MacAddress := TRdcWakeOnLan.FormatMac(lMac);
  if lHost.WolBroadcast <> Trim(edtWolBroadcast.Text) then
    lHost.WolBroadcast := Trim(edtWolBroadcast.Text);
  if lHost.WolPort <> StrToInt(edtWolPort.Text) then
    lHost.WolPort := StrToInt(edtWolPort.Text);
end;

{ Tabbladen per sectie }

function TfrmProperties.AddPage(const aCaption: string; aClass: TRdcSettingsGroupClass): TRdcSectionPage;
begin
  Result := TRdcSectionPage.Create(pcPages, aCaption, InheritCaption, FWork.Find(aClass), InheritedGroup(aClass));
  FPages.Add(Result);
end;

procedure TfrmProperties.ApplyFieldHints;
var
  lPage: TRdcSectionPage;
begin
  // Uitleg (tooltip) bij elk veld van de generieke tabbladen.
  for lPage in FPages do
  begin
    lPage.SetHint('port', 'TCP-poort van Extern bureaublad op de server (standaard 3389).');
    lPage.SetHint('connectToConsole', 'Verbinden met de beheersessie (console) in plaats van een nieuwe sessie, zoals mstsc /admin.');
    lPage.SetHint('startProgram', 'Programma dat na het aanmelden start in plaats van het bureaublad (alleen als de server dat toestaat).');
    lPage.SetHint('workingDir', 'Map waarin het startprogramma begint.');
    lPage.SetHint('loadBalanceInfo', 'Routeringsinformatie voor een RD Connection Broker (load balancing). Meestal leeg laten.');
    lPage.SetHint('route', 'Hoe de server bereikt wordt: rechtstreeks (eventueel via de RDCMan-gateway hieronder), via een Tailscale-netwerk, of via een RDP-gateway uit de lijst.');
    lPage.SetHint('tailnetId', 'Het Tailscale-netwerk waarlangs verbonden wordt (beheer via Bestand > Tailscale-netwerken).');
    lPage.SetHint('tailnetHost', 'Naam of adres van de server in het tailnet: de machinenaam uit de Tailscale-console of het 100.x-adres. Leeg = de servernaam.');
    lPage.SetHint('gatewayId', 'De RDP-gateway waarlangs verbonden wordt (beheer via Bestand > RDP-gateways).');
    lPage.SetHint('ping', 'Op de achtergrond controleren of de server bereikbaar is (ping, anders de RDP-poort). In de boom: groen = bereikbaar, rood = niet bereikbaar, oranje = andere computer op dat adres. Interval: Bestand > Opties.');
    lPage.SetHint('enabled', 'RDCMan-gatewayinstelling (staat in de .rdg): bij route Direct via deze gateway verbinden.');
    lPage.SetHint('hostName', 'Naam van de RD Gateway-server, bijv. rdg.voorbeeld.nl.');
    lPage.SetHint('logonMethod', 'Hoe je je bij de gateway aanmeldt: wachtwoord (NTLM), smartcard, of later kiezen.');
    lPage.SetHint('localBypass', 'Servers in het lokale netwerk rechtstreeks benaderen, niet via de gateway.');
    lPage.SetHint('credSharing', 'Voor de gateway dezelfde gebruikersnaam en hetzelfde wachtwoord gebruiken als voor de server.');
    lPage.SetHint('userName', 'Gebruikersnaam voor de gateway (als de aanmeldgegevens niet gedeeld worden).');
    lPage.SetHint('domain', 'Domein van de gateway-gebruiker.');
    lPage.SetHint('displayMode', 'Dynamisch: de resolutie volgt het vak of venster. Venstergrootte: vast op de grootte bij verbinden. Vaste grootte: de afmeting hieronder. Of volledig scherm.');
    lPage.SetHint('desktopScale', 'Schaal (DPI) in de sessie. Automatisch volgt de monitor waarop RDCManagerX staat. In dynamische modus meteen toegepast.');
    lPage.SetHint('size', 'Afmeting bij "Vaste grootte", als breedte x hoogte (bijv. 1920 x 1080).');
    lPage.SetHint('colorDepth', 'Kleurdiepte van de sessie; 32 bits is standaard.');
    lPage.SetHint('smartSizeDockedWindows', 'Bij venstergrootte of vaste grootte de inhoud schalen zodat hij in het vak past (niet nodig bij dynamisch).');
    lPage.SetHint('resizeDebounceMs', 'Hoe lang na het wijzigen van de venstergrootte gewacht wordt voordat de resolutie wordt aangepast.');
    lPage.SetHint('reconnectOnResizeFallback', 'Ondersteunt de server geen dynamische resolutie, dan opnieuw verbinden met de nieuwe afmeting.');
    lPage.SetHint('audioRedirection', 'Waar het geluid uit de sessie wordt afgespeeld.');
    lPage.SetHint('audioRedirectionQuality', 'Geluidskwaliteit; hoger kost meer bandbreedte.');
    lPage.SetHint('audioCaptureRedirection', 'De microfoon van deze pc in de sessie gebruiken.');
    lPage.SetHint('keyboardHook', 'Waar Windows-toetscombinaties (zoals Alt+Tab en de Windows-toets) heengaan.');
    lPage.SetHint('redirectClipboard', 'Kopiëren en plakken tussen deze pc en de sessie (tekst en bestanden). De server moet dit toestaan.');
    lPage.SetHint('redirectDrives', 'Stations van deze pc beschikbaar maken in de sessie.');
    lPage.SetHint('redirectPrinters', 'Printers van deze pc gebruiken in de sessie.');
    lPage.SetHint('redirectPorts', 'COM- en LPT-poorten van deze pc doorgeven aan de sessie.');
    lPage.SetHint('redirectSmartCards', 'Smartcards van deze pc gebruiken in de sessie (ook om aan te melden).');
    lPage.SetHint('redirectPnpDevices', 'Plug-and-play-apparaten (bijv. camera of telefoon) doorgeven aan de sessie.');
    lPage.SetHint('authentication', 'Wat te doen als het certificaat van de server niet geverifieerd kan worden: toch verbinden, niet verbinden, of waarschuwen (aanbevolen).');
  end;
end;

procedure TfrmProperties.BuildRoutePage;
var
  lCaptions: TArray<string>;
  lFile: TRdcFile;
  lGateway: TRdcGatewayDef;
  lIds: TArray<string>;
  lPage: TRdcSectionPage;
  lTailnet: TRdcTailnetDef;
begin
  // Route en de RDCMan-gateway op één tabblad (één vinkje): samen bepalen ze hoe de server bereikt wordt. De
  // keuzelijsten komen uit de definities van het bestand (Bestand > Tailscale-netwerken / RDP-gateways). Bij een
  // nieuwe server/groep hangt die nog niet in het bestand: dan het bestand van de toekomstige parent.
  lFile := ProfilesFile;
  lPage := AddPage('Route', TRdcxRouteSettings);
  lPage.AddSection(FWork.Gateway, InheritedGroup(TRdcGatewaySettings));
  lPage.UseSection(FWork.Route);
  lPage.AddChoice('route', 'Verbindingsroute', cRdcRouteKindNames, ['Direct (eventueel via de gateway hieronder)', 'Via Tailscale-netwerk', 'Via RDP-gateway uit de lijst']);
  lIds := [''];
  lCaptions := ['(geen)'];
  if lFile <> nil then
    for lTailnet in lFile.Tailnets do
    begin
      lIds := lIds + [lTailnet.Id];
      lCaptions := lCaptions + [lTailnet.Name];
    end;
  lPage.AddChoice('tailnetId', 'Tailscale-netwerk', lIds, lCaptions);
  lPage.AddText('tailnetHost', 'Adres in het tailnet');
  lIds := [''];
  lCaptions := ['(geen)'];
  if lFile <> nil then
    for lGateway in lFile.Gateways do
    begin
      lIds := lIds + [lGateway.Id];
      lCaptions := lCaptions + [lGateway.Name];
    end;
  lPage.AddChoice('gatewayId', 'RDP-gateway', lIds, lCaptions);
  lPage.AddCheck('ping', 'Bereikbaarheid tonen in de boom (ping op de achtergrond, alleen bij Direct)');
  lPage.AddHint('Adres in het tailnet: de machinenaam (MagicDNS) of het 100.x-adres van de server; leeg = de servernaam. Netwerken en gateways beheer je via Bestand > Tailscale-netwerken en Bestand > RDP-gateways.');

  // RDCMan-gateway (gatewaySettings in de .rdg): alleen bij route Direct.
  lPage.UseSection(FWork.Gateway);
  lPage.AddCheck('enabled', 'Gateway gebruiken (RDCMan-instelling, bij Direct)');
  lPage.AddText('hostName', 'Gatewayserver');
  lPage.AddChoice('logonMethod', 'Aanmeldmethode', cRdcGatewayLogonMethodNames, ['Wachtwoord vragen (NTLM)', 'Smartcard', 'Later kiezen']);
  lPage.AddCheck('localBypass', 'Gateway overslaan voor lokale adressen');
  lPage.AddCheck('credSharing', 'Zelfde aanmeldgegevens gebruiken als voor de server');
  lPage.AddText('userName', 'Gebruikersnaam gateway');
  lPage.AddText('domain', 'Domein gateway');
  lPage.AddHint('Deze gateway staat in de .rdg (RDCMan kan hem ook gebruiken); het wachtwoord wordt niet opgeslagen. Een gateway uit de lijst (route "Via RDP-gateway") kan dat wel, in de wachtwoordkluis.');

  // Alleen de velden van de gekozen route zijn actief.
  lPage.FieldApplies :=
    function(const aElement: string): Boolean
    var
      lKind: TRdcRouteKind;
    begin
      lKind := TRdcRouteKind(RdcTextToEnum(lPage.FieldValue('route'), cRdcRouteKindNames, Ord(rkDirect)));
      if (aElement = 'tailnetId') or (aElement = 'tailnetHost') then
        Result := lKind = rkTailscale
      else if aElement = 'gatewayId' then
        Result := lKind = rkGateway
      else if (aElement = 'route') or (aElement = 'ping') then
        Result := True
      else
        Result := lKind = rkDirect; // de RDCMan-gatewayvelden
    end;
end;

procedure TfrmProperties.BuildSectionPages;
var
  lPage: TRdcSectionPage;
begin
  lPage := AddPage('Verbinding', TRdcConnectionSettings);
  lPage.AddNumber('port', 'Poort', 1, 65535);
  lPage.AddCheck('connectToConsole', 'Verbinden met de beheersessie (console)');
  lPage.AddText('startProgram', 'Programma starten na aanmelden');
  lPage.AddText('workingDir', 'Werkmap van dat programma');
  lPage.AddText('loadBalanceInfo', 'Load-balancinginformatie');
  lPage.AddHint('Een startprogramma werkt alleen als de server dat toestaat (groepsbeleid/RemoteApp).');

  BuildRoutePage;

  // Weergave: één tabblad en één vinkje voor drie secties (rdcmx, remoteDesktop, displaySettings), zodat er geen
  // tegenstrijdige combinaties ontstaan. Miniatuur-instellingen staan er niet op (geen miniaturen in RDCManX);
  // ze gaan ongewijzigd mee voor RDCMan. sameSizeAsClientArea/fullScreen worden bij opslaan uit de modus afgeleid.
  FDisplayPage := AddPage('Weergave', TRdcxSettings);
  FDisplayPage.AddSection(FWork.RemoteDesktop, InheritedGroup(TRdcRemoteDesktopSettings));
  FDisplayPage.AddSection(FWork.Display, InheritedGroup(TRdcDisplaySettings));
  FDisplayPage.UseSection(FWork.Extras);
  FDisplayPage.AddChoice('displayMode', 'Weergavemodus', cRdcDisplayModeNames, ['Dynamisch (volgt het venster)', 'Venstergrootte bij verbinden', 'Vaste grootte', 'Volledig scherm']);
  FDisplayPage.AddChoice('desktopScale', 'Schaal in de sessie', ['0', '100', '125', '150', '175', '200', '250', '300'], ['Automatisch (volgt de monitor)', '100%', '125%', '150%', '175%', '200%', '250%', '300%']);
  FDisplayPage.UseSection(FWork.RemoteDesktop);
  FDisplayPage.AddSuggestions('size', 'Vaste grootte (breedte x hoogte)', ['1024 x 768', '1280 x 720', '1280 x 1024', '1366 x 768', '1600 x 900', '1920 x 1080', '1920 x 1200', '2560 x 1440']);
  FDisplayPage.AddChoice('colorDepth', 'Kleurdiepte', ['15', '16', '24', '32'], ['15 bits', '16 bits', '24 bits', '32 bits']);
  FDisplayPage.UseSection(FWork.Display);
  FDisplayPage.AddChoice('smartSizeDockedWindows', 'Inhoud schalen (smart sizing)', cRdcSmartSizeNames, ['Nee', 'Ja, bij venstergrootte of vaste grootte']);
  FDisplayPage.UseSection(FWork.Extras);
  FDisplayPage.AddNumber('resizeDebounceMs', 'Wachttijd na formaatwijziging (ms)', 100, 5000);
  FDisplayPage.AddCheck('reconnectOnResizeFallback', 'Opnieuw verbinden als dynamisch aanpassen niet werkt');
  FDisplayPage.AddHint('Dynamisch: de resolutie volgt het vak of venster (schalen niet nodig). Vaste grootte gebruikt de opgegeven afmeting. Een gewijzigde schaal geldt direct voor open sessies; de andere instellingen bij de volgende verbinding.');

  lPage := AddPage('Lokale bronnen', TRdcLocalResources);
  lPage.AddChoice('audioRedirection', 'Geluid', cRdcAudioRedirectionNames, ['Op deze computer afspelen', 'Op de externe computer afspelen', 'Niet afspelen']);
  lPage.AddChoice('audioRedirectionQuality', 'Geluidskwaliteit', cRdcAudioQualityNames, ['Automatisch', 'Gemiddeld', 'Hoog']);
  lPage.AddChoice('audioCaptureRedirection', 'Microfoon', cRdcAudioCaptureNames, ['Opnemen vanaf deze computer', 'Niet opnemen']);
  lPage.AddChoice('keyboardHook', 'Windows-toetscombinaties', cRdcKeyboardHookNames, ['Op deze computer', 'Op de externe computer', 'Alleen bij volledig scherm']);
  lPage.AddCheck('redirectClipboard', 'Klembord (tekst en bestanden kopiëren/plakken)');
  lPage.AddCheck('redirectDrives', 'Stations van deze computer');
  lPage.AddCheck('redirectPrinters', 'Printers');
  lPage.AddCheck('redirectPorts', 'Poorten (COM/LPT)');
  lPage.AddCheck('redirectSmartCards', 'Smartcards');
  lPage.AddCheck('redirectPnpDevices', 'Plug-and-play-apparaten');
  lPage.AddHint('Wijzigingen gelden bij de volgende verbinding.');

  lPage := AddPage('Beveiliging', TRdcSecuritySettings);
  lPage.AddChoice('authentication', 'Serverauthenticatie', cRdcAuthenticationNames, ['Verbinden zonder waarschuwing', 'Niet verbinden als verificatie mislukt', 'Waarschuwen als verificatie mislukt']);

  for lPage in FPages do
    lPage.Refresh;
  ApplyFieldHints;
  FInitialDisplayMode := FDisplayPage.FieldValue('displayMode');
end;

procedure TfrmProperties.SyncRemoteDesktopWithDisplayMode;
var
  lMode: TRdcDisplayMode;
begin
  // RDCMan-compatibel houden: wie het bestand in RDCMan opent, krijgt een vergelijkbare weergave. Alleen als de
  // modus gewijzigd is en remoteDesktop een eigen sectie is (na ApplyToWork).
  if FWork.RemoteDesktop.Inherit or (FDisplayPage.FieldValue('displayMode') = FInitialDisplayMode) then
    Exit;
  lMode := TRdcDisplayMode(RdcTextToEnum(FDisplayPage.FieldValue('displayMode'), cRdcDisplayModeNames, Ord(dmDynamic)));
  case lMode of
    dmDynamic, dmClientArea:
      begin
        FWork.RemoteDesktop.SameSizeAsClientArea := True;
        FWork.RemoteDesktop.FullScreen := False;
      end;
    dmFixed:
      begin
        FWork.RemoteDesktop.SameSizeAsClientArea := False;
        FWork.RemoteDesktop.FullScreen := False;
      end;
    dmFullScreen:
      FWork.RemoteDesktop.FullScreen := True;
  end;
end;

{ Aanmelden }

procedure TfrmProperties.BuildLogonChoices(aSettings: TRdcLogonCredentials);
var
  lChoice: TRdcLogonChoice;
  lFile: TRdcFile;
  lFound: Boolean;
  lProfile: TRdcCredentialProfile;
begin
  cbProfile.Items.Clear;
  FLogonChoices := [];
  lChoice := Default(TRdcLogonChoice);
  lChoice.Custom := True;
  lChoice.Available := True;
  FLogonChoices := FLogonChoices + [lChoice];
  cbProfile.Items.Add('(eigen gebruikersnaam en domein)');

  lFile := ProfilesFile;
  if lFile <> nil then
    for lProfile in lFile.Profiles do
    begin
      lChoice := Default(TRdcLogonChoice);
      lChoice.Scope := psFile;
      lChoice.ProfileName := lProfile.ProfileName;
      lChoice.Available := True;
      FLogonChoices := FLogonChoices + [lChoice];
      cbProfile.Items.Add(Format('Profiel: %s', [lProfile.ProfileName]));
    end;

  // Verwijzing naar een profiel dat hier niet bestaat (extern RDCMan-profiel of verwijderd): toch tonen, zodat het blijft staan.
  if not aSettings.IsCustom then
  begin
    lFound := aSettings.IsFileProfile and (lFile <> nil) and (lFile.FindProfile(aSettings.ProfileName) <> nil);
    if not lFound then
    begin
      lChoice := Default(TRdcLogonChoice);
      lChoice.Scope := aSettings.ProfileScope;
      lChoice.ProfileName := aSettings.ProfileName;
      FLogonChoices := FLogonChoices + [lChoice];
      cbProfile.Items.Add(Format('%s (niet beschikbaar in RDCManX)', [aSettings.ProfileName]));
    end;
  end;
end;

function TfrmProperties.SelectedLogonChoice: TRdcLogonChoice;
begin
  if (cbProfile.ItemIndex >= 0) and (cbProfile.ItemIndex <= High(FLogonChoices)) then
    Result := FLogonChoices[cbProfile.ItemIndex]
  else
    Result := FLogonChoices[0];
end;

procedure TfrmProperties.ShowLogonValues(aSettings: TRdcLogonCredentials);
var
  lChoice: TRdcLogonChoice;
  lFile: TRdcFile;
  lProfile: TRdcCredentialProfile;
begin
  lChoice := SelectedLogonChoice;
  lblLogonHint.Caption := 'Wachtwoorden worden nooit opgeslagen; bij elke verbinding wordt erom gevraagd.';
  if lChoice.Custom then
  begin
    edtUser.Text := aSettings.UserName;
    edtDomain.Text := aSettings.Domain;
    Exit;
  end;
  lFile := ProfilesFile;
  lProfile := nil;
  if lChoice.Available and (lFile <> nil) then
    lProfile := lFile.FindProfile(lChoice.ProfileName);
  if lProfile <> nil then
  begin
    edtUser.Text := lProfile.UserName;
    edtDomain.Text := lProfile.Domain;
    lblLogonHint.Caption := 'Gebruikersnaam en domein komen uit het profiel (beheer: Bestand > Credential-profielen).' + sLineBreak + lblLogonHint.Caption;
  end
  else
  begin
    edtUser.Text := '';
    edtDomain.Text := '';
    lblLogonHint.Caption := Format('Profiel "%s" is niet beschikbaar; bij verbinden wordt om de gebruikersnaam gevraagd.', [lChoice.ProfileName]);
  end;
end;

procedure TfrmProperties.ShowLogon;
var
  lIndex: Integer;
  lSettings: TRdcLogonCredentials;
begin
  if chkLogonInherit.Checked then
    lSettings := TRdcLogonCredentials(InheritedGroup(TRdcLogonCredentials))
  else
    lSettings := FWork.Logon;
  FLoading := True;
  try
    BuildLogonChoices(lSettings);
    cbProfile.ItemIndex := 0;
    if not lSettings.IsCustom then
      for lIndex := 1 to High(FLogonChoices) do
        if (FLogonChoices[lIndex].Scope = lSettings.ProfileScope) and SameText(FLogonChoices[lIndex].ProfileName, lSettings.ProfileName) then
          cbProfile.ItemIndex := lIndex;
    ShowLogonValues(lSettings);
  finally
    FLoading := False;
  end;
  cbProfile.Enabled := not chkLogonInherit.Checked;
  edtUser.Enabled := not chkLogonInherit.Checked and SelectedLogonChoice.Custom;
  edtDomain.Enabled := edtUser.Enabled;
end;

procedure TfrmProperties.LogonInheritChanged;
begin
  if FLoading then
    Exit;
  if chkLogonInherit.Checked then
    SaveLogon(FWork.Logon) // eigen waarden bewaren voor als het vinkje weer uit gaat
  else if FWork.Logon.Node.Children.Count = 0 then
    FWork.Logon.ReplaceNode(InheritedGroup(TRdcLogonCredentials).Node.Clone); // geërfde waarden als startpunt
  ShowLogon;
end;

procedure TfrmProperties.LogonChoiceChanged;
begin
  if FLoading then
    Exit;
  ShowLogonValues(FWork.Logon);
  edtUser.Enabled := SelectedLogonChoice.Custom;
  edtDomain.Enabled := edtUser.Enabled;
end;

procedure TfrmProperties.SaveLogon(aSettings: TRdcLogonCredentials);
var
  lChoice: TRdcLogonChoice;
begin
  lChoice := SelectedLogonChoice;
  if lChoice.Custom then
  begin
    if not aSettings.IsCustom then
    begin
      aSettings.ProfileName := cRdcCustomProfileName;
      aSettings.ProfileScope := psLocal;
    end;
    if aSettings.UserName <> Trim(edtUser.Text) then
      aSettings.UserName := Trim(edtUser.Text);
    if aSettings.Domain <> Trim(edtDomain.Text) then
      aSettings.Domain := Trim(edtDomain.Text);
  end
  else if (aSettings.ProfileScope <> lChoice.Scope) or not SameText(aSettings.ProfileName, lChoice.ProfileName) then
  begin
    aSettings.ProfileName := lChoice.ProfileName;
    aSettings.ProfileScope := lChoice.Scope;
  end;
end;

procedure TfrmProperties.SaveLogonSection;
begin
  FWork.Logon.Inherit := chkLogonInherit.Checked;
  if FWork.Logon.Inherit then
  begin
    FWork.Logon.Clear;
    Exit;
  end;
  if FWork.Logon.Node.Children.Count = 0 then
    FWork.Logon.FillDefaults;
  SaveLogon(FWork.Logon);
end;

{ Laden / opslaan / valideren }

procedure TfrmProperties.LoadFromNode;
begin
  FLoading := True;
  try
    FWork.Assign(FNode.Settings);
    LoadGeneral;
    chkLogonInherit.Caption := InheritCaption;
    chkLogonInherit.Checked := FWork.Logon.Inherit;
  finally
    FLoading := False;
  end;
  ShowLogon;
  BuildSectionPages;
end;

procedure TfrmProperties.SaveToNode;
var
  lPage: TRdcSectionPage;
begin
  SaveGeneral;
  SaveLogonSection;
  for lPage in FPages do
    lPage.ApplyToWork;
  SyncRemoteDesktopWithDisplayMode;
  FNode.Settings.Assign(FWork);
end;

procedure TfrmProperties.ShowInvalid(aPage: TTabSheet; aControl: TWinControl; const aMessage: string);
begin
  pcPages.ActivePage := aPage;
  if (aControl <> nil) and aControl.CanFocus then
    aControl.SetFocus;
  MessageDlg(aMessage, mtWarning, [mbOK], 0);
end;

function TfrmProperties.ValidateGeneral: Boolean;
var
  lMac: TRdcMacAddress;
  lPort: Integer;
begin
  Result := False;
  // Bij een server is de weergavenaam optioneel (dan wordt de hostnaam getoond).
  if (Trim(edtName.Text) = '') and not (FNode is TRdcServer) then
  begin
    ShowInvalid(tsGeneral, edtName, 'Vul een naam in.');
    Exit;
  end;
  if FNode is TRdcServer then
  begin
    if Trim(edtServer.Text) = '' then
    begin
      ShowInvalid(tsGeneral, edtServer, 'Vul de servernaam of het IP-adres in.');
      Exit;
    end;
    if Trim(edtMac.Text) <> '' then
    begin
      if not TRdcWakeOnLan.TryParseMac(edtMac.Text, lMac) then
      begin
        ShowInvalid(tsGeneral, edtMac, 'Ongeldig MAC-adres. Voorbeeld: 00-11-22-33-44-55.');
        Exit;
      end;
      if Trim(edtWolBroadcast.Text) = '' then
      begin
        ShowInvalid(tsGeneral, edtWolBroadcast, 'Vul het broadcastadres in (meestal 255.255.255.255).');
        Exit;
      end;
      if not TryStrToInt(edtWolPort.Text, lPort) or (lPort < 1) or (lPort > 65535) then
      begin
        ShowInvalid(tsGeneral, edtWolPort, 'De UDP-poort moet een getal tussen 1 en 65535 zijn (meestal 9 of 7).');
        Exit;
      end;
    end;
  end;
  Result := True;
end;

function TfrmProperties.ValidatePages: Boolean;
var
  lControl: TWinControl;
  lHeight: Integer;
  lMessage: string;
  lPage: TRdcSectionPage;
  lWidth: Integer;
begin
  Result := False;
  for lPage in FPages do
    if not lPage.Validate(lControl, lMessage) then
    begin
      ShowInvalid(lPage.Sheet, lControl, lMessage);
      Exit;
    end;
  if FDisplayPage.IsOwn and not TryParseDesktopSize(FDisplayPage.FieldValue('size'), lWidth, lHeight) then
  begin
    ShowInvalid(FDisplayPage.Sheet, nil, 'Ongeldige vaste grootte. Gebruik breedte x hoogte, bijvoorbeeld 1920 x 1080.');
    Exit;
  end;
  Result := True;
end;

function TfrmProperties.ValidateInput: Boolean;
begin
  Result := ValidateGeneral and ValidatePages;
end;

end.
