unit RdcmX.UI.Options;

{
  Opties-dialoog (Bestand > Opties...): app-instellingen per gebruiker (settings.json), niet per bestand.
  De dialoog werkt op een TRdcOptions-record; het hoofdvenster past de gekozen waarden toe.
}

interface

uses
  Winapi.Messages, Winapi.Windows,
  System.Classes, System.SysUtils, System.UITypes,
  Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.Samples.Spin, Vcl.StdCtrls,
  RdcmX.Lang, RdcmX.UI.Theme;

type
  TRdcOptions = record
    /// <summary>UI language; applies at the next start.</summary>
    Language: TRdcLanguage;
    RecentServerCount: Integer;
    Theme: TRdcTheme;
    AutoSave: Boolean;
    RememberPasswords: Boolean;
    AutoLockMinutes: Integer;
    /// <summary>Bereikbaarheid controleren elke zoveel seconden.</summary>
    PingIntervalSec: Integer;
    /// <summary>Daily check for a newer release on GitHub.</summary>
    CheckForUpdates: Boolean;
  end;

  TfrmOptions = class(TForm)
    lblLanguage: TLabel;
    cbLanguage: TComboBox;
    lblRecentCount: TLabel;
    seRecentCount: TSpinEdit;
    lblRecentHint: TLabel;
    lblTheme: TLabel;
    cbTheme: TComboBox;
    lblThemeHint: TLabel;
    chkAutoSave: TCheckBox;
    lblAutoSaveHint: TLabel;
    chkRememberPasswords: TCheckBox;
    lblRememberHint: TLabel;
    lblAutoLock: TLabel;
    seAutoLock: TSpinEdit;
    btnChangeMasterPassword: TButton;
    lblPingInterval: TLabel;
    sePingInterval: TSpinEdit;
    chkCheckForUpdates: TCheckBox;
    pnlButtons: TPanel;
    btnOk: TButton;
    btnCancel: TButton;
    procedure FormShow(Sender: TObject);
    procedure btnChangeMasterPasswordClick(Sender: TObject);
    procedure chkRememberPasswordsClick(Sender: TObject);
  private
    FChangeMasterPassword: TProc;
    FVaultExists: Boolean;
    procedure UpdateMasterPasswordButton;
    procedure ChangeMasterPassword;
    procedure FocusFirstField;
    procedure LoadOptions(const aOptions: TRdcOptions);
    procedure SaveOptions(var aOptions: TRdcOptions);
  protected
    procedure DoCreate; override;
  public
    /// <summary>aChangeMasterPassword: wijzigt het hoofdwachtwoord (knop; alleen als de kluis bestaat).</summary>
    class function Execute(var aOptions: TRdcOptions; aVaultExists: Boolean; const aChangeMasterPassword: TProc): Boolean; static;
  end;

implementation

{$R *.dfm}

procedure TfrmOptions.DoCreate;
begin
  // Translate the DFM texts before OnCreate runs.
  TranslateComponent(Self);
  inherited;
end;

class function TfrmOptions.Execute(var aOptions: TRdcOptions; aVaultExists: Boolean; const aChangeMasterPassword: TProc): Boolean;
var
  lForm: TfrmOptions;
begin
  lForm := TfrmOptions.Create(Application);
  try
    lForm.FVaultExists := aVaultExists;
    lForm.FChangeMasterPassword := aChangeMasterPassword;
    lForm.LoadOptions(aOptions);
    lForm.UpdateMasterPasswordButton;
    Result := lForm.ShowModal = mrOk;
    if Result then
      lForm.SaveOptions(aOptions);
  finally
    lForm.Free;
  end;
end;

procedure TfrmOptions.FormShow(Sender: TObject);
begin
  FocusFirstField;
end;

procedure TfrmOptions.btnChangeMasterPasswordClick(Sender: TObject);
begin
  ChangeMasterPassword;
end;

procedure TfrmOptions.chkRememberPasswordsClick(Sender: TObject);
begin
  UpdateMasterPasswordButton;
end;

procedure TfrmOptions.UpdateMasterPasswordButton;
begin
  // Alleen met een bestaande kluis, en niet als het onthouden net wordt uitgezet (dan wordt de kluis gewist).
  btnChangeMasterPassword.Enabled := FVaultExists and chkRememberPasswords.Checked and Assigned(FChangeMasterPassword);
end;

procedure TfrmOptions.ChangeMasterPassword;
begin
  if Assigned(FChangeMasterPassword) then
    FChangeMasterPassword();
end;

procedure TfrmOptions.FocusFirstField;
begin
  ActiveControl := cbLanguage;
end;

procedure TfrmOptions.LoadOptions(const aOptions: TRdcOptions);
begin
  cbLanguage.ItemIndex := Ord(aOptions.Language);
  seRecentCount.Value := aOptions.RecentServerCount;
  cbTheme.ItemIndex := Ord(aOptions.Theme);
  chkAutoSave.Checked := aOptions.AutoSave;
  chkRememberPasswords.Checked := aOptions.RememberPasswords;
  seAutoLock.Value := aOptions.AutoLockMinutes;
  sePingInterval.Value := aOptions.PingIntervalSec;
  chkCheckForUpdates.Checked := aOptions.CheckForUpdates;
end;

procedure TfrmOptions.SaveOptions(var aOptions: TRdcOptions);
begin
  if cbLanguage.ItemIndex >= 0 then
    aOptions.Language := TRdcLanguage(cbLanguage.ItemIndex);
  aOptions.RecentServerCount := seRecentCount.Value;
  if cbTheme.ItemIndex >= 0 then
    aOptions.Theme := TRdcTheme(cbTheme.ItemIndex);
  aOptions.AutoSave := chkAutoSave.Checked;
  aOptions.RememberPasswords := chkRememberPasswords.Checked;
  aOptions.AutoLockMinutes := seAutoLock.Value;
  aOptions.PingIntervalSec := sePingInterval.Value;
  aOptions.CheckForUpdates := chkCheckForUpdates.Checked;
end;

end.
