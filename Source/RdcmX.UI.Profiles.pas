unit RdcmX.UI.Profiles;

{
  Beheer van de credential-profielen van één bestand (<credentialsProfiles> in de .rdg): naam, gebruikersnaam
  en domein. Wachtwoorden worden nooit opgeslagen.

  Er wordt op een kopie gewerkt; bij OK:
  - hernoemde profielen: alle verwijzingen (logonCredentials/gatewaySettings met scope="File") gaan mee;
  - verwijderen kan alleen als niets meer naar het profiel verwijst.
}

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils, System.UITypes,
  Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.Model;

type
  TRdcProfileEdit = class
  public
    /// <summary>Naam in het bestand bij openen; leeg = nieuw profiel.</summary>
    OriginalName: string;
    ProfileName: string;
    UserName: string;
    Domain: string;
  end;

  TfrmProfiles = class(TForm)
    lvProfiles: TListView;
    btnAdd: TButton;
    btnDelete: TButton;
    lblProfileName: TLabel;
    edtProfileName: TEdit;
    lblProfileUser: TLabel;
    edtProfileUser: TEdit;
    lblProfileDomain: TLabel;
    edtProfileDomain: TEdit;
    lblHint: TLabel;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure lvProfilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure btnAddClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure ProfileFieldChange(Sender: TObject);
  private
    FFile: TRdcFile;
    FEdits: TObjectList<TRdcProfileEdit>;
    FChanged: Boolean;
    FLoading: Boolean;
    procedure LoadProfiles;
    procedure FillList(aSelect: TRdcProfileEdit);
    procedure UpdateListItem(aItem: TListItem);
    function SelectedEdit: TRdcProfileEdit;
    procedure ShowSelected;
    procedure StoreFields;
    procedure AddProfile;
    procedure DeleteSelectedProfile;
    function UniqueName(const aBase: string): string;
    function ValidateProfiles: Boolean;
    procedure ApplyToFile;
  public
    /// <summary>True als er iets gewijzigd is (en toegepast op het bestand).</summary>
    class function Execute(aFile: TRdcFile): Boolean; static;
  end;

implementation

{$R *.dfm}

class function TfrmProfiles.Execute(aFile: TRdcFile): Boolean;
var
  lForm: TfrmProfiles;
begin
  lForm := TfrmProfiles.Create(Application);
  try
    lForm.FFile := aFile;
    lForm.LoadProfiles;
    Result := (lForm.ShowModal = mrOk) and lForm.FChanged;
    if Result then
      lForm.ApplyToFile;
  finally
    lForm.Free;
  end;
end;

procedure TfrmProfiles.FormCreate(Sender: TObject);
begin
  FEdits := TObjectList<TRdcProfileEdit>.Create(True);
end;

procedure TfrmProfiles.FormDestroy(Sender: TObject);
begin
  FEdits.Free;
end;

procedure TfrmProfiles.FormShow(Sender: TObject);
begin
  ShowSelected;
end;

procedure TfrmProfiles.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (ModalResult <> mrOk) or ValidateProfiles;
end;

procedure TfrmProfiles.lvProfilesSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  ShowSelected;
end;

procedure TfrmProfiles.btnAddClick(Sender: TObject);
begin
  AddProfile;
end;

procedure TfrmProfiles.btnDeleteClick(Sender: TObject);
begin
  DeleteSelectedProfile;
end;

procedure TfrmProfiles.ProfileFieldChange(Sender: TObject);
begin
  StoreFields;
end;

procedure TfrmProfiles.LoadProfiles;
var
  lEdit: TRdcProfileEdit;
  lProfile: TRdcCredentialProfile;
begin
  Caption := Format('Credential-profielen - %s', [FFile.Caption]);
  for lProfile in FFile.Profiles do
  begin
    lEdit := TRdcProfileEdit.Create;
    lEdit.OriginalName := lProfile.ProfileName;
    lEdit.ProfileName := lProfile.ProfileName;
    lEdit.UserName := lProfile.UserName;
    lEdit.Domain := lProfile.Domain;
    FEdits.Add(lEdit);
  end;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
