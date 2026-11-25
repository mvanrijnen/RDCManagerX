object frmProfiles: TfrmProfiles
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Credential-profielen'
  ClientHeight = 400
  ClientWidth = 560
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object lblProfileName: TLabel
    Hint =
      'Naam van het profiel. Hernoemen past alle verwijzingen in het bestand' +
      ' aan.'
    Left = 12
    Top = 222
    Width = 32
    Height = 15
    Caption = 'Naam'
  end
  object lblProfileUser: TLabel
    Hint = 'Gebruikersnaam voor dit profiel; mag ook als DOMEIN\gebruiker.'
    Left = 12
    Top = 254
    Width = 87
    Height = 15
    Caption = 'Gebruikersnaam'
  end
  object lblProfileDomain: TLabel
    Hint = 'Domein voor dit profiel.'
    Left = 12
    Top = 286
    Width = 42
    Height = 15
    Caption = 'Domein'
  end
  object lblHint: TLabel
    Left = 12
    Top = 318
    Width = 536
    Height = 30
    AutoSize = False
    Caption =
      'Wachtwoorden staan nooit in het bestand; bij het verbinden wordt e' +
      'rom gevraagd, tenzij het in de wachtwoordkluis onthouden is. Hern' +
      'oemen past alle verwijzingen in het bestand aan.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object lvProfiles: TListView
    Hint =
      'Credential-profielen van dit bestand. Servers en groepen kunnen ernaa' +
      'r verwijzen (Eigenschappen > Aanmelden).'
    Left = 12
    Top = 12
    Width = 440
    Height = 194
    Columns = <
      item
        Caption = 'Naam'
        Width = 170
      end
      item
        Caption = 'Gebruikersnaam'
        Width = 150
      end
      item
        Caption = 'Domein'
        Width = 100
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnSelectItem = lvProfilesSelectItem
  end
  object btnAdd: TButton
    Hint = 'Een nieuw profiel toevoegen.'
    Left = 466
    Top = 12
    Width = 82
    Height = 26
    Caption = 'Nieuw'
    TabOrder = 1
    OnClick = btnAddClick
  end
  object btnDelete: TButton
    Hint =
      'Het geselecteerde profiel verwijderen (alleen als geen server of groe' +
      'p er nog naar verwijst).'
    Left = 466
    Top = 46
    Width = 82
    Height = 26
    Caption = 'Verwijderen'
    TabOrder = 2
    OnClick = btnDeleteClick
  end
  object edtProfileName: TEdit
    Hint =
      'Naam van het profiel. Hernoemen past alle verwijzingen in het bestand' +
      ' aan.'
    Left = 150
    Top = 218
    Width = 302
    Height = 23
    TabOrder = 3
    OnChange = ProfileFieldChange
  end
  object edtProfileUser: TEdit
    Hint = 'Gebruikersnaam voor dit profiel; mag ook als DOMEIN\gebruiker.'
    Left = 150
    Top = 250
    Width = 302
    Height = 23
    TabOrder = 4
    OnChange = ProfileFieldChange
  end
  object edtProfileDomain: TEdit
    Hint = 'Domein voor dit profiel.'
    Left = 150
    Top = 282
    Width = 302
    Height = 23
    TabOrder = 5
    OnChange = ProfileFieldChange
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 346
    Width = 560
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 6
    object btnOk: TButton
      Hint = 'Wijzigingen opslaan.'
      Left = 380
      Top = 14
      Width = 82
      Height = 26
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TButton
      Hint = 'Sluiten zonder op te slaan.'
      Left = 470
      Top = 14
      Width = 82
      Height = 26
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Annuleren'
      ModalResult = 2
      TabOrder = 1
    end
  end
end
