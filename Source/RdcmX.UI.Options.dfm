object frmOptions: TfrmOptions
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Opties'
  ClientHeight = 556
  ClientWidth = 460
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnShow = FormShow
  TextHeight = 15
  object lblRecentCount: TLabel
    Hint =
      'Hoeveel laatst verbonden servers bovenaan de boom onder Recent staan ' +
      '(0 = Recent niet tonen).'
    Left = 16
    Top = 20
    Width = 160
    Height = 15
    Caption = 'Aantal recente servers in de boom'
  end
  object lblRecentHint: TLabel
    Left = 16
    Top = 50
    Width = 428
    Height = 32
    AutoSize = False
    Caption =
      'De laatst verbonden servers staan bovenaan de boom onder Recent. ' +
      '0 = geen lijst Recent.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object lblTheme: TLabel
    Hint =
      'Uiterlijk: volgt Windows, licht of donker. Zijn er sessies open, dan ' +
      'geldt een wijziging bij de volgende start.'
    Left = 16
    Top = 102
    Width = 37
    Height = 15
    Caption = 'Thema'
  end
  object lblThemeHint: TLabel
    Left = 16
    Top = 132
    Width = 428
    Height = 48
    AutoSize = False
    Caption =
      'Zijn er sessies open, dan wordt een ander thema pas bij de volgen' +
      'de start toegepast (omschakelen zou de sessies verbreken).'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object lblAutoSaveHint: TLabel
    Left = 36
    Top = 220
    Width = 408
    Height = 48
    AutoSize = False
    Caption =
      'Elke wijziging wordt kort daarna opgeslagen. Uit: bij sluiten wor' +
      'dt gevraagd om wijzigingen op te slaan. Een nieuw, nog nooit opge' +
      'slagen bestand wordt altijd bij sluiten gevraagd.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object lblRememberHint: TLabel
    Left = 36
    Top = 312
    Width = 408
    Height = 64
    AutoSize = False
    Caption =
      'Alleen als dit aan staat, verschijnt bij het aanmelden het vinkje' +
      ' "Wachtwoord onthouden" (standaard uit). Versleuteld met een hoofd' +
      'wachtwoord (AES-256) in Windows Referentiebeheer, nooit in het be' +
      'stand. Uitzetten wist alles.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object chkRememberPasswords: TCheckBox
    Hint =
      'Wachtwoorden versleuteld onthouden in de wachtwoordkluis (met een hoo' +
      'fdwachtwoord). Uitzetten wist de kluis en alle onthouden wachtwoorden.'
    Left = 16
    Top = 284
    Width = 428
    Height = 19
    Caption = 'Onthouden van wachtwoorden toestaan'
    TabOrder = 3
    OnClick = chkRememberPasswordsClick
  end
  object chkAutoSave: TCheckBox
    Hint =
      'Wijzigingen in bestanden na 2 seconden automatisch opslaan. Uit: bij ' +
      'het sluiten wordt gevraagd of je wilt opslaan.'
    Left = 16
    Top = 192
    Width = 428
    Height = 19
    Caption = 'Wijzigingen in bestanden automatisch opslaan'
    TabOrder = 2
  end
  object seRecentCount: TSpinEdit
    Hint =
      'Hoeveel laatst verbonden servers bovenaan de boom onder Recent staan ' +
      '(0 = Recent niet tonen).'
    Left = 260
    Top = 16
    Width = 70
    Height = 24
    MaxValue = 25
    MinValue = 0
    TabOrder = 0
    Value = 5
  end
  object cbTheme: TComboBox
    Hint =
      'Uiterlijk: volgt Windows, licht of donker. Zijn er sessies open, dan ' +
      'geldt een wijziging bij de volgende start.'
    Left = 260
    Top = 98
    Width = 184
    Height = 23
    Style = csDropDownList
    TabOrder = 1
    Items.Strings = (
      'Systeem (volgt Windows)'
      'Licht'
      'Donker')
  end
  object lblAutoLock: TLabel
    Hint =
      'Na zoveel minuten zonder gebruik vergrendelt de kluis; daarna wordt h' +
      'et hoofdwachtwoord opnieuw gevraagd (0 = nooit).'
    Left = 36
    Top = 384
    Width = 196
    Height = 15
    Caption = 'Kluis vergrendelen na (minuten, 0 = nooit)'
  end
  object seAutoLock: TSpinEdit
    Hint =
      'Na zoveel minuten zonder gebruik vergrendelt de kluis; daarna wordt h' +
      'et hoofdwachtwoord opnieuw gevraagd (0 = nooit).'
    Left = 260
    Top = 380
    Width = 70
    Height = 24
    MaxValue = 1440
    MinValue = 0
    TabOrder = 5
    Value = 15
  end
  object btnChangeMasterPassword: TButton
    Hint =
      'Het hoofdwachtwoord van de kluis wijzigen. Alle onthouden wachtwoorde' +
      'n worden met het nieuwe opnieuw versleuteld.'
    Left = 36
    Top = 416
    Width = 200
    Height = 26
    Caption = 'Hoofdwachtwoord wijzigen...'
    TabOrder = 6
    OnClick = btnChangeMasterPasswordClick
  end
  object lblPingInterval: TLabel
    Hint =
      'Hoe vaak servers met "Bereikbaarheid tonen" (Eigenschappen > Route) g' +
      'econtroleerd worden: 5 tot 3600 seconden.'
    Left = 16
    Top = 464
    Width = 236
    Height = 15
    Caption = 'Bereikbaarheid controleren elke (seconden)'
  end
  object sePingInterval: TSpinEdit
    Hint =
      'Hoe vaak servers met "Bereikbaarheid tonen" (Eigenschappen > Route) g' +
      'econtroleerd worden: 5 tot 3600 seconden.'
    Left = 260
    Top = 460
    Width = 70
    Height = 24
    MaxValue = 3600
    MinValue = 5
    TabOrder = 7
    Value = 30
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 502
    Width = 460
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 4
    object btnOk: TButton
      Hint = 'Instellingen opslaan.'
      Left = 280
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
      Left = 370
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
