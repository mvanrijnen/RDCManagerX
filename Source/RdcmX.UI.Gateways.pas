unit RdcmX.UI.Gateways;

{
  Beheer van de RD Gateways van één bestand (TRdcFile.Gateways; sidecar of .rdcx). Het wachtwoord voor "eigen
  aanmeldgegevens" staat alleen in de wachtwoordkluis van deze pc (TRdcPasswordVault.GatewayTarget), nooit in het
  bestand.

  Werkt zoals RdcmX.UI.Tailnets: op kopieën; bij OK eerst de geheimen (kan om het hoofdwachtwoord vragen), dan de
  definities. Verwijderen kan alleen als geen route meer naar de gateway verwijst.
}

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.UITypes,
  Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.Credentials, RdcmX.Model;

type
  TRdcGatewayEdit = class
  public
    Def: TRdcGatewayDef;
    IsNew: Boolean;
    /// <summary>host:poort bij openen: het wachtwoord is daaraan gebonden.</summary>
    OriginalAddress: string;
    /// <summary>Net ingevoerd wachtwoord (nog niet opgeslagen).</summary>
    NewPassword: string;
    HasStoredPassword: Boolean;
    ClearPassword: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

  TfrmGateways = class(TForm)
    lvGateways: TListView;
    btnAdd: TButton;
    btnDelete: TButton;
    lblName: TLabel;
    edtName: TEdit;
    lblHostName: TLabel;
    edtHostName: TEdit;
    lblPort: TLabel;
    edtPort: TEdit;
    lblUsage: TLabel;
    cbUsage: TComboBox;
    lblCredsMode: TLabel;
    cbCredsMode: TComboBox;
    lblAuthMethod: TLabel;
    cbAuthMethod: TComboBox;
    lblUserName: TLabel;
    edtUserName: TEdit;
    lblDomain: TLabel;
    edtDomain: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    btnClearPassword: TButton;
    lblHint: TLabel;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure lvGatewaysSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnAddClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnClearPasswordClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
  private
    FFile: TRdcFile;
    FSecrets: IRdcSecretAccess;
    FIdInUseElsewhere: TFunc<string, Boolean>;
    FEdits: TObjectList<TRdcGatewayEdit>;
    FDeletedIds: TList<string>;
    FChanged: Boolean;
    FLoading: Boolean;
    procedure LoadGateways;
    procedure FillList(aSelect: TRdcGatewayEdit);
    procedure UpdateListItem(aItem: TListItem);
    function SelectedEdit: TRdcGatewayEdit;
    procedure ShowSelected;
    procedure UpdateControls;
    procedure StoreFields;
    procedure AddGateway;
    procedure DeleteSelectedGateway;
    procedure ClearSelectedPassword;
    function UniqueName(const aBase: string): string;
    function ValidateAll: Boolean;
    function SaveSecrets: Boolean;
    function AddressChanged(aEdit: TRdcGatewayEdit): Boolean;
    procedure ApplyToFile;
  protected
    /// <summary>Translates the DFM texts after loading, before OnCreate.</summary>
    procedure DoCreate; override;
  public
    /// <summary>True als er iets gewijzigd is (en toegepast op het bestand).</summary>
    class function Execute(aFile: TRdcFile; const aSecrets: IRdcSecretAccess; const aIdInUseElsewhere: TFunc<string, Boolean>): Boolean; static;
  end;

implementation

uses
  RdcmX.Lang;

{$R *.dfm}

/// <summary>Short caption of a credentials mode for the list, in the active language.</summary>
function GatewayCredsModeCaption(aMode: TRdcGatewayCredsMode): string;
begin
  case aMode of
    gcmSession: Result := _('Sessie');
    gcmSeparate: Result := _('Eigen');
    gcmAsk: Result := _('Vragen');
  else
    Result := _('Smartcard');
  end;
end;

{ TRdcGatewayEdit }

constructor TRdcGatewayEdit.Create;
begin
  inherited Create;
  Def := TRdcGatewayDef.Create;
end;

destructor TRdcGatewayEdit.Destroy;
begin
  WipeString(NewPassword);
  Def.Free;
  inherited;
