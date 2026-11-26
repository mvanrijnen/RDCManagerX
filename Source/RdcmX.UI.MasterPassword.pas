unit RdcmX.UI.MasterPassword;

{
  Dialoog voor het hoofdwachtwoord van de wachtwoordkluis (RdcmX.Credentials):
  - Ontgrendelen: één veld; "Vergeten..." laat de aanroeper de kluis leegmaken (het hoofdwachtwoord is niet te
    herstellen, dat is de bedoeling).
  - Instellen: nieuw hoofdwachtwoord twee keer, minimaal cRdcMinMasterPasswordLength tekens en geen voor de hand
    liggend patroon (TRdcPasswordVault.CheckMasterPassword).
  - Wijzigen: huidig hoofdwachtwoord plus het nieuwe twee keer.
  De velden worden na gebruik overschreven; de dialoog bewaart niets.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils, System.UITypes,
  Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls;

type
  TRdcMasterPasswordMode = (mpmUnlock, mpmCreate, mpmChange);
  TRdcMasterPasswordResult = (mprOk, mprCancel, mprForgot);

  TfrmMasterPassword = class(TForm)
    lblInfo: TLabel;
    lblOld: TLabel;
    edtOld: TEdit;
    lblNew: TLabel;
    edtNew: TEdit;
    lblConfirm: TLabel;
    edtConfirm: TEdit;
    lblHint: TLabel;
    pnlButtons: TPanel;
    btnForgot: TButton;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  private
    FMode: TRdcMasterPasswordMode;
    procedure ApplyMode(aMode: TRdcMasterPasswordMode; const aInfo: string);
    procedure FocusFirstField;
    function ValidateInput: Boolean;
    procedure WipeFields;
  protected
    procedure DoCreate; override;
  public
    /// <summary>aPassword: het (nieuwe) hoofdwachtwoord; aOldPassword: alleen bij Wijzigen. Aanroeper wist beide na gebruik.</summary>
    class function Execute(aMode: TRdcMasterPasswordMode; const aInfo: string; out aPassword, aOldPassword: string): TRdcMasterPasswordResult; static;
  end;

implementation

uses
  RdcmX.Credentials, RdcmX.Lang;

{$R *.dfm}

procedure TfrmMasterPassword.DoCreate;
begin
  // Translate the DFM texts before OnCreate runs.
  TranslateComponent(Self);
  inherited;
end;

class function TfrmMasterPassword.Execute(aMode: TRdcMasterPasswordMode; const aInfo: string; out aPassword, aOldPassword: string): TRdcMasterPasswordResult;
var
  lForm: TfrmMasterPassword;
begin
  aPassword := '';
  aOldPassword := '';
  lForm := TfrmMasterPassword.Create(Application);
  try
    lForm.ApplyMode(aMode, aInfo);
    case lForm.ShowModal of
      mrOk:
        begin
          Result := mprOk;
          aPassword := lForm.edtNew.Text;
          aOldPassword := lForm.edtOld.Text;
        end;
      mrRetry:
        Result := mprForgot;
    else
      Result := mprCancel;
    end;
    lForm.WipeFields;
  finally
    lForm.Free;
  end;
end;

procedure TfrmMasterPassword.FormShow(Sender: TObject);
begin
  FocusFirstField;
end;

procedure TfrmMasterPassword.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := (ModalResult <> mrOk) or ValidateInput;
end;

procedure TfrmMasterPassword.ApplyMode(aMode: TRdcMasterPasswordMode; const aInfo: string);
begin
  FMode := aMode;
  lblInfo.Caption := aInfo;
  lblOld.Visible := aMode = mpmChange;
  edtOld.Visible := aMode = mpmChange;
  lblConfirm.Visible := aMode <> mpmUnlock;
  edtConfirm.Visible := aMode <> mpmUnlock;
  btnForgot.Visible := aMode = mpmUnlock;
  case aMode of
    mpmUnlock:
      begin
        Caption := _('Wachtwoordkluis ontgrendelen');
        lblNew.Caption := _('Hoofdwachtwoord');
        btnOk.Caption := _('Ontgrendelen');
        lblHint.Caption := _('Het hoofdwachtwoord wordt niet opgeslagen. Vergeten? Dan kan de kluis alleen leeggemaakt worden.');
      end;
    mpmCreate:
      begin
        Caption := _('Hoofdwachtwoord instellen');
        lblNew.Caption := _('Nieuw hoofdwachtwoord');
        btnOk.Caption := _('Instellen');
        lblHint.Caption := Format(_('Minimaal %d tekens; een zin van een paar woorden is sterk en makkelijk te onthouden. Het hoofdwachtwoord wordt nergens opgeslagen en is niet te herstellen: vergeten = alle onthouden wachtwoorden kwijt.'), [cRdcMinMasterPasswordLength]);
      end;
    mpmChange:
      begin
        Caption := _('Hoofdwachtwoord wijzigen');
        lblNew.Caption := _('Nieuw hoofdwachtwoord');
        btnOk.Caption := _('Wijzigen');
        lblHint.Caption := Format(_('Minimaal %d tekens; een zin van een paar woorden is sterk en makkelijk te onthouden. Alle onthouden wachtwoorden worden opnieuw versleuteld.'), [cRdcMinMasterPasswordLength]);
      end;
  end;
end;

procedure TfrmMasterPassword.FocusFirstField;
begin
  if FMode = mpmChange then
    ActiveControl := edtOld
  else
    ActiveControl := edtNew;
end;

function TfrmMasterPassword.ValidateInput: Boolean;
var
  lReason: string;
begin
  Result := False;
  if FMode = mpmUnlock then
    Exit(edtNew.Text <> '');
  if (FMode = mpmChange) and (edtOld.Text = '') then
  begin
    edtOld.SetFocus;
    MessageDlg(_('Vul het huidige hoofdwachtwoord in.'), mtWarning, [mbOK], 0);
    Exit;
  end;
  if not TRdcPasswordVault.CheckMasterPassword(edtNew.Text, lReason) then
  begin
    edtNew.SetFocus;
    MessageDlg(lReason, mtWarning, [mbOK], 0);
    Exit;
  end;
  if edtNew.Text <> edtConfirm.Text then
  begin
    edtConfirm.SetFocus;
    MessageDlg(_('De twee nieuwe hoofdwachtwoorden zijn niet gelijk.'), mtWarning, [mbOK], 0);
    Exit;
  end;
  Result := True;
end;

procedure TfrmMasterPassword.WipeFields;
begin
  // TEdit houdt zijn eigen kopie van de tekst; leegmaken is wat hier kan.
  edtOld.Text := '';
  edtNew.Text := '';
  edtConfirm.Text := '';
end;

end.
