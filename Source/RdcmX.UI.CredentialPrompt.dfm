object frmCredentialPrompt: TfrmCredentialPrompt
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Aanmelden'
  ClientHeight = 240
  ClientWidth = 380
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnShow = FormShow
  TextHeight = 15
  object lblInfo: TLabel
    Left = 16
    Top = 14
    Width = 348
    Height = 15
    AutoSize = False
    Caption = 'Verbinden met'
    EllipsisPosition = epEndEllipsis
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblUser: TLabel
    Hint =
      'Gebruikersnaam voor deze server; mag ook als DOMEIN\gebruiker of gebr' +
      'uiker@domein.'
    Left = 16
    Top = 46
    Width = 87
    Height = 15
    Caption = 'Gebruikersnaam'
  end
  object lblDomain: TLabel
    Hint = 'Domein van de gebruiker; leeg bij een lokaal account op de server.'
    Left = 16
    Top = 77
    Width = 42
    Height = 15
    Caption = 'Domein'
  end
  object lblPassword: TLabel
    Hint =
      'Wachtwoord voor deze verbinding. Het wordt na gebruik uit het geheuge' +
      'n gewist.'
    Left = 16
    Top = 108
    Width = 70
    Height = 15
    Caption = 'Wachtwoord'
  end
  object lblHint: TLabel
    Left = 16
    Top = 136
    Width = 348
    Height = 15
    AutoSize = False
    Caption = 'Het wachtwoord wordt niet opgeslagen.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
  end
  object chkRemember: TCheckBox
    Hint =
      'Het wachtwoord versleuteld in de wachtwoordkluis bewaren, zodat het d' +
      'e volgende keer niet gevraagd wordt.'
    Left = 120
    Top = 160
    Width = 244
    Height = 19
    Caption = 'Wachtwoord onthouden'
    TabOrder = 3
  end
  object edtUser: TEdit
    Hint =
      'Gebruikersnaam voor deze server; mag ook als DOMEIN\gebruiker of gebr' +
      'uiker@domein.'
    Left = 120
    Top = 42
    Width = 244
    Height = 23
    TabOrder = 0
  end
  object edtDomain: TEdit
    Hint = 'Domein van de gebruiker; leeg bij een lokaal account op de server.'
    Left = 120
    Top = 73
    Width = 244
    Height = 23
    TabOrder = 1
  end
  object edtPassword: TEdit
    Hint =
      'Wachtwoord voor deze verbinding. Het wordt na gebruik uit het geheuge' +
      'n gewist.'
    Left = 120
    Top = 104
    Width = 244
    Height = 23
    PasswordChar = '*'
    TabOrder = 2
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 194
    Width = 380
    Height = 46
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 4
    object btnOk: TButton
      Hint = 'Verbinden met deze aanmeldgegevens.'
      Left = 192
      Top = 10
      Width = 82
      Height = 26
      Anchors = [akTop, akRight]
      Caption = 'Verbinden'
      Default = True
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TButton
      Hint = 'Niet verbinden.'
      Left = 282
      Top = 10
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