end;

{ TfrmGateways }

class function TfrmGateways.Execute(aFile: TRdcFile; const aSecrets: IRdcSecretAccess; const aIdInUseElsewhere: TFunc<string, Boolean>): Boolean;
var
  lForm: TfrmGateways;
begin
  lForm := TfrmGateways.Create(Application);
  try
    lForm.FFile := aFile;
    lForm.FSecrets := aSecrets;
    lForm.FIdInUseElsewhere := aIdInUseElsewhere;
    lForm.LoadGateways;
    Result := (lForm.ShowModal = mrOk) and lForm.FChanged;
    if Result then
      lForm.ApplyToFile;
  finally
    lForm.Free;
  end;
end;

procedure TfrmGateways.DoCreate;
begin
  // Translate the DFM texts before OnCreate runs.
  TranslateComponent(Self);
  inherited;
end;

procedure TfrmGateways.FormCreate(Sender: TObject);
begin
  FEdits := TObjectList<TRdcGatewayEdit>.Create(True);
  FDeletedIds := TList<string>.Create;
end;

procedure TfrmGateways.FormDestroy(Sender: TObject);
begin
  FDeletedIds.Free;
  FEdits.Free;
end;

procedure TfrmGateways.FormShow(Sender: TObject);
begin
  ShowSelected;
end;

procedure TfrmGateways.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (ModalResult <> mrOk) or (ValidateAll and SaveSecrets);
end;

procedure TfrmGateways.lvGatewaysSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  ShowSelected;
end;

procedure TfrmGateways.btnAddClick(Sender: TObject);
begin
  AddGateway;
end;

procedure TfrmGateways.btnDeleteClick(Sender: TObject);
begin
  DeleteSelectedGateway;
end;

procedure TfrmGateways.btnClearPasswordClick(Sender: TObject);
begin
  ClearSelectedPassword;
end;

procedure TfrmGateways.FieldChange(Sender: TObject);
begin
  StoreFields;
end;

procedure TfrmGateways.LoadGateways;
var
  lDef: TRdcGatewayDef;
  lEdit: TRdcGatewayEdit;
begin
  Caption := Format(_('RDP-gateways - %s'), [FFile.Caption]);
  for lDef in FFile.Gateways do
  begin
    lEdit := TRdcGatewayEdit.Create;
    lEdit.Def.Assign(lDef);
    lEdit.OriginalAddress := lDef.Address;
    lEdit.HasStoredPassword := FSecrets.HasSecret(TRdcPasswordVault.GatewayTarget(lDef.Id, lDef.Address));
    FEdits.Add(lEdit);
  end;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
end;

procedure TfrmGateways.FillList(aSelect: TRdcGatewayEdit);
var
  lEdit: TRdcGatewayEdit;
  lItem: TListItem;
begin
  FLoading := True;
  lvGateways.Items.BeginUpdate;
  try
    lvGateways.Items.Clear;
    for lEdit in FEdits do
    begin
      lItem := lvGateways.Items.Add;
      lItem.Data := lEdit;
      lItem.SubItems.Add('');
      lItem.SubItems.Add('');
      UpdateListItem(lItem);
      if lEdit = aSelect then
        lItem.Selected := True;
    end;
  finally
    lvGateways.Items.EndUpdate;
    FLoading := False;
  end;
  if lvGateways.Selected <> nil then
    lvGateways.Selected.MakeVisible(False);
  ShowSelected;
end;

procedure TfrmGateways.UpdateListItem(aItem: TListItem);
var
  lEdit: TRdcGatewayEdit;
begin
  lEdit := TRdcGatewayEdit(aItem.Data);
  aItem.Caption := lEdit.Def.Name;
  aItem.SubItems[0] := lEdit.Def.Address;
  aItem.SubItems[1] := GatewayCredsModeCaption(lEdit.Def.CredsMode);
end;

function TfrmGateways.SelectedEdit: TRdcGatewayEdit;
begin
  if lvGateways.Selected <> nil then
    Result := TRdcGatewayEdit(lvGateways.Selected.Data)
  else
    Result := nil;
end;

