unit RdcmX.UI.CredentialPrompt;

{
  Vraagt het wachtwoord (en eventueel gebruikersnaam/domein voor deze verbinding).
  Met "Wachtwoorden onthouden" in Opties staat er een vinkje "Wachtwoord onthouden"; het opslaan zelf gebeurt
  door de aanroeper in Windows Referentiebeheer (RdcmX.Credentials). Het veld wordt na gebruik overschreven.
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
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
  private
    procedure FocusFirstEmptyField;
  public
    /// <summary>aShowRemember: vinkje "Wachtwoord onthouden" tonen (Opties); aRemember: begin- en eindstand daarvan.</summary>
    class function Execute(const aServerCaption: string; var aUserName, aDomain: string; out aPassword: string; aShowRemember: Boolean; var aRemember: Boolean): Boolean; static;
  end;

implementation

{$R *.dfm}

class function TfrmCredentialPrompt.Execute(const aServerCaption: string; var aUserName, aDomain: string; out aPassword: string; aShowRemember: Boolean; var aRemember: Boolean): Boolean;
var
  lForm: TfrmCredentialPrompt;
begin
  aPassword := '';
  lForm := TfrmCredentialPrompt.Create(Application);
  try
    lForm.lblInfo.Caption := 'Verbinden met ' + aServerCaption;
    lForm.edtUser.Text := aUserName;
    lForm.edtDomain.Text := aDomain;
    lForm.chkRemember.Visible := aShowRemember;
    lForm.chkRemember.Checked := aRemember;
    if aShowRemember then
      lForm.lblHint.Caption := 'Onthouden: versleuteld in Windows Referentiebeheer, nooit in het bestand.'
    else
      lForm.lblHint.Caption := 'Het wachtwoord wordt niet opgeslagen.';
    Result := lForm.ShowModal = mrOk;
    if Result then
    begin
      aUserName := Trim(lForm.edtUser.Text);
      aDomain := Trim(lForm.edtDomain.Text);
      aPassword := lForm.edtPassword.Text;
      aRemember := aShowRemember and lForm.chkRemember.Checked;
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