end;

procedure TfrmProfiles.FillList(aSelect: TRdcProfileEdit);
var
  lEdit: TRdcProfileEdit;
  lItem: TListItem;
begin
  FLoading := True;
  lvProfiles.Items.BeginUpdate;
  try
    lvProfiles.Items.Clear;
    for lEdit in FEdits do
    begin
      lItem := lvProfiles.Items.Add;
      lItem.Data := lEdit;
      lItem.SubItems.Add('');
      lItem.SubItems.Add('');
      UpdateListItem(lItem);
      if lEdit = aSelect then
        lItem.Selected := True;
    end;
  finally
    lvProfiles.Items.EndUpdate;
    FLoading := False;
  end;
  if lvProfiles.Selected <> nil then
    lvProfiles.Selected.MakeVisible(False);
  ShowSelected;
end;

procedure TfrmProfiles.UpdateListItem(aItem: TListItem);
var
  lEdit: TRdcProfileEdit;
begin
  lEdit := TRdcProfileEdit(aItem.Data);
  aItem.Caption := lEdit.ProfileName;
  aItem.SubItems[0] := lEdit.UserName;
  aItem.SubItems[1] := lEdit.Domain;
end;

function TfrmProfiles.SelectedEdit: TRdcProfileEdit;
begin
  if lvProfiles.Selected <> nil then
    Result := TRdcProfileEdit(lvProfiles.Selected.Data)
  else
    Result := nil;
end;

procedure TfrmProfiles.ShowSelected;
var
  lEdit: TRdcProfileEdit;
begin
  if FLoading then
    Exit;
  lEdit := SelectedEdit;
  FLoading := True;
  try
    if lEdit <> nil then
    begin
      edtProfileName.Text := lEdit.ProfileName;
      edtProfileUser.Text := lEdit.UserName;
      edtProfileDomain.Text := lEdit.Domain;
    end
    else
    begin
      edtProfileName.Text := '';
      edtProfileUser.Text := '';
      edtProfileDomain.Text := '';
    end;
  finally
    FLoading := False;
  end;
  edtProfileName.Enabled := lEdit <> nil;
  edtProfileUser.Enabled := lEdit <> nil;
  edtProfileDomain.Enabled := lEdit <> nil;
  btnDelete.Enabled := lEdit <> nil;
end;

procedure TfrmProfiles.StoreFields;
var
  lEdit: TRdcProfileEdit;
begin
  lEdit := SelectedEdit;
  if FLoading or (lEdit = nil) then
    Exit;
  lEdit.ProfileName := Trim(edtProfileName.Text);
  lEdit.UserName := Trim(edtProfileUser.Text);
  lEdit.Domain := Trim(edtProfileDomain.Text);
  UpdateListItem(lvProfiles.Selected);
  FChanged := True;
end;

function TfrmProfiles.UniqueName(const aBase: string): string;
var
  lEdit: TRdcProfileEdit;
  lNumber: Integer;
  lUsed: Boolean;
begin
  lNumber := 1;
  Result := aBase;
  repeat
    lUsed := False;
    for lEdit in FEdits do
      if SameText(lEdit.ProfileName, Result) then
        lUsed := True;
    if lUsed then
    begin
      Inc(lNumber);
      Result := Format('%s %d', [aBase, lNumber]);
    end;
  until not lUsed;
end;

procedure TfrmProfiles.AddProfile;
var
  lEdit: TRdcProfileEdit;
begin
  lEdit := TRdcProfileEdit.Create;
  lEdit.ProfileName := UniqueName('Nieuw profiel');
  FEdits.Add(lEdit);
  FChanged := True;
  FillList(lEdit);
  edtProfileName.SetFocus;
  edtProfileName.SelectAll;
end;

procedure TfrmProfiles.DeleteSelectedProfile;
var
  lEdit: TRdcProfileEdit;
  lUsage: Integer;