procedure TfrmGateways.ShowSelected;
var
  lEdit: TRdcGatewayEdit;
begin
  if FLoading then
    Exit;
  lEdit := SelectedEdit;
  FLoading := True;
  try
    if lEdit <> nil then
    begin
      edtName.Text := lEdit.Def.Name;
      edtHostName.Text := lEdit.Def.HostName;
      if lEdit.Def.Port > 0 then
        edtPort.Text := IntToStr(lEdit.Def.Port)
      else
        edtPort.Text := '';
      cbUsage.ItemIndex := Ord(lEdit.Def.Usage);
      cbCredsMode.ItemIndex := Ord(lEdit.Def.CredsMode);
      cbAuthMethod.ItemIndex := Ord(lEdit.Def.AuthMethod);
      edtUserName.Text := lEdit.Def.UserName;
      edtDomain.Text := lEdit.Def.Domain;
      edtPassword.Text := lEdit.NewPassword;
    end
    else
    begin
      edtName.Text := '';
      edtHostName.Text := '';
      edtPort.Text := '';
      cbUsage.ItemIndex := -1;
      cbCredsMode.ItemIndex := -1;
      cbAuthMethod.ItemIndex := -1;
      edtUserName.Text := '';
      edtDomain.Text := '';
      edtPassword.Text := '';
    end;
  finally
    FLoading := False;
  end;
  UpdateControls;
end;

procedure TfrmGateways.UpdateControls;
var
  lEdit: TRdcGatewayEdit;
  lOwn: Boolean;
begin
  lEdit := SelectedEdit;
  lOwn := (lEdit <> nil) and (lEdit.Def.CredsMode = gcmSeparate);
  edtName.Enabled := lEdit <> nil;
  edtHostName.Enabled := lEdit <> nil;
  edtPort.Enabled := lEdit <> nil;
  cbUsage.Enabled := lEdit <> nil;
  cbCredsMode.Enabled := lEdit <> nil;
  // Bij smartcard ligt de methode vast.
  cbAuthMethod.Enabled := (lEdit <> nil) and (lEdit.Def.CredsMode <> gcmSmartCard);
  edtUserName.Enabled := lOwn;
  edtDomain.Enabled := lOwn;
  edtPassword.Enabled := lOwn;
  btnClearPassword.Enabled := lOwn and ((lEdit.NewPassword <> '') or (lEdit.HasStoredPassword and not lEdit.ClearPassword));
  if (lEdit <> nil) and lEdit.HasStoredPassword and not lEdit.ClearPassword and AddressChanged(lEdit) then
    edtPassword.TextHint := _('server gewijzigd: opgeslagen wachtwoord wordt gewist')
  else if (lEdit <> nil) and lEdit.HasStoredPassword and not lEdit.ClearPassword then
    edtPassword.TextHint := _('opgeslagen in de wachtwoordkluis')
  else
    edtPassword.TextHint := _('leeg = vragen bij verbinden');
  btnDelete.Enabled := lEdit <> nil;
end;

procedure TfrmGateways.StoreFields;
var
  lEdit: TRdcGatewayEdit;
begin
  lEdit := SelectedEdit;
  if FLoading or (lEdit = nil) then
    Exit;
  lEdit.Def.Name := Trim(edtName.Text);
  lEdit.Def.HostName := Trim(edtHostName.Text);
  lEdit.Def.Port := StrToIntDef(Trim(edtPort.Text), 0);
  if cbUsage.ItemIndex >= 0 then
    lEdit.Def.Usage := TRdcGatewayUsage(cbUsage.ItemIndex);
  if cbCredsMode.ItemIndex >= 0 then
    lEdit.Def.CredsMode := TRdcGatewayCredsMode(cbCredsMode.ItemIndex);
  if lEdit.Def.CredsMode = gcmSmartCard then
  begin
    lEdit.Def.AuthMethod := glmSmartCard;
    if cbAuthMethod.ItemIndex <> Ord(glmSmartCard) then
    begin
      FLoading := True;
      try
        cbAuthMethod.ItemIndex := Ord(glmSmartCard);
      finally
        FLoading := False;
      end;
    end;
  end
  else if cbAuthMethod.ItemIndex >= 0 then
    lEdit.Def.AuthMethod := TRdcGatewayLogonMethod(cbAuthMethod.ItemIndex);
  lEdit.Def.UserName := Trim(edtUserName.Text);
  lEdit.Def.Domain := Trim(edtDomain.Text);
  if edtPassword.Text <> lEdit.NewPassword then
  begin
    WipeString(lEdit.NewPassword);
    lEdit.NewPassword := edtPassword.Text;
    if lEdit.NewPassword <> '' then
      lEdit.ClearPassword := False;
  end;
  UpdateListItem(lvGateways.Selected);
  UpdateControls;
  FChanged := True;
