object frmMasterPassword: TfrmMasterPassword
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Hoofdwachtwoord'
  ClientHeight = 262
  ClientWidth = 440
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  OnShow = FormShow
  TextHeight = 15
  object lblInfo: TLabel
    Left = 16
    Top = 14
    Width = 408
    Height = 32
    AutoSize = False
    Caption = 'Wachtwoordkluis'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
    WordWrap = True
  end
  object lblOld: TLabel
    Hint = 'Het huidige hoofdwachtwoord van de wachtwoordkluis.'
    Left = 16
    Top = 62
    Width = 126
    Height = 15
    Caption = 'Huidig hoofdwachtwoord'
  end
  object lblNew: TLabel
    Hint =
      'Hoofdwachtwoord van de kluis, minimaal 16 tekens. Het wordt nergens o' +
      'pgeslagen en is niet te herstellen: onthoud het goed.'
    Left = 16
    Top = 94
    Width = 92
    Height = 15
    Caption = 'Hoofdwachtwoord'
  end
  object lblConfirm: TLabel
    Hint = 'Hetzelfde hoofdwachtwoord nogmaals, ter controle.'
    Left = 16
    Top = 126
    Width = 93
    Height = 15
    Caption = 'Nogmaals invoeren'
  end
  object lblHint: TLabel
    Left = 16
    Top = 156
    Width = 408
    Height = 48
    AutoSize = False
    Caption = 'Het hoofdwachtwoord wordt niet opgeslagen.'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object edtOld: TEdit
    Hint = 'Het huidige hoofdwachtwoord van de wachtwoordkluis.'
    Left = 180
    Top = 58
    Width = 244
    Height = 23
    PasswordChar = '*'
    TabOrder = 0
  end
  object edtNew: TEdit
    Hint =
      'Hoofdwachtwoord van de kluis, minimaal 16 tekens. Het wordt nergens o' +
      'pgeslagen en is niet te herstellen: onthoud het goed.'
    Left = 180
    Top = 90
    Width = 244
    Height = 23
    PasswordChar = '*'
    TabOrder = 1
  end
  object edtConfirm: TEdit
    Hint = 'Hetzelfde hoofdwachtwoord nogmaals, ter controle.'
    Left = 180
    Top = 122
    Width = 244
    Height = 23
    PasswordChar = '*'
    TabOrder = 2
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 216
    Width = 440
    Height = 46
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 3
    object btnForgot: TButton
      Hint =
        'Hoofdwachtwoord vergeten: de kluis legen (alle onthouden wachtwoorden' +
        ' verdwijnen) en een nieuw hoofdwachtwoord instellen.'
      Left = 16
      Top = 10
      Width = 96
      Height = 26
      Caption = 'Vergeten...'
      ModalResult = 4
      TabOrder = 0
    end
    object btnOk: TButton
      Hint = 'Bevestigen.'
      Left = 252
      Top = 10
      Width = 82
      Height = 26
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 1
    end
    object btnCancel: TButton
      Hint = 'Annuleren.'
      Left = 342
      Top = 10
      Width = 82
      Height = 26
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Annuleren'
      ModalResult = 2
      TabOrder = 2
    end
  end
end