begin
  lEdit := SelectedEdit;
  if lEdit = nil then
    Exit;
  if lEdit.OriginalName <> '' then
  begin
    lUsage := FFile.ProfileUsageCount(lEdit.OriginalName);
    if lUsage > 0 then
    begin
      MessageDlg(Format('Profiel "%s" wordt nog gebruikt door %d instelling(en) in dit bestand. Kies daar eerst een ander profiel of eigen aanmeldgegevens.', [lEdit.OriginalName, lUsage]), mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  FEdits.Remove(lEdit);
  FChanged := True;
  if FEdits.Count > 0 then
    FillList(FEdits[0])
  else
    FillList(nil);
end;

function TfrmProfiles.ValidateProfiles: Boolean;
var
  lIndex: Integer;
  lOther: Integer;
begin
  for lIndex := 0 to FEdits.Count - 1 do
  begin
    if FEdits[lIndex].ProfileName = '' then
    begin
      FillList(FEdits[lIndex]);
      edtProfileName.SetFocus;
      MessageDlg('Elk profiel moet een naam hebben.', mtWarning, [mbOK], 0);
      Exit(False);
    end;
    for lOther := lIndex + 1 to FEdits.Count - 1 do
      if SameText(FEdits[lIndex].ProfileName, FEdits[lOther].ProfileName) then
      begin
        FillList(FEdits[lOther]);
        edtProfileName.SetFocus;
        MessageDlg(Format('Er zijn twee profielen met de naam "%s".', [FEdits[lOther].ProfileName]), mtWarning, [mbOK], 0);
        Exit(False);
      end;
  end;
  Result := True;
end;

procedure TfrmProfiles.ApplyToFile;
var
  lEdit: TRdcProfileEdit;
  lIndex: Integer;
  lKeep: Boolean;
  lProfile: TRdcCredentialProfile;
  lTempName: string;
begin
  // 1. Verwijderde profielen.
  for lIndex := FFile.Profiles.Count - 1 downto 0 do
  begin
    lKeep := False;
    for lEdit in FEdits do
      if SameText(lEdit.OriginalName, FFile.Profiles[lIndex].ProfileName) then
        lKeep := True;
    if not lKeep then
      FFile.Profiles.Delete(lIndex);
  end;
  // 2. Hernoemen in twee stappen (via een tijdelijke naam), zodat ook het omwisselen van namen klopt.
  for lIndex := 0 to FEdits.Count - 1 do
    if (FEdits[lIndex].OriginalName <> '') and (FEdits[lIndex].OriginalName <> FEdits[lIndex].ProfileName) then
    begin
      lTempName := Format(#1'rdcmx-rename-%d', [lIndex]);
      FFile.RenameProfileReferences(FEdits[lIndex].OriginalName, lTempName);
      FFile.FindProfile(FEdits[lIndex].OriginalName).ProfileName := lTempName;
    end;
  for lIndex := 0 to FEdits.Count - 1 do
    if (FEdits[lIndex].OriginalName <> '') and (FEdits[lIndex].OriginalName <> FEdits[lIndex].ProfileName) then
    begin
      lTempName := Format(#1'rdcmx-rename-%d', [lIndex]);
      FFile.RenameProfileReferences(lTempName, FEdits[lIndex].ProfileName);
      FFile.FindProfile(lTempName).ProfileName := FEdits[lIndex].ProfileName;
    end;
  // 3. Gebruikersnaam/domein bijwerken en nieuwe profielen toevoegen.
  for lEdit in FEdits do
  begin
    if lEdit.OriginalName = '' then
    begin
      FFile.AddProfile(lEdit.ProfileName, lEdit.UserName, lEdit.Domain);
      Continue;
    end;
    lProfile := FFile.FindProfile(lEdit.ProfileName);
    if lProfile.UserName <> lEdit.UserName then
      lProfile.UserName := lEdit.UserName;
    if lProfile.Domain <> lEdit.Domain then
      lProfile.Domain := lEdit.Domain;
  end;
end;

end.