end;

function TfrmGateways.UniqueName(const aBase: string): string;
var
  lEdit: TRdcGatewayEdit;
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

procedure TfrmGateways.AddGateway;
var
  lEdit: TRdcGatewayEdit;
begin
  lEdit := TRdcGatewayEdit.Create;
  lEdit.IsNew := True;
  lEdit.Def.Id := TGUID.NewGuid.ToString;
  lEdit.Def.Name := UniqueName(_('Nieuwe gateway'));
  FEdits.Add(lEdit);
  FChanged := True;
  FillList(lEdit);
  edtName.SetFocus;
  edtName.SelectAll;
end;

procedure TfrmGateways.DeleteSelectedGateway;
var
  lEdit: TRdcGatewayEdit;
  lUsage: Integer;
begin
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  if not lEdit.IsNew then
  begin
    lUsage := FFile.GatewayUsageCount(lEdit.Def.Id);
    if lUsage > 0 then
    begin
      MessageDlg(Format(_('Gateway "%s" wordt nog gebruikt door %d route(s) in dit bestand. Kies daar eerst een andere route.'), [lEdit.Def.Name, lUsage]), mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  if not lEdit.IsNew then
    FDeletedIds.Add(lEdit.Def.Id);
  FEdits.Remove(lEdit);
  FChanged := True;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
end;

procedure TfrmGateways.ClearSelectedPassword;
var
  lEdit: TRdcGatewayEdit;
begin
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  WipeString(lEdit.NewPassword);
  lEdit.ClearPassword := lEdit.HasStoredPassword;
  FChanged := True;
  ShowSelected;
end;

function TfrmGateways.ValidateAll: Boolean;

  function Fail(aEdit: TRdcGatewayEdit; aControl: TWinControl; const aMessage: string): Boolean;
  begin
    FillList(aEdit);
    if aControl.CanFocus then
      aControl.SetFocus;
    MessageDlg(aMessage, mtWarning, [mbOK], 0);
    Result := False;
  end;

var
  lEdit: TRdcGatewayEdit;
  lOther: TRdcGatewayEdit;
begin
  StoreFields;
  for lEdit in FEdits do
  begin
    if lEdit.Def.Name = '' then
      Exit(Fail(lEdit, edtName, _('Elke gateway moet een naam hebben.')));
    for lOther in FEdits do
      if (lOther <> lEdit) and SameText(lOther.Def.Name, lEdit.Def.Name) then
        Exit(Fail(lEdit, edtName, Format(_('Er zijn twee gateways met de naam "%s".'), [lEdit.Def.Name])));
    if lEdit.Def.HostName = '' then
      Exit(Fail(lEdit, edtHostName, _('Vul de gatewayserver in.')));
    if (lEdit.Def.HostName.Contains(':') or lEdit.Def.HostName.Contains('/')) then
      Exit(Fail(lEdit, edtHostName, _('Vul bij de gatewayserver alleen de naam in; de poort heeft een eigen veld.')));
    if (lEdit.Def.Port <> 0) and ((lEdit.Def.Port < 1) or (lEdit.Def.Port > 65535)) then
      Exit(Fail(lEdit, edtPort, _('De poort moet tussen 1 en 65535 liggen (leeg = 443).')));
    if (lEdit.Def.CredsMode = gcmSeparate) and (lEdit.Def.UserName = '') then
      Exit(Fail(lEdit, edtUserName, _('Vul de gebruikersnaam voor de gateway in.')));
    if (lEdit.NewPassword <> '') and not FSecrets.CanStoreSecrets then
      Exit(Fail(lEdit, edtPassword, _('Het gateway-wachtwoord kan alleen in de wachtwoordkluis worden bewaard. Zet "Wachtwoorden onthouden" aan in Opties, of laat het veld leeg (dan wordt erom gevraagd bij verbinden).')));
  end;
  Result := True;
end;

function TfrmGateways.AddressChanged(aEdit: TRdcGatewayEdit): Boolean;
begin
  Result := not aEdit.IsNew and not SameText(Trim(aEdit.Def.Address), Trim(aEdit.OriginalAddress));
end;

function TfrmGateways.SaveSecrets: Boolean;
var
  lEdit: TRdcGatewayEdit;
begin
  // Andere gatewayserver/poort: het opgeslagen wachtwoord hoort bij de oude server en wordt gewist (het mag nooit
  // naar een andere server gaan).
  for lEdit in FEdits do
    if AddressChanged(lEdit) then
    begin
      if lEdit.HasStoredPassword and (lEdit.NewPassword = '') then
        if MessageDlg(Format(_('De server van gateway "%s" is gewijzigd.'#13#10#13#10'Het opgeslagen wachtwoord hoort bij de oude server en wordt gewist. Doorgaan?'), [lEdit.Def.Name]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
        begin
          FillList(lEdit);
          Exit(False);
        end;
      FSecrets.DeleteSecretsWithPrefix(TRdcPasswordVault.GatewayTargetPrefix(lEdit.Def.Id));
      lEdit.HasStoredPassword := False;
      lEdit.OriginalAddress := lEdit.Def.Address;
    end;
  for lEdit in FEdits do
    if (lEdit.NewPassword <> '') and (lEdit.Def.CredsMode = gcmSeparate) then
    begin
      if not FSecrets.SaveSecret(TRdcPasswordVault.GatewayTarget(lEdit.Def.Id, lEdit.Def.Address), 'Gateway ' + lEdit.Def.Name, lEdit.NewPassword, Format(_('Het wachtwoord voor gateway "%s" wordt in de wachtwoordkluis opgeslagen.'), [lEdit.Def.Name])) then
      begin
        FillList(lEdit);
        MessageDlg(Format(_('Het wachtwoord voor gateway "%s" kon niet in de wachtwoordkluis worden opgeslagen.'), [lEdit.Def.Name]), mtWarning, [mbOK], 0);
        Exit(False);
      end;
      WipeString(lEdit.NewPassword);
      lEdit.HasStoredPassword := True;
      lEdit.ClearPassword := False;
    end
    else if lEdit.ClearPassword or ((lEdit.Def.CredsMode <> gcmSeparate) and lEdit.HasStoredPassword) then
    begin
      // Gewist, of geen eigen aanmeldgegevens meer: het opgeslagen wachtwoord is niet meer nodig.
      FSecrets.DeleteSecretsWithPrefix(TRdcPasswordVault.GatewayTargetPrefix(lEdit.Def.Id));
      lEdit.HasStoredPassword := False;
      lEdit.ClearPassword := False;
    end;
  Result := True;
end;

procedure TfrmGateways.ApplyToFile;
var
  lDef: TRdcGatewayDef;
  lEdit: TRdcGatewayEdit;
  lId: string;
  lIndex: Integer;
begin
  for lId in FDeletedIds do
  begin
    for lIndex := FFile.Gateways.Count - 1 downto 0 do
      if SameText(FFile.Gateways[lIndex].Id, lId) then
        FFile.Gateways.Delete(lIndex);
    if not (Assigned(FIdInUseElsewhere) and FIdInUseElsewhere(lId)) then
      FSecrets.DeleteSecretsWithPrefix(TRdcPasswordVault.GatewayTargetPrefix(lId));
  end;
  for lEdit in FEdits do
  begin
    lDef := FFile.FindGateway(lEdit.Def.Id);
    if lDef = nil then
    begin
      lDef := TRdcGatewayDef.Create;
      FFile.Gateways.Add(lDef);
    end;
    lDef.Assign(lEdit.Def);
  end;
end;

end.
