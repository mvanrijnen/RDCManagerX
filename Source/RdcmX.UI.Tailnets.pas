unit RdcmX.UI.Tailnets;

{
  Beheer van de Tailscale-netwerken van één bestand (TRdcFile.Tailnets; sidecar of .rdcx). De auth key staat alleen
  in de wachtwoordkluis van deze pc (TRdcPasswordVault.TailnetAuthKeyTarget), nooit in het bestand.

  Er wordt op kopieën gewerkt; bij OK eerst de geheimen opslaan (kan om het hoofdwachtwoord vragen; mislukt dat, dan
  blijft het venster open), daarna de definities naar het bestand.
  - Verwijderen kan alleen als geen route meer naar het netwerk verwijst en het niet in gebruik is door een sessie.
    De geheimen en de werkmap worden dan ook gewist, tenzij een ander open bestand hetzelfde netwerk (id) heeft.
  - "Test verbinding" start het netwerk via de TRdcTailnetManager van het hoofdvenster (zelfde werkmap en sleutels
    als bij echt verbinden), toont de status en sluit het weer. Een login-URL (interactief inloggen) wordt in de
    browser geopend. Draait het netwerk al voor een sessie, dan wordt alleen de status getoond.
}

interface

uses
  Winapi.Windows,
  System.Classes, System.Generics.Collections, System.IOUtils, System.SysUtils, System.UITypes,
  Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.AppSettings, RdcmX.Credentials, RdcmX.Model, RdcmX.Tailscale;

