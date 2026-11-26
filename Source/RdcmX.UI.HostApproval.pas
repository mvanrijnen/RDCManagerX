unit RdcmX.UI.HostApproval;

{
  Asks per host whether a remembered account password may be used there (group connect, second security review):
  a check list, every host unchecked by default, hosts that came from an Active Directory refresh marked as such.
  Built at runtime (no DFM): a label, the list, and OK/Cancel.
}

interface

uses
  RdcmX.Credentials;

/// <summary>False on Cancel. aApproved: the checked hosts (may be empty).</summary>
function RdcSelectApprovedHosts(const aAccount: string; const aHosts: TArray<TRdcHostRef>; const aNewFromAd: TArray<Boolean>; out aApproved: TArray<TRdcHostRef>): Boolean;

implementation

uses
  System.Classes, System.SysUtils, System.UITypes,
  Vcl.CheckLst, Vcl.Controls, Vcl.ExtCtrls, Vcl.Forms, Vcl.StdCtrls,
  RdcmX.Lang;

function RdcSelectApprovedHosts(const aAccount: string; const aHosts: TArray<TRdcHostRef>; const aNewFromAd: TArray<Boolean>; out aApproved: TArray<TRdcHostRef>): Boolean;
var
  lButtons: TPanel;
  lCancel: TButton;
  lForm: TForm;
  lIndex: Integer;
  lInfo: TLabel;
  lList: TCheckListBox;
  lOk: TButton;
  lText: string;
begin
  aApproved := [];
  lForm := TForm.CreateNew(Application);
  try
    lForm.Caption := _('Onthouden wachtwoord gebruiken');
    lForm.Position := poMainFormCenter;
    lForm.BorderStyle := bsSizeable;
    lForm.BorderIcons := [biSystemMenu];
    lForm.ClientWidth := lForm.ScaleValue(520);
    lForm.ClientHeight := lForm.ScaleValue(380);
    lForm.Font.Name := 'Segoe UI';
    lForm.Font.Size := 9;

    lInfo := TLabel.Create(lForm);
    lInfo.Parent := lForm;
    lInfo.Align := alTop;
    lInfo.AlignWithMargins := True;
    lInfo.WordWrap := True;
    lInfo.Caption := Format(_('Op welke hosts mag het onthouden wachtwoord voor %s gebruikt worden? Vink alleen hosts aan die u vertrouwt; het antwoord wordt onthouden. Voor de andere typt u het wachtwoord zelf in.'), [aAccount]);

    lButtons := TPanel.Create(lForm);
    lButtons.Parent := lForm;
    lButtons.Align := alBottom;
    lButtons.Height := lForm.ScaleValue(44);
    lButtons.BevelOuter := bvNone;

    lCancel := TButton.Create(lForm);
    lCancel.Parent := lButtons;
    lCancel.Caption := _('Annuleren');
    lCancel.ModalResult := mrCancel;
    lCancel.Cancel := True;
    lCancel.SetBounds(lForm.ClientWidth - lForm.ScaleValue(96), lForm.ScaleValue(9), lForm.ScaleValue(84), lForm.ScaleValue(26));
    lCancel.Anchors := [akTop, akRight];

    lOk := TButton.Create(lForm);
    lOk.Parent := lButtons;
    lOk.Caption := _('OK');
    lOk.ModalResult := mrOk;
    lOk.Default := True;
    lOk.SetBounds(lForm.ClientWidth - lForm.ScaleValue(188), lForm.ScaleValue(9), lForm.ScaleValue(84), lForm.ScaleValue(26));
    lOk.Anchors := [akTop, akRight];

    lList := TCheckListBox.Create(lForm);
    lList.Parent := lForm;
    lList.Align := alClient;
    lList.AlignWithMargins := True;
    for lIndex := 0 to High(aHosts) do
    begin
      lText := aHosts[lIndex].Display;
      if (lIndex <= High(aNewFromAd)) and aNewFromAd[lIndex] then
        lText := Format(_('%s  (nieuw uit Active Directory)'), [lText]);
      lList.Items.Add(lText);
      lList.Checked[lIndex] := False; // never approved by default
    end;

    Result := lForm.ShowModal = mrOk;
    if Result then
      for lIndex := 0 to High(aHosts) do
        if lList.Checked[lIndex] then
          aApproved := aApproved + [aHosts[lIndex]];
  finally
    lForm.Free;
  end;
end;

end.
