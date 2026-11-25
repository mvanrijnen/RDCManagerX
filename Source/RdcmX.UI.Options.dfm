object frmOptions: TfrmOptions
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Opties'
  ClientHeight = 596
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
  object lblLanguage: TLabel
    Hint =
      'Taal van de schermen en meldingen: volgt Windows, English of Ned' +
      'erlands. Een wijziging geldt bij de volgende start.'
    Left = 16
    Top = 20
    Width = 25
    Height = 15
    Caption = 'Taal'
  end
  object cbLanguage: TComboBox
    Hint =
      'Taal van de schermen en meldingen: volgt Windows, English of Ned' +
      'erlands. Een wijziging geldt bij de volgende start.'
    Left = 260
    Top = 16
    Width = 184
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    Items.Strings = (
      'Systeem (volgt Windows)'
      'English'
      'Nederlands')
  end
  object lblRecentCount: TLabel
    Hint =
      'Hoeveel laatst verbonden servers bovenaan de boom onder Recent staan ' +
      '(0 = Recent niet tonen).'
    Left = 16
    Top = 60
    Width = 160
    Height = 15
    Caption = 'Aantal recente servers in de boom'
  end
  object lblRecentHint: TLabel
    Left = 16
    Top = 90
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
    Top = 142
    Width = 37
    Height = 15
    Caption = 'Thema'
  end
  object lblThemeHint: TLabel
    Left = 16
    Top = 172
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
    Top = 260
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
    Top = 352
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
    Top = 324
    Width = 428
    Height = 19
    Caption = 'Onthouden van wachtwoorden toestaan'
    TabOrder = 4
    OnClick = chkRememberPasswordsClick
  end
  object chkAutoSave: TCheckBox
    Hint =
      'Wijzigingen in bestanden na 2 seconden automatisch opslaan. Uit: bij ' +
      'het sluiten wordt gevraagd of je wilt opslaan.'
    Left = 16
    Top = 232
    Width = 428
    Height = 19
    Caption = 'Wijzigingen in bestanden automatisch opslaan'
    TabOrder = 3
  end
  object seRecentCount: TSpinEdit
    Hint =
      'Hoeveel laatst verbonden servers bovenaan de boom onder Recent staan ' +
      '(0 = Recent niet tonen).'
    Left = 260
    Top = 56
    Width = 70
    Height = 24
    MaxValue = 25
    MinValue = 0
    TabOrder = 1
    Value = 5
  end
  object cbTheme: TComboBox
    Hint =
      'Uiterlijk: volgt Windows, licht of donker. Zijn er sessies open, dan ' +
      'geldt een wijziging bij de volgende start.'
    Left = 260
    Top = 138
    Width = 184
    Height = 23
    Style = csDropDownList
    TabOrder = 2
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
    Top = 424
    Width = 196
    Height = 15
    Caption = 'Kluis vergrendelen na (minuten, 0 = nooit)'
  end
  object seAutoLock: TSpinEdit
    Hint =
      'Na zoveel minuten zonder gebruik vergrendelt de kluis; daarna wordt h' +
      'et hoofdwachtwoord opnieuw gevraagd (0 = nooit).'
    Left = 260
    Top = 420
    Width = 70
    Height = 24
    MaxValue = 1440
    MinValue = 0
    TabOrder = 6
    Value = 15
  end
  object btnChangeMasterPassword: TButton
    Hint =
      'Het hoofdwachtwoord van de kluis wijzigen. Alle onthouden wachtwoorde' +
      'n worden met het nieuwe opnieuw versleuteld.'
    Left = 36
    Top = 456
    Width = 200
    Height = 26
    Caption = 'Hoofdwachtwoord wijzigen...'
    TabOrder = 7
    OnClick = btnChangeMasterPasswordClick
  end
  object lblPingInterval: TLabel
    Hint =
      'Hoe vaak servers met "Bereikbaarheid tonen" (Eigenschappen > Route) g' +
      'econtroleerd worden: 5 tot 3600 seconden.'
    Left = 16
    Top = 504
    Width = 236
    Height = 15
    Caption = 'Bereikbaarheid controleren elke (seconden)'
  end
  object sePingInterval: TSpinEdit
    Hint =
      'Hoe vaak servers met "Bereikbaarheid tonen" (Eigenschappen > Route) g' +
      'econtroleerd worden: 5 tot 3600 seconden.'
    Left = 260
    Top = 500
    Width = 70
    Height = 24
    MaxValue = 3600
    MinValue = 5
    TabOrder = 8
    Value = 30
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 542
    Width = 460
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 5
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