type
  TRdcTailnetEdit = class
  public
    Def: TRdcTailnetDef;
    IsNew: Boolean;
    /// <summary>Control URL bij openen: de geheimen zijn daaraan gebonden.</summary>
    OriginalControlUrl: string;
    /// <summary>Net ingevoerde auth key (nog niet opgeslagen).</summary>
    NewAuthKey: string;
    HasStoredAuthKey: Boolean;
    ClearAuthKey: Boolean;
    /// <summary>Client-side opt-ins (app settings, not the file).</summary>
    MatchHostName: Boolean;
    AllowShared: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  TfrmTailnets = class(TForm)
    lvTailnets: TListView;
    btnAdd: TButton;
    btnDelete: TButton;
    lblName: TLabel;
    edtName: TEdit;
    lblNodeHost: TLabel;
    edtNodeHost: TEdit;
    lblAuthKey: TLabel;
    edtAuthKey: TEdit;
    btnClearAuthKey: TButton;
    chkEphemeral: TCheckBox;
    chkMatchHostName: TCheckBox;
    chkAllowShared: TCheckBox;
    lblControlUrl: TLabel;
    edtControlUrl: TEdit;
    lblLocalAddress: TLabel;
    edtLocalAddress: TEdit;
    btnTest: TButton;
    lblTestStatus: TLabel;
    lblHint: TLabel;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    tmrTest: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure lvTailnetsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnAddClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnClearAuthKeyClick(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure tmrTestTimer(Sender: TObject);
  private
    FFile: TRdcFile;
    FSecrets: IRdcSecretAccess;
    FManager: TRdcTailnetManager;
    FSettings: TRdcAppSettings;
    FIdInUseElsewhere: TFunc<string, Boolean>;
    FEdits: TObjectList<TRdcTailnetEdit>;
    FDeletedIds: TList<string>;
    FChanged: Boolean;
    FLoading: Boolean;
    // Test
    FTestId: string;
    FTestGuard: IRdcCallbackGuard;
    FAuthUrlOpened: string;
    procedure LoadTailnets;
    procedure FillList(aSelect: TRdcTailnetEdit);
    procedure UpdateListItem(aItem: TListItem);
    function SelectedEdit: TRdcTailnetEdit;
    procedure ShowSelected;
    procedure StoreFields;
    procedure AddTailnet;
    procedure DeleteSelectedTailnet;
    procedure ClearSelectedAuthKey;
    function UniqueName(const aBase: string): string;
    function ValidateEdit(aEdit: TRdcTailnetEdit; out aControl: TWinControl; out aMessage: string): Boolean;
    function ValidateAll: Boolean;
    function SaveSecrets: Boolean;
    procedure ApplyToFile;
    procedure ApplyOptions;
    procedure DeleteLocalData(const aId: string; aForce: Boolean);
    function ControlUrlChanged(aEdit: TRdcTailnetEdit): Boolean;
    function IsTesting: Boolean;
    procedure ToggleTest;
    procedure StartTest;
    procedure StopTest(const aText: string);
    procedure ShowTestProgress;
    procedure TestFinished(aSuccess: Boolean; const aError: string);
    procedure UpdateButtons;
  protected
    /// <summary>Translates the DFM texts after loading, before OnCreate.</summary>
    procedure DoCreate; override;
  public
    /// <summary>True als er iets gewijzigd is (en toegepast op het bestand). aIdInUseElsewhere: staat dit id ook
    /// in een ander open bestand (dan de geheimen bij verwijderen laten staan).</summary>
    class function Execute(aFile: TRdcFile; const aSecrets: IRdcSecretAccess; aManager: TRdcTailnetManager; aSettings: TRdcAppSettings; const aIdInUseElsewhere: TFunc<string, Boolean>): Boolean; static;
  end;

implementation

uses
  RdcmX.Lang;

{$R *.dfm}

{ TRdcTailnetEdit }

constructor TRdcTailnetEdit.Create;
begin
  inherited Create;
  Def := TRdcTailnetDef.Create;
end;

destructor TRdcTailnetEdit.Destroy;
begin
  WipeString(NewAuthKey);
  Def.Free;
  inherited;
end;

{ TfrmTailnets }

class function TfrmTailnets.Execute(aFile: TRdcFile; const aSecrets: IRdcSecretAccess; aManager: TRdcTailnetManager; aSettings: TRdcAppSettings; const aIdInUseElsewhere: TFunc<string, Boolean>): Boolean;
var
  lForm: TfrmTailnets;
begin
  lForm := TfrmTailnets.Create(Application);
  try
    lForm.FFile := aFile;
    lForm.FSecrets := aSecrets;
    lForm.FManager := aManager;
    lForm.FSettings := aSettings;
    lForm.FIdInUseElsewhere := aIdInUseElsewhere;
    lForm.LoadTailnets;
    Result := (lForm.ShowModal = mrOk) and lForm.FChanged;
    if Result then
    begin
      lForm.ApplyToFile;
      lForm.ApplyOptions;
    end;
  finally
    lForm.Free;
  end;
end;

procedure TfrmTailnets.DoCreate;
begin
  // Translate the DFM texts before OnCreate runs.
  TranslateComponent(Self);
  inherited;
end;

procedure TfrmTailnets.FormCreate(Sender: TObject);
begin
  FEdits := TObjectList<TRdcTailnetEdit>.Create(True);
  FDeletedIds := TList<string>.Create;
end;

procedure TfrmTailnets.FormDestroy(Sender: TObject);
begin
  if IsTesting then
    StopTest('');
  FDeletedIds.Free;
  FEdits.Free;
end;

procedure TfrmTailnets.FormShow(Sender: TObject);
begin
  ShowSelected;
end;

procedure TfrmTailnets.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if IsTesting then
    StopTest('');
  CanClose := (ModalResult <> mrOk) or (ValidateAll and SaveSecrets);
end;

procedure TfrmTailnets.lvTailnetsSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  ShowSelected;
end;

procedure TfrmTailnets.btnAddClick(Sender: TObject);
begin
  AddTailnet;
end;

procedure TfrmTailnets.btnDeleteClick(Sender: TObject);
begin
  DeleteSelectedTailnet;
end;

procedure TfrmTailnets.btnClearAuthKeyClick(Sender: TObject);
begin
  ClearSelectedAuthKey;
end;

procedure TfrmTailnets.btnTestClick(Sender: TObject);
begin
  ToggleTest;
end;

procedure TfrmTailnets.FieldChange(Sender: TObject);
begin
  StoreFields;
end;

procedure TfrmTailnets.tmrTestTimer(Sender: TObject);
begin
  ShowTestProgress;
end;

procedure TfrmTailnets.LoadTailnets;
var
  lDef: TRdcTailnetDef;
  lEdit: TRdcTailnetEdit;
begin
  Caption := Format(_('Tailscale-netwerken - %s'), [FFile.Caption]);
  for lDef in FFile.Tailnets do
  begin
    lEdit := TRdcTailnetEdit.Create;
    lEdit.Def.Assign(lDef);
    lEdit.OriginalControlUrl := lDef.ControlUrl;
    lEdit.HasStoredAuthKey := FSecrets.HasSecret(TRdcPasswordVault.TailnetAuthKeyTarget(lDef.Id, lDef.ControlUrl));
    lEdit.MatchHostName := FSettings.TailnetHostNameMatch.IndexOf(TRdcPasswordVault.TailnetBindingKey(lDef.Id, lDef.ControlUrl)) >= 0;
    lEdit.AllowShared := FSettings.TailnetAllowShared.IndexOf(TRdcPasswordVault.TailnetBindingKey(lDef.Id, lDef.ControlUrl)) >= 0;
    FEdits.Add(lEdit);
  end;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
  if not TRdcTsBridge.Available then
    lblTestStatus.Caption := TRdcTsBridge.LoadError;
end;

procedure TfrmTailnets.FillList(aSelect: TRdcTailnetEdit);
var
  lEdit: TRdcTailnetEdit;
  lItem: TListItem;
begin
  FLoading := True;
  lvTailnets.Items.BeginUpdate;
  try
    lvTailnets.Items.Clear;
    for lEdit in FEdits do
    begin
      lItem := lvTailnets.Items.Add;
      lItem.Data := lEdit;
      lItem.SubItems.Add('');
      lItem.SubItems.Add('');
      lItem.SubItems.Add('');
      UpdateListItem(lItem);
      if lEdit = aSelect then
        lItem.Selected := True;
    end;
  finally
    lvTailnets.Items.EndUpdate;
    FLoading := False;
  end;
  if lvTailnets.Selected <> nil then
    lvTailnets.Selected.MakeVisible(False);
  ShowSelected;
end;

procedure TfrmTailnets.UpdateListItem(aItem: TListItem);
var
  lEdit: TRdcTailnetEdit;
begin
  lEdit := TRdcTailnetEdit(aItem.Data);
  aItem.Caption := lEdit.Def.Name;
  if lEdit.Def.NodeHostName <> '' then
    aItem.SubItems[0] := lEdit.Def.NodeHostName
  else
    aItem.SubItems[0] := RdcDefaultTailnetHostName;
  if lEdit.Def.Ephemeral then
    aItem.SubItems[1] := _('ja')
  else
    aItem.SubItems[1] := _('nee');
  if lEdit.NewAuthKey <> '' then
    aItem.SubItems[2] := _('nieuw')
  else if lEdit.HasStoredAuthKey and not lEdit.ClearAuthKey and not ControlUrlChanged(lEdit) then
    aItem.SubItems[2] := _('in de kluis')
  else
    aItem.SubItems[2] := _('geen (browser)');
end;

function TfrmTailnets.SelectedEdit: TRdcTailnetEdit;
begin
  if lvTailnets.Selected <> nil then
    Result := TRdcTailnetEdit(lvTailnets.Selected.Data)
  else
    Result := nil;
end;

procedure TfrmTailnets.ShowSelected;
var
  lEdit: TRdcTailnetEdit;
begin
  if FLoading then
    Exit;
  lEdit := SelectedEdit;
  FLoading := True;
  try
    if lEdit <> nil then
    begin
      edtName.Text := lEdit.Def.Name;
      edtNodeHost.Text := lEdit.Def.NodeHostName;
      edtAuthKey.Text := lEdit.NewAuthKey;
      chkEphemeral.Checked := lEdit.Def.Ephemeral;
      chkMatchHostName.Checked := lEdit.MatchHostName;
      chkAllowShared.Checked := lEdit.AllowShared;
      edtControlUrl.Text := lEdit.Def.ControlUrl;
      edtLocalAddress.Text := lEdit.Def.LocalAddress;
    end
    else
    begin
      edtName.Text := '';
      edtNodeHost.Text := '';
      edtAuthKey.Text := '';
      chkEphemeral.Checked := False;
      chkMatchHostName.Checked := False;
      chkAllowShared.Checked := False;
      edtControlUrl.Text := '';
      edtLocalAddress.Text := '';
    end;
  finally
    FLoading := False;
  end;
  edtNodeHost.TextHint := RdcDefaultTailnetHostName;
  if (lEdit <> nil) and lEdit.HasStoredAuthKey and not lEdit.ClearAuthKey and ControlUrlChanged(lEdit) then
    edtAuthKey.TextHint := _('control URL gewijzigd: opgeslagen key wordt gewist')
  else if (lEdit <> nil) and lEdit.HasStoredAuthKey and not lEdit.ClearAuthKey then
    edtAuthKey.TextHint := _('opgeslagen in de wachtwoordkluis')
  else
    edtAuthKey.TextHint := _('tskey-auth-... (leeg = inloggen via de browser)');
  UpdateButtons;
end;

procedure TfrmTailnets.UpdateButtons;
var
  lEdit: TRdcTailnetEdit;
  lEnabled: Boolean;
begin
  lEdit := SelectedEdit;
  lEnabled := (lEdit <> nil) and not IsTesting;
  edtName.Enabled := lEnabled;
  edtNodeHost.Enabled := lEnabled;
  edtAuthKey.Enabled := lEnabled;
  btnClearAuthKey.Enabled := lEnabled and ((lEdit.NewAuthKey <> '') or (lEdit.HasStoredAuthKey and not lEdit.ClearAuthKey));
  chkEphemeral.Enabled := lEnabled;
  chkMatchHostName.Enabled := lEnabled;
  chkAllowShared.Enabled := lEnabled;
  edtControlUrl.Enabled := lEnabled;
  edtLocalAddress.Enabled := lEnabled;
  btnDelete.Enabled := lEnabled;
  btnAdd.Enabled := not IsTesting;
  lvTailnets.Enabled := not IsTesting;
  btnTest.Enabled := (lEdit <> nil) and TRdcTsBridge.Available;
  if IsTesting then
    btnTest.Caption := _('Test stoppen')
  else
    btnTest.Caption := _('Test verbinding');
end;

procedure TfrmTailnets.StoreFields;
var
  lEdit: TRdcTailnetEdit;
begin
  lEdit := SelectedEdit;
  if FLoading or (lEdit = nil) then
    Exit;
  lEdit.Def.Name := Trim(edtName.Text);
  lEdit.Def.NodeHostName := Trim(edtNodeHost.Text);
  if edtAuthKey.Text <> lEdit.NewAuthKey then
  begin
    WipeString(lEdit.NewAuthKey);
    lEdit.NewAuthKey := Trim(edtAuthKey.Text);
    if lEdit.NewAuthKey <> '' then
      lEdit.ClearAuthKey := False;
  end;
  lEdit.Def.Ephemeral := chkEphemeral.Checked;
  lEdit.MatchHostName := chkMatchHostName.Checked;
  lEdit.AllowShared := chkAllowShared.Checked;
  lEdit.Def.ControlUrl := Trim(edtControlUrl.Text);
  lEdit.Def.LocalAddress := Trim(edtLocalAddress.Text);
  UpdateListItem(lvTailnets.Selected);
  UpdateButtons;
  FChanged := True;
end;

function TfrmTailnets.UniqueName(const aBase: string): string;
var
  lEdit: TRdcTailnetEdit;
  lNumber: Integer;
  lUsed: Boolean;
begin
  lNumber := 1;
  Result := aBase;
  repeat
    lUsed := False;
    for lEdit in FEdits do
      if SameText(lEdit.Def.Name, Result) then
        lUsed := True;
    if lUsed then
    begin
      Inc(lNumber);
      Result := Format('%s %d', [aBase, lNumber]);
    end;
  until not lUsed;
end;

procedure TfrmTailnets.AddTailnet;
var
  lEdit: TRdcTailnetEdit;
begin
  lEdit := TRdcTailnetEdit.Create;
  lEdit.IsNew := True;
  lEdit.Def.Id := TGUID.NewGuid.ToString;
  lEdit.Def.Name := UniqueName(_('Nieuw netwerk'));
  FEdits.Add(lEdit);
  FChanged := True;
  FillList(lEdit);
  edtName.SetFocus;
  edtName.SelectAll;
end;

procedure TfrmTailnets.DeleteSelectedTailnet;
var
  lEdit: TRdcTailnetEdit;
  lUsage: Integer;
begin
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  if not lEdit.IsNew then
  begin
    lUsage := FFile.TailnetUsageCount(lEdit.Def.Id);
    if lUsage > 0 then
    begin
      MessageDlg(Format(_('Netwerk "%s" wordt nog gebruikt door %d route(s) in dit bestand. Kies daar eerst een andere route.'), [lEdit.Def.Name, lUsage]), mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  if FManager.RefCount(lEdit.Def.Id) > 0 then
  begin
    MessageDlg(Format(_('Netwerk "%s" is in gebruik door een open sessie. Sluit die eerst.'), [lEdit.Def.Name]), mtWarning, [mbOK], 0);
    Exit;
  end;
  if MessageDlg(Format(_('Netwerk "%s" verwijderen?'#13#10#13#10'De auth key en de sleutels van dit netwerk worden van deze pc gewist.'), [lEdit.Def.Name]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not lEdit.IsNew then
    FDeletedIds.Add(lEdit.Def.Id);
  FEdits.Remove(lEdit);
  FChanged := True;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
end;

procedure TfrmTailnets.ClearSelectedAuthKey;
var
  lEdit: TRdcTailnetEdit;
begin
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  WipeString(lEdit.NewAuthKey);
  lEdit.ClearAuthKey := lEdit.HasStoredAuthKey;
  FChanged := True;
  ShowSelected;
  UpdateListItem(lvTailnets.Selected);
end;

function TfrmTailnets.ValidateEdit(aEdit: TRdcTailnetEdit; out aControl: TWinControl; out aMessage: string): Boolean;
var
  lOther: TRdcTailnetEdit;
begin
  Result := False;
  aControl := nil;
  if aEdit.Def.Name = '' then
  begin
    aControl := edtName;
    aMessage := _('Elk netwerk moet een naam hebben.');
    Exit;
  end;
  for lOther in FEdits do
    if (lOther <> aEdit) and SameText(lOther.Def.Name, aEdit.Def.Name) then
    begin
      aControl := edtName;
      aMessage := Format(_('Er zijn twee netwerken met de naam "%s".'), [aEdit.Def.Name]);
      Exit;
    end;
  if (aEdit.Def.NodeHostName <> '') and not RdcIsValidNodeHostName(aEdit.Def.NodeHostName) then
  begin
    aControl := edtNodeHost;
    aMessage := _('De naam in het tailnet mag alleen kleine letters, cijfers en streepjes bevatten (max. 63 tekens, niet beginnen of eindigen met een streepje).');
    Exit;
  end;
  if (aEdit.NewAuthKey <> '') and not aEdit.NewAuthKey.StartsWith('tskey-') then
  begin
    aControl := edtAuthKey;
    aMessage := _('Een auth key begint met "tskey-" (bijv. tskey-auth-...).');
    Exit;
  end;
  if not RdcIsValidControlUrl(aEdit.Def.ControlUrl) then
  begin
    aControl := edtControlUrl;
    aMessage := _('De control URL moet met https:// beginnen (http:// alleen naar localhost): anders kan de auth key onderweg worden onderschept.');
    Exit;
  end;
  if (aEdit.Def.LocalAddress <> '') and not RdcIsValidLoopbackAddress(aEdit.Def.LocalAddress) then
  begin
    aControl := edtLocalAddress;
    aMessage := _('Het lokale adres moet een loopback-adres zijn (127.x.x.x), bijv. 127.0.0.2.');
    Exit;
  end;
  if (aEdit.NewAuthKey <> '') and not FSecrets.CanStoreSecrets then
  begin
    aControl := edtAuthKey;
    aMessage := _('Een auth key kan alleen in de wachtwoordkluis worden bewaard. Zet "Wachtwoorden onthouden" aan in Opties, of laat het veld leeg (dan log je in via de browser).');
    Exit;
  end;
  Result := True;
end;

function TfrmTailnets.ValidateAll: Boolean;
var
  lControl: TWinControl;
  lEdit: TRdcTailnetEdit;
  lMessage: string;
begin
  StoreFields;
  for lEdit in FEdits do
    if not ValidateEdit(lEdit, lControl, lMessage) then
    begin
      FillList(lEdit);
      if (lControl <> nil) and lControl.CanFocus then
        lControl.SetFocus;
      MessageDlg(lMessage, mtWarning, [mbOK], 0);
      Exit(False);
    end;
  Result := True;
end;

function TfrmTailnets.ControlUrlChanged(aEdit: TRdcTailnetEdit): Boolean;
begin
  Result := not aEdit.IsNew and (TRdcPasswordVault.NormalizeControlUrl(aEdit.Def.ControlUrl) <> TRdcPasswordVault.NormalizeControlUrl(aEdit.OriginalControlUrl));
end;

function TfrmTailnets.SaveSecrets: Boolean;
var
  lEdit: TRdcTailnetEdit;
begin
  // Vóór ApplyToFile: mislukt het (kluis niet ontgrendeld), dan blijft het venster open en verandert er niets.
  // Andere control server: de opgeslagen key en sleutels horen bij de oude server en worden gewist.
  for lEdit in FEdits do
    if ControlUrlChanged(lEdit) then
    begin
      if lEdit.HasStoredAuthKey or FSecrets.HasSecret(TRdcPasswordVault.TailnetStateKeyTarget(lEdit.Def.Id, lEdit.OriginalControlUrl)) then
        if MessageDlg(Format(_('De control URL van "%s" is gewijzigd.'#13#10#13#10'De opgeslagen auth key en sleutels horen bij de oude server en worden gewist; daarna is een nieuwe auth key of opnieuw inloggen nodig. Doorgaan?'), [lEdit.Def.Name]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        begin
          FillList(lEdit);
          Exit(False);
        end;
      DeleteLocalData(lEdit.Def.Id, True);
      lEdit.HasStoredAuthKey := False;
      lEdit.OriginalControlUrl := lEdit.Def.ControlUrl;
    end;
  for lEdit in FEdits do
    if lEdit.NewAuthKey <> '' then
    begin
      if not FSecrets.SaveSecret(TRdcPasswordVault.TailnetAuthKeyTarget(lEdit.Def.Id, lEdit.Def.ControlUrl), 'Tailscale ' + lEdit.Def.Name, lEdit.NewAuthKey, Format(_('De auth key van "%s" wordt in de wachtwoordkluis opgeslagen.'), [lEdit.Def.Name])) then
      begin
        FillList(lEdit);
        MessageDlg(Format(_('De auth key van "%s" kon niet in de wachtwoordkluis worden opgeslagen.'), [lEdit.Def.Name]), mtWarning, [mbOK], 0);
        Exit(False);
      end;
      WipeString(lEdit.NewAuthKey);
      lEdit.HasStoredAuthKey := True;
      lEdit.ClearAuthKey := False;
    end
    else if lEdit.ClearAuthKey then
    begin
      FSecrets.DeleteSecret(TRdcPasswordVault.TailnetAuthKeyTarget(lEdit.Def.Id, lEdit.Def.ControlUrl));
      lEdit.HasStoredAuthKey := False;
      lEdit.ClearAuthKey := False;
    end;
  Result := True;
end;

procedure TfrmTailnets.DeleteLocalData(const aId: string; aForce: Boolean);
var
  lDir: string;
begin
  if not aForce and Assigned(FIdInUseElsewhere) and FIdInUseElsewhere(aId) then
    Exit;
  FSecrets.DeleteSecretsWithPrefix(TRdcPasswordVault.TailnetTargetPrefix(aId));
  lDir := RdcTailnetDir(aId);
  try
    if TDirectory.Exists(lDir) then
      TDirectory.Delete(lDir, True);
  except
    // Werkmap (versleuteld) kon niet weg; niet erg.
  end;
end;

procedure TfrmTailnets.ApplyToFile;
var
  lDef: TRdcTailnetDef;
  lEdit: TRdcTailnetEdit;
  lId: string;
  lIndex: Integer;
begin
  for lId in FDeletedIds do
  begin
    for lIndex := FFile.Tailnets.Count - 1 downto 0 do
      if SameText(FFile.Tailnets[lIndex].Id, lId) then
        FFile.Tailnets.Delete(lIndex);
    DeleteLocalData(lId, False);
  end;
  for lEdit in FEdits do
  begin
    lDef := FFile.FindTailnet(lEdit.Def.Id);
    if lDef = nil then
    begin
      lDef := TRdcTailnetDef.Create;
      FFile.Tailnets.Add(lDef);
    end;
    lDef.Assign(lEdit.Def);
  end;
end;

procedure TfrmTailnets.ApplyOptions;

  procedure RemoveId(aList: TStringList; const aId: string);
  var
    lIndex: Integer;
  begin
    for lIndex := aList.Count - 1 downto 0 do
      if aList[lIndex].StartsWith(LowerCase(Trim(aId)) + ':', True) then
        aList.Delete(lIndex);
  end;

var
  lEdit: TRdcTailnetEdit;
  lId: string;
  lKey: string;
begin
  // Stored per id + control URL; old bindings of these ids (other control URL, deleted network) are dropped.
  for lId in FDeletedIds do
  begin
    RemoveId(FSettings.TailnetHostNameMatch, lId);
    RemoveId(FSettings.TailnetAllowShared, lId);
  end;
  for lEdit in FEdits do
  begin
    RemoveId(FSettings.TailnetHostNameMatch, lEdit.Def.Id);
    RemoveId(FSettings.TailnetAllowShared, lEdit.Def.Id);
    lKey := TRdcPasswordVault.TailnetBindingKey(lEdit.Def.Id, lEdit.Def.ControlUrl);
    if lEdit.MatchHostName then
      FSettings.TailnetHostNameMatch.Add(lKey);
    if lEdit.AllowShared then
      FSettings.TailnetAllowShared.Add(lKey);
  end;
end;

{ Test }

function TfrmTailnets.IsTesting: Boolean;
begin
  Result := FTestId <> '';
end;

procedure TfrmTailnets.ToggleTest;
begin
  if IsTesting then
    StopTest(_('Test gestopt.'))
  else
    StartTest;
end;

procedure TfrmTailnets.StartTest;
var
  lConfig: TRdcTailnetConfig;
  lControl: TWinControl;
  lEdit: TRdcTailnetEdit;
  lError: string;
  lGuard: IRdcCallbackGuard;
  lMessage: string;
begin
  StoreFields;
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  // De auth key hoeft voor een test niet in de kluis te kunnen: alleen de vorm controleren.
  if not ValidateEdit(lEdit, lControl, lMessage) and (lControl <> edtAuthKey) then
  begin
    if (lControl <> nil) and lControl.CanFocus then
      lControl.SetFocus;
    MessageDlg(lMessage, mtWarning, [mbOK], 0);
    Exit;
  end;
  if (lEdit.NewAuthKey <> '') and not lEdit.NewAuthKey.StartsWith('tskey-') then
  begin
    MessageDlg(_('Een auth key begint met "tskey-" (bijv. tskey-auth-...).'), mtWarning, [mbOK], 0);
    Exit;
  end;
  if not RdcBuildTailnetConfig(lEdit.Def, FSecrets, lEdit.NewAuthKey, lConfig, lError) then
  begin
    lblTestStatus.Caption := lError;
    Exit;
  end;
  lConfig.MatchHostName := lEdit.MatchHostName;
  lConfig.AllowShared := lEdit.AllowShared;
  FTestId := lEdit.Def.Id;
  FTestGuard := RdcNewCallbackGuard;
  FAuthUrlOpened := '';
  lGuard := FTestGuard;
  if FManager.RefCount(FTestId) > 0 then
    lblTestStatus.Caption := _('Dit netwerk is al actief voor een open sessie; status ophalen...')
  else
    lblTestStatus.Caption := _('Verbinden met het tailnet...');
  UpdateButtons;
  // Acquire wist lConfig (geheimen) na gebruik.
  FManager.Acquire(lConfig,
    procedure(aSuccess: Boolean; const aError: string)
    begin
      if lGuard.IsValid then
        TestFinished(aSuccess, aError);
    end);
  tmrTest.Enabled := True;
end;

procedure TfrmTailnets.ShowTestProgress;
var
  lStatus: TRdcTailnetStatus;
begin
  if not IsTesting or not FManager.TryStatus(FTestId, lStatus) then
    Exit;
  if lStatus.AuthUrl <> '' then
  begin
    // Interactief inloggen: de login-pagina één keer in de browser openen.
    if lStatus.AuthUrl <> FAuthUrlOpened then
    begin
      FAuthUrlOpened := lStatus.AuthUrl;
      if not RdcOpenAuthUrl(lStatus.AuthUrl) then
      begin
        StopTest(_('De control server gaf een ongeldig login-adres (geen https); niet geopend.'));
        Exit;
      end;
    end;
    lblTestStatus.Caption := Format(_('Inloggen nodig: de login-pagina is in de browser geopend.'#13#10'%s'), [lStatus.AuthUrl]);
  end
  else if lStatus.State <> '' then
    lblTestStatus.Caption := Format(_('Verbinden met het tailnet... (%s)'), [lStatus.State]);
end;

procedure TfrmTailnets.TestFinished(aSuccess: Boolean; const aError: string);
var
  lStatus: TRdcTailnetStatus;
  lText: string;
begin
  if not IsTesting then
    Exit;
  if aSuccess and FManager.TryStatus(FTestId, lStatus) then
  begin
    lText := Format(_('Verbonden. Adres in het tailnet: %s'), [string.Join(', ', lStatus.IPs)]);
    if lStatus.DnsName <> '' then
      lText := lText + #13#10 + Format(_('Naam: %s'), [lStatus.DnsName]);
  end
  else if aSuccess then
    lText := _('Verbonden.')
  else
    lText := Format(_('Niet gelukt: %s'), [aError]);
  StopTest(lText);
end;

procedure TfrmTailnets.StopTest(const aText: string);
var
  lId: string;
begin
  tmrTest.Enabled := False;
  if FTestGuard <> nil then
    FTestGuard.Invalidate;
  FTestGuard := nil;
  lId := FTestId;
  FTestId := '';
  // Weer vrijgeven: het netwerk sluit als geen sessie het gebruikt (een lopende start wordt afgebroken).
  if lId <> '' then
    FManager.Release(lId);
  if aText <> '' then
    lblTestStatus.Caption := aText;
  if not (csDestroying in ComponentState) then
    UpdateButtons;
end;

end.
