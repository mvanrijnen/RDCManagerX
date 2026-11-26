unit RdcmX.UI.CredentialPrompt;

{
  Vraagt het wachtwoord (en eventueel gebruikersnaam/domein voor deze verbinding).
  Met "Wachtwoorden onthouden" in Opties staat er een vinkje "Wachtwoord onthouden"; het opslaan zelf gebeurt
  door de aanroeper in Windows Referentiebeheer (RdcmX.Credentials). Het veld wordt na gebruik overschreven.
  "Gebruikersnaam en domein onthouden" (user request) is separate from the password: the caller stores user name and
  domain in the file (logon settings of the server or group); never checked by default.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils,
  Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.StdCtrls;

type
  TfrmCredentialPrompt = class(TForm)
    lblInfo: TLabel;
    lblUser: TLabel;
    edtUser: TEdit;
    lblDomain: TLabel;
    edtDomain: TEdit;
    lblPassword: TLabel;
    edtPassword: TEdit;
    lblHint: TLabel;
    chkRemember: TCheckBox;
    chkRememberUser: TCheckBox;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
  private
    procedure FocusFirstEmptyField;
  protected
    procedure DoCreate; override;
  public
    /// <summary>aShowRemember: vinkje "Wachtwoord onthouden" tonen (Opties); aRemember: begin- en eindstand daarvan.
    /// aRememberUser: "Gebruikersnaam en domein onthouden" (start and end state).</summary>
    class function Execute(const aServerCaption: string; var aUserName, aDomain: string; out aPassword: string; aShowRemember: Boolean; var aRemember, aRememberUser: Boolean): Boolean; static;
  end;

implementation

uses
  RdcmX.Lang;

{$R *.dfm}

procedure TfrmCredentialPrompt.DoCreate;
begin
  // Translate the DFM texts before OnCreate runs.
  TranslateComponent(Self);
  inherited;
end;

class function TfrmCredentialPrompt.Execute(const aServerCaption: string; var aUserName, aDomain: string; out aPassword: string; aShowRemember: Boolean; var aRemember, aRememberUser: Boolean): Boolean;
var
  lForm: TfrmCredentialPrompt;
begin
  aPassword := '';
  lForm := TfrmCredentialPrompt.Create(Application);
  try
    lForm.lblInfo.Caption := Format(_('Verbinden met %s'), [aServerCaption]);
    lForm.edtUser.Text := aUserName;
    lForm.edtDomain.Text := aDomain;
    lForm.chkRemember.Visible := aShowRemember;
    lForm.chkRemember.Checked := aRemember;
    lForm.chkRememberUser.Checked := aRememberUser;
    if not aShowRemember then
      lForm.ClientHeight := lForm.ClientHeight - (lForm.chkRemember.Top - lForm.chkRememberUser.Top);
    if aShowRemember then
      lForm.lblHint.Caption := _('Onthouden: versleuteld in Windows Referentiebeheer, nooit in het bestand.')
    else
      lForm.lblHint.Caption := _('Het wachtwoord wordt niet opgeslagen.');
    Result := lForm.ShowModal = mrOk;
    if Result then
    begin
      aUserName := Trim(lForm.edtUser.Text);
      aDomain := Trim(lForm.edtDomain.Text);
      aPassword := lForm.edtPassword.Text;
      aRemember := aShowRemember and lForm.chkRemember.Checked;
      aRememberUser := lForm.chkRememberUser.Checked;
    end;
    lForm.edtPassword.Text := '';
  finally
    lForm.Free;
  end;
end;

procedure TfrmCredentialPrompt.FormShow(Sender: TObject);
begin
  FocusFirstEmptyField;
end;

procedure TfrmCredentialPrompt.FocusFirstEmptyField;
begin
  // Eerste lege veld: gebruikersnaam als die ontbreekt, anders direct het wachtwoord.
  if edtUser.Text = '' then
    ActiveControl := edtUser
  else
    ActiveControl := edtPassword;
end;

end.
