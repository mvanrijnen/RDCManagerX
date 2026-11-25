object frmGateways: TfrmGateways
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'RDP-gateways'
  ClientHeight = 560
  ClientWidth = 620
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
  object lblName: TLabel
    Hint = 'Naam voor jezelf. Je kiest de gateway op deze naam bij de route.'
    Left = 12
    Top = 182
    Width = 32
    Height = 15
    Caption = 'Naam'
  end
  object lblHostName: TLabel
    Hint = 'Naam van de RD Gateway-server, zonder poort (bijv. rdg.voorbeeld.nl).'
    Left = 12
    Top = 214
    Width = 77
    Height = 15
    Caption = 'Gatewayserver'
  end
  object lblPort: TLabel
    Hint = 'Poort van de gateway. Leeg = 443.'
    Left = 400
    Top = 214
    Width = 27
    Height = 15
    Caption = 'Poort'
  end
  object lblUsage: TLabel
    Hint =
      'Altijd via de gateway, automatisch detecteren, of altijd behalve voor' +
      ' adressen in het lokale netwerk.'
    Left = 12
    Top = 246
    Width = 54
    Height = 15
    Caption = 'Gebruiken'
  end
  object lblCredsMode: TLabel
    Hint =
      'Welke aanmeldgegevens de gateway krijgt: die van de sessie, eigen geg' +
      'evens (wachtwoord in de kluis), vragen bij verbinden, of smartcard.'
    Left = 12
    Top = 278
    Width = 104
    Height = 15
    Caption = 'Aanmeldgegevens'
  end
  object lblAuthMethod: TLabel
    Hint =
      'Aanmeldmethode bij de gateway: wachtwoord (NTLM), smartcard of automa' +
      'tisch.'
    Left = 12
    Top = 310
    Width = 87
    Height = 15
    Caption = 'Aanmeldmethode'
  end
  object lblUserName: TLabel
    Hint = 'Gebruikersnaam voor de gateway (bij eigen aanmeldgegevens).'
    Left = 12
    Top = 342
    Width = 87
    Height = 15
    Caption = 'Gebruikersnaam'
  end
  object lblDomain: TLabel
    Hint = 'Domein van de gateway-gebruiker.'
    Left = 12
    Top = 374
    Width = 42
    Height = 15
    Caption = 'Domein'
  end
  object lblPassword: TLabel
    Hint =
      'Wachtwoord voor de gateway; wordt alleen in de wachtwoordkluis bewaar' +
      'd. Leeg = vragen bij verbinden.'
    Left = 12
    Top = 406
    Width = 70
    Height = 15
    Caption = 'Wachtwoord'
  end
  object lblHint: TLabel
    Left = 12
    Top = 440
    Width = 596
    Height = 56
    AutoSize = False
    Caption =
      'De gateway-instellingen horen bij dit bestand; het wachtwoord staat alleen in de wachtwoordkluis van deze pc. Kies per se' +
      'rver of groep de route "Via RDP-gateway" in Eigenschappen > Route.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ShowAccelChar = False
    WordWrap = True
  end
  object lvGateways: TListView
    Hint =
      'RDP-gateways van dit bestand. Kies er een per server of groep via Eig' +
      'enschappen > Route.'
    Left = 12
    Top = 12
    Width = 500
    Height = 156
    Columns = <
      item
        Caption = 'Naam'
        Width = 150
      end
      item
        Caption = 'Gatewayserver'
        Width = 200
      end
      item
        Caption = 'Aanmeldgegevens'
        Width = 125
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnSelectItem = lvGatewaysSelectItem
  end
  object btnAdd: TButton
    Hint = 'Een nieuwe gateway toevoegen.'
    Left = 526
    Top = 12
    Width = 82
    Height = 26
    Caption = 'Nieuw'
    TabOrder = 1
    OnClick = btnAddClick
  end
  object btnDelete: TButton
    Hint =
      'De geselecteerde gateway verwijderen (alleen als geen route er nog na' +
      'ar verwijst).'
    Left = 526
    Top = 46
    Width = 82
    Height = 26
    Caption = 'Verwijderen'
    TabOrder = 2
    OnClick = btnDeleteClick
  end
  object edtName: TEdit
    Hint = 'Naam voor jezelf. Je kiest de gateway op deze naam bij de route.'
    Left = 150
    Top = 178
    Width = 362
    Height = 23
    TabOrder = 3
    OnChange = FieldChange
  end
  object edtHostName: TEdit
    Hint = 'Naam van de RD Gateway-server, zonder poort (bijv. rdg.voorbeeld.nl).'
    Left = 150
    Top = 210
    Width = 236
    Height = 23
    TabOrder = 4
    TextHint = 'rdg.voorbeeld.nl'
    OnChange = FieldChange
  end
  object edtPort: TEdit
    Hint = 'Poort van de gateway. Leeg = 443.'
    Left = 440
    Top = 210
    Width = 72
    Height = 23
    NumbersOnly = True
    TabOrder = 5
    TextHint = '443'
    OnChange = FieldChange
  end
  object cbUsage: TComboBox
    Hint =
      'Altijd via de gateway, automatisch detecteren, of altijd behalve voor' +
      ' adressen in het lokale netwerk.'
    Left = 150
    Top = 242
    Width = 362
    Height = 23
    Style = csDropDownList
    TabOrder = 6
    OnChange = FieldChange
    Items.Strings = (
      'Altijd gebruiken'
      'Automatisch detecteren'
      'Altijd, behalve voor lokale adressen')
  end
  object cbCredsMode: TComboBox
    Hint =
      'Welke aanmeldgegevens de gateway krijgt: die van de sessie, eigen geg' +
      'evens (wachtwoord in de kluis), vragen bij verbinden, of smartcard.'
    Left = 150
    Top = 274
    Width = 362
    Height = 23
    Style = csDropDownList
    TabOrder = 7
    OnChange = FieldChange
    Items.Strings = (
      'Dezelfde als voor de sessie'
      'Eigen aanmeldgegevens voor de gateway'
      'Vragen bij verbinden'
      'Smartcard')
  end
  object cbAuthMethod: TComboBox
    Hint =
      'Aanmeldmethode bij de gateway: wachtwoord (NTLM), smartcard of automa' +
      'tisch.'
    Left = 150
    Top = 306
    Width = 362
    Height = 23
    Style = csDropDownList
    TabOrder = 8
    OnChange = FieldChange
    Items.Strings = (
      'Wachtwoord (NTLM)'
      'Smartcard'
      'Automatisch')
  end
  object edtUserName: TEdit
    Hint = 'Gebruikersnaam voor de gateway (bij eigen aanmeldgegevens).'
    Left = 150
    Top = 338
    Width = 362
    Height = 23
    TabOrder = 9
    OnChange = FieldChange
  end
  object edtDomain: TEdit
    Hint = 'Domein van de gateway-gebruiker.'
    Left = 150
    Top = 370
    Width = 362
    Height = 23
    TabOrder = 10
    OnChange = FieldChange
  end
  object edtPassword: TEdit
    Hint =
      'Wachtwoord voor de gateway; wordt alleen in de wachtwoordkluis bewaar' +
      'd. Leeg = vragen bij verbinden.'
    Left = 150
    Top = 402
    Width = 362
    Height = 23
    PasswordChar = '*'
    TabOrder = 11
    OnChange = FieldChange
  end
  object btnClearPassword: TButton
    Hint = 'Het opgeslagen gateway-wachtwoord verwijderen.'
    Left = 526
    Top = 401
    Width = 82
    Height = 26
    Caption = 'Wissen'
    TabOrder = 12
    OnClick = btnClearPasswordClick
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 506
    Width = 620
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 13
    object btnOk: TButton
      Hint = 'Wijzigingen opslaan.'
      Left = 440
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
      Left = 530
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
