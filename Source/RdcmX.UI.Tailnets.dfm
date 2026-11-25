object frmTailnets: TfrmTailnets
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Tailscale-netwerken'
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
    Hint =
      'Naam voor jezelf, bijv. Thuis of Klant X. Je kiest het netwerk op dez' +
      'e naam bij de route.'
    Left = 12
    Top = 182
    Width = 32
    Height = 15
    Caption = 'Naam'
  end
  object lblNodeHost: TLabel
    Hint =
      'Naam waaronder RDCManagerX als apparaat in het tailnet verschijnt. Le' +
      'eg = rdpclient-<computernaam>.'
    Left = 12
    Top = 214
    Width = 125
    Height = 15
    Caption = 'Naam in het tailnet'
  end
  object lblAuthKey: TLabel
    Hint =
      'Auth key uit de Tailscale-adminconsole (tskey-auth-...). Leeg = inlog' +
      'gen via de browser. Wordt alleen in de wachtwoordkluis bewaard.'
    Left = 12
    Top = 246
    Width = 50
    Height = 15
    Caption = 'Auth key'
  end
  object lblControlUrl: TLabel
    Hint =
      'Eigen control server (bijv. Headscale), alleen via https. Leeg = Tail' +
      'scale zelf.'
    Left = 12
    Top = 306
    Width = 63
    Height = 15
    Caption = 'Control URL'
  end
  object lblLocalAddress: TLabel
    Hint =
      'Lokaal adres (127.x.x.x) voor de doorverwijzing naar het tailnet. Lee' +
      'g = 127.0.0.2.'
    Left = 12
    Top = 338
    Width = 73
    Height = 15
    Caption = 'Lokaal adres'
  end
  object lblTestStatus: TLabel
    Left = 150
    Top = 374
    Width = 458
    Height = 48
    AutoSize = False
    ShowAccelChar = False
    WordWrap = True
  end
  object lblHint: TLabel
    Left = 12
    Top = 430
    Width = 596
    Height = 64
    AutoSize = False
    Caption =
      'De auth key en de sleutels van een niet-ephemeral netwerk staan alleen in de wachtwoordkluis van deze pc (niet in het be' +
      'stand). Zonder auth key log je eenmalig in via de browser; zet Ephemeral dan uit, anders moet dat bij elke start opnieuw' +
      '. "Naam in het tailnet" is de naam waaronder RDCManagerX zelf als apparaat in je tailnet verschijnt (leeg = rdpclient-<computernaam>).'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clGrayText
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    ShowAccelChar = False
    WordWrap = True
  end
  object lvTailnets: TListView
    Hint =
      'Tailscale-netwerken van dit bestand. Kies er een per server of groep ' +
      'via Eigenschappen > Route.'
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
        Caption = 'Naam in het tailnet'
        Width = 150
      end
      item
        Caption = 'Ephemeral'
        Width = 75
      end
      item
        Caption = 'Auth key'
        Width = 100
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnSelectItem = lvTailnetsSelectItem
  end
  object btnAdd: TButton
    Hint = 'Een nieuw Tailscale-netwerk toevoegen.'
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
      'Het geselecteerde netwerk verwijderen; de auth key en sleutels op dez' +
      'e pc worden ook gewist.'
    Left = 526
    Top = 46
    Width = 82
    Height = 26
    Caption = 'Verwijderen'
    TabOrder = 2
    OnClick = btnDeleteClick
  end
  object edtName: TEdit
    Hint =
      'Naam voor jezelf, bijv. Thuis of Klant X. Je kiest het netwerk op dez' +
      'e naam bij de route.'
    Left = 150
    Top = 178
    Width = 362
    Height = 23
    TabOrder = 3
    OnChange = FieldChange
  end
  object edtNodeHost: TEdit
    Hint =
      'Naam waaronder RDCManagerX als apparaat in het tailnet verschijnt. Le' +
      'eg = rdpclient-<computernaam>.'
    Left = 150
    Top = 210
    Width = 362
    Height = 23
    CharCase = ecLowerCase
    TabOrder = 4
    OnChange = FieldChange
  end
  object edtAuthKey: TEdit
    Hint =
      'Auth key uit de Tailscale-adminconsole (tskey-auth-...). Leeg = inlog' +
      'gen via de browser. Wordt alleen in de wachtwoordkluis bewaard.'
    Left = 150
    Top = 242
    Width = 362
    Height = 23
    PasswordChar = '*'
    TabOrder = 5
    OnChange = FieldChange
  end
  object btnClearAuthKey: TButton
    Hint = 'De opgeslagen auth key van dit netwerk verwijderen.'
    Left = 526
    Top = 241
    Width = 82
    Height = 26
    Caption = 'Wissen'
    TabOrder = 6
    OnClick = btnClearAuthKeyClick
  end
  object chkEphemeral: TCheckBox
    Hint =
      'Aan: het apparaat verdwijnt uit het tailnet na afsluiten en er blijft' +
      ' niets op schijf. Uit: eenmalig inloggen; de sleutels blijven versleu' +
      'teld bewaard.'
    Left = 150
    Top = 276
    Width = 458
    Height = 19
    Caption = 'Ephemeral (verdwijnt uit het tailnet na afsluiten; niets op schijf)'
    TabOrder = 7
    OnClick = FieldChange
  end
  object edtControlUrl: TEdit
    Hint =
      'Eigen control server (bijv. Headscale), alleen via https. Leeg = Tail' +
      'scale zelf.'
    Left = 150
    Top = 302
    Width = 362
    Height = 23
    TabOrder = 8
    TextHint = 'standaard (Tailscale)'
    OnChange = FieldChange
  end
  object edtLocalAddress: TEdit
    Hint =
      'Lokaal adres (127.x.x.x) voor de doorverwijzing naar het tailnet. Lee' +
      'g = 127.0.0.2.'
    Left = 150
    Top = 334
    Width = 120
    Height = 23
    TabOrder = 9
    TextHint = '127.0.0.2'
    OnChange = FieldChange
  end
  object btnTest: TButton
    Hint =
      'Het netwerk opstarten, het adres in het tailnet tonen en weer sluiten' +
      '. Zonder auth key opent de login-pagina in de browser.'
    Left = 12
    Top = 370
    Width = 125
    Height = 26
    Caption = 'Test verbinding'
    TabOrder = 10
    OnClick = btnTestClick
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 506
    Width = 620
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 11
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
  object tmrTest: TTimer
    Enabled = False
    Interval = 500
    OnTimer = tmrTestTimer
    Left = 560
    Top = 120
  end
end
