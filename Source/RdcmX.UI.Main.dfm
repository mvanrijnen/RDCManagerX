object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'RDCManagerX'
  ClientHeight = 760
  ClientWidth = 1280
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnAfterMonitorDpiChanged = FormAfterMonitorDpiChanged
  OnClose = FormClose
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object sbStatus: TStatusBar
    Left = 0
    Top = 741
    Width = 1280
    Height = 19
    Panels = <
      item
        Width = 220
      end
      item
        Width = 520
      end
      item
        Width = 160
      end
      item
        Width = 120
      end>
    OnResize = sbStatusResize
  end
  object pnlLeft: TPanel
    Left = 0
    Top = 0
    Width = 260
    Height = 741
    Align = alLeft
    BevelOuter = bvNone
    TabOrder = 1
    object tbMenu: TToolBar
      Left = 0
      Top = 0
      Width = 260
      Height = 22
      AutoSize = True
      ButtonWidth = 54
      Caption = 'Menu'
      EdgeBorders = []
      List = True
      Menu = mmMain
      ShowCaptions = True
      TabOrder = 2
      Wrapable = True
    end
    object sbSearch: TSearchBox
      AlignWithMargins = True
      Left = 6
      Top = 28
      Width = 248
      Height = 23
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 4
      Align = alTop
      TabOrder = 0
      TextHint = 'Zoeken  (Ctrl+F)'
      Hint = 'Zoeken op weergavenaam of hostnaam: de boom toont alleen wat overeenkomt (Ctrl+F; Esc wist).'
      ShowHint = True
      OnChange = sbSearchChange
      OnKeyDown = sbSearchKeyDown
    end
    object tvServers: TTreeView
    Left = 0
    Top = 33
    Width = 260
    Height = 708
    Align = alClient
    BorderStyle = bsNone
    DragMode = dmManual
    HideSelection = False
    HotTrack = True
    ShowHint = True
    ToolTips = False
    OnMouseMove = tvServersMouseMove
    Indent = 20
    PopupMenu = pmTree
    RowSelect = True
    ShowLines = False
    TabOrder = 1
    OnCancelEdit = tvServersCancelEdit
    OnChange = tvServersChange
    OnCollapsed = tvServersCollapsed
    OnCompare = tvServersCompare
    OnExpanded = tvServersExpanded
    OnDblClick = tvServersDblClick
    OnDragDrop = tvServersDragDrop
    OnDragOver = tvServersDragOver
    OnEdited = tvServersEdited
    OnEditing = tvServersEditing
    OnContextPopup = tvServersContextPopup
    OnKeyDown = tvServersKeyDown
    OnMouseDown = tvServersMouseDown
    end
  end
  object splTree: TSplitter
    Left = 260
    Top = 0
    Width = 5
    Height = 741
    ResizeStyle = rsUpdate
  end
  object pnlRight: TPanel
    Left = 265
    Top = 0
    Width = 1015
    Height = 741
    Align = alClient
    BevelOuter = bvNone
    TabOrder = 2
    object pnlSession: TPanel
      Left = 0
      Top = 0
      Width = 1015
      Height = 741
      Align = alClient
      BevelOuter = bvNone
      Color = 3157291
      ParentBackground = False
      StyleElements = []
      TabOrder = 1
      object lblPlaceholder: TLabel
        Left = 0
        Top = 30
        Width = 1015
        Height = 711
        Alignment = taCenter
        AutoSize = False
        Font.Charset = DEFAULT_CHARSET
        Font.Color = 14737632
        Font.Height = -15
        Font.Name = 'Segoe UI'
        Font.Style = []
        Layout = tlCenter
        ParentFont = False
        StyleElements = []
        WordWrap = True
      end
    end
  end
  object mmMain: TMainMenu
    Left = 40
    Top = 80
    object miFile: TMenuItem
      Caption = '&Bestand'
      object miNewFile: TMenuItem
        Action = actNewFile
      end
      object miOpen: TMenuItem
        Action = actOpen
      end
      object miRecent: TMenuItem
        Caption = '&Recente bestanden'
      end
      object miFileSep1: TMenuItem
        Caption = '-'
      end
      object miSave: TMenuItem
        Action = actSave
      end
      object miSaveAs: TMenuItem
        Action = actSaveAs
      end
      object miSaveAll: TMenuItem
        Action = actSaveAll
      end
      object miFileSep2: TMenuItem
        Caption = '-'
      end
      object miCloseFile: TMenuItem
        Action = actCloseFile
      end
      object miFileSepProfiles: TMenuItem
        Caption = '-'
      end
      object miProfiles: TMenuItem
        Action = actProfiles
      end
      object miTailnets: TMenuItem
        Action = actTailnets
      end
      object miGateways: TMenuItem
        Action = actGateways
      end
      object miLockVault: TMenuItem
        Action = actLockVault
      end
      object miChangeMasterPassword: TMenuItem
        Action = actChangeMasterPassword
      end
      object miOptions: TMenuItem
        Action = actOptions
      end
      object miFileSep3: TMenuItem
        Caption = '-'
      end
      object miExit: TMenuItem
        Action = actExit
      end
    end
    object miServer: TMenuItem
      Caption = '&Server'
      object miConnect: TMenuItem
        Action = actConnect
      end
      object miDisconnect: TMenuItem
        Action = actDisconnect
      end
      object miConnectGroup: TMenuItem
        Action = actConnectGroup
      end
      object miDisconnectGroup: TMenuItem
        Action = actDisconnectGroup
      end
      object miWakeOnLan: TMenuItem
        Action = actWakeOnLan
      end
      object miFavorite: TMenuItem
        Action = actFavorite
      end
      object miForgetPassword: TMenuItem
        Action = actForgetPassword
      end
      object miSep1: TMenuItem
        Caption = '-'
      end
      object miNewServer: TMenuItem
        Action = actNewServer
      end
      object miNewGroup: TMenuItem
        Action = actNewGroup
      end
      object miSep2: TMenuItem
        Caption = '-'
      end
      object miRename: TMenuItem
        Action = actRename
      end
      object miDelete: TMenuItem
        Action = actDelete
      end
      object miSep3: TMenuItem
        Caption = '-'
      end
      object miProperties: TMenuItem
        Action = actProperties
      end
    end
    object miView: TMenuItem
      Caption = '&Beeld'
      object miGrid11: TMenuItem
        Action = actGrid11
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid21: TMenuItem
        Action = actGrid21
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid31: TMenuItem
        Action = actGrid31
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid41: TMenuItem
        Action = actGrid41
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid12: TMenuItem
        Action = actGrid12
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid22: TMenuItem
        Action = actGrid22
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid32: TMenuItem
        Action = actGrid32
        GroupIndex = 1
        RadioItem = True
      end
      object miGrid42: TMenuItem
        Action = actGrid42
        GroupIndex = 1
        RadioItem = True
      end
      object miGridCustom: TMenuItem
        Action = actGridCustom
        GroupIndex = 1
        RadioItem = True
      end
      object miGridSep: TMenuItem
        Caption = '-'
        GroupIndex = 1
      end
      object miGridEqualize: TMenuItem
        Action = actGridEqualize
        GroupIndex = 1
      end
      object miViewSep1: TMenuItem
        Caption = '-'
        GroupIndex = 1
      end
      object miTheme: TMenuItem
        Caption = 'Thema'
        GroupIndex = 1
        object miThemeSystem: TMenuItem
          Action = actThemeSystem
          GroupIndex = 2
          RadioItem = True
        end
        object miThemeLight: TMenuItem
          Action = actThemeLight
          GroupIndex = 2
          RadioItem = True
        end
        object miThemeDark: TMenuItem
          Action = actThemeDark
          GroupIndex = 2
          RadioItem = True
        end
      end
    end
    object miHelp: TMenuItem
      Caption = '&Help'
      object miHelpManual: TMenuItem
        Action = actHelpManual
      end
    end
  end
  object alMain: TActionList
    OnUpdate = alMainUpdate
    Left = 40
    Top = 140
    object actConnect: TAction
      Caption = 'Verbinden'#9'Enter'
      OnExecute = actConnectExecute
    end
    object actDisconnect: TAction
      Caption = 'Verbreken'#9'Ctrl+D'
      OnExecute = actDisconnectExecute
    end
    object actNewServer: TAction
      Caption = 'Nieuwe server...'#9'Ctrl+N'
      OnExecute = actNewServerExecute
    end
    object actNewGroup: TAction
      Caption = 'Nieuwe groep...'#9'Ctrl+G'
      OnExecute = actNewGroupExecute
    end
    object actRename: TAction
      Caption = 'Naam wijzigen'#9'F2'
      OnExecute = actRenameExecute
    end
    object actDelete: TAction
      Caption = 'Verwijderen'#9'Del'
      OnExecute = actDeleteExecute
    end
    object actProperties: TAction
      Caption = 'Eigenschappen...'#9'Alt+Enter'
      OnExecute = actPropertiesExecute
    end
    object actExit: TAction
      Caption = 'Afsluiten'
      OnExecute = actExitExecute
    end
    object actNewFile: TAction
      Caption = '&Nieuw bestand'
      OnExecute = actNewFileExecute
    end
    object actOpen: TAction
      Caption = '&Openen...'#9'Ctrl+O'
      OnExecute = actOpenExecute
    end
    object actSave: TAction
      Caption = 'Op&slaan'#9'Ctrl+S'
      OnExecute = actSaveExecute
    end
    object actSaveAs: TAction
      Caption = 'Opslaan &als...'
      OnExecute = actSaveAsExecute
    end
    object actSaveAll: TAction
      Caption = 'Alles opslaan'
      OnExecute = actSaveAllExecute
    end
    object actCloseFile: TAction
      Caption = 'Bestand s&luiten'
      OnExecute = actCloseFileExecute
    end
    object actProfiles: TAction
      Caption = 'Credential-profielen...'
      OnExecute = actProfilesExecute
    end
    object actTailnets: TAction
      Caption = 'Tailscale-netwerken...'
      OnExecute = actTailnetsExecute
    end
    object actGateways: TAction
      Caption = 'RDP-gateways...'
      OnExecute = actGatewaysExecute
    end
    object actWakeOnLan: TAction
      Caption = 'Wake-on-LAN-signaal versturen'
      OnExecute = actWakeOnLanExecute
    end
    object actTabDetach: TAction
      Caption = 'In een eigen venster'
      OnExecute = actTabDetachExecute
    end
    object actTabFullScreen: TAction
      Caption = 'Volledig scherm'
      OnExecute = actTabFullScreenExecute
    end
    object actTabDock: TAction
      Caption = 'Terugzetten in hoofdvenster'
      OnExecute = actTabDockExecute
    end
    object actConnectGroup: TAction
      Caption = 'Alle servers verbinden'
      OnExecute = actConnectGroupExecute
    end
    object actDisconnectGroup: TAction
      Caption = 'Alle servers verbreken'
      OnExecute = actDisconnectGroupExecute
    end
    object actForgetPassword: TAction
      Caption = 'Onthouden wachtwoord vergeten'
      OnExecute = actForgetPasswordExecute
    end
    object actFavorite: TAction
      Caption = 'Aan favorieten toevoegen'
      OnExecute = actFavoriteExecute
    end
    object actLockVault: TAction
      Caption = 'Wachtwoordkluis vergrendelen'
      OnExecute = actLockVaultExecute
    end
    object actChangeMasterPassword: TAction
      Caption = 'Hoofdwachtwoord wijzigen...'
      OnExecute = actChangeMasterPasswordExecute
    end
    object actOptions: TAction
      Caption = 'Opties...'
      OnExecute = actOptionsExecute
    end
    object actHelpManual: TAction
      Caption = 'Handleiding'#9'F1'
      Hint = 'De handleiding van RDCManagerX openen'
      OnExecute = actHelpManualExecute
    end
    object actGrid11: TAction
      Tag = 11
      Caption = '1 vak (niet splitsen)'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid21: TAction
      Tag = 21
      Caption = '2 naast elkaar'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid31: TAction
      Tag = 31
      Caption = '3 naast elkaar'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid41: TAction
      Tag = 41
      Caption = '4 naast elkaar'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid12: TAction
      Tag = 12
      Caption = '2 boven elkaar'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid22: TAction
      Tag = 22
      Caption = '2 x 2'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid32: TAction
      Tag = 32
      Caption = '3 x 2'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGrid42: TAction
      Tag = 42
      Caption = '4 x 2'
      GroupIndex = 1
      OnExecute = actGridPresetExecute
    end
    object actGridCustom: TAction
      Caption = 'Aangepast...'
      GroupIndex = 1
      OnExecute = actGridCustomExecute
    end
    object actGridEqualize: TAction
      Caption = 'Gelijk verdelen'
      OnExecute = actGridEqualizeExecute
    end
    object actThemeSystem: TAction
      Caption = 'Systeem (volgt Windows)'
      GroupIndex = 2
      OnExecute = actThemeSystemExecute
    end
    object actThemeLight: TAction
      Caption = 'Licht'
      GroupIndex = 2
      OnExecute = actThemeLightExecute
    end
    object actThemeDark: TAction
      Caption = 'Donker'
      GroupIndex = 2
      OnExecute = actThemeDarkExecute
    end
    object actTabMoveToOtherPane: TAction
      Caption = 'Naar het volgende vak verplaatsen'
      OnExecute = actTabMoveToOtherPaneExecute
    end
    object actTabReconnect: TAction
      Caption = 'Opnieuw verbinden'
      OnExecute = actTabReconnectExecute
    end
    object actTabDisconnect: TAction
      Caption = 'Verbreken'
      OnExecute = actTabDisconnectExecute
    end
    object actTabClose: TAction
      Caption = 'Tab sluiten'#9'Middelklik'
      OnExecute = actTabCloseExecute
    end
  end
  object pmTree: TPopupMenu
    Left = 40
    Top = 200
    object pmiConnect: TMenuItem
      Action = actConnect
      Default = True
    end
    object pmiDisconnect: TMenuItem
      Action = actDisconnect
    end
    object pmiConnectGroup: TMenuItem
      Action = actConnectGroup
    end
    object pmiDisconnectGroup: TMenuItem
      Action = actDisconnectGroup
    end
    object pmiWakeOnLan: TMenuItem
      Action = actWakeOnLan
    end
    object pmiFavorite: TMenuItem
      Action = actFavorite
    end
    object pmiForgetPassword: TMenuItem
      Action = actForgetPassword
    end
    object pmiSep1: TMenuItem
      Caption = '-'
    end
    object pmiNewServer: TMenuItem
      Action = actNewServer
    end
    object pmiNewGroup: TMenuItem
      Action = actNewGroup
    end
    object pmiSep2: TMenuItem
      Caption = '-'
    end
    object pmiRename: TMenuItem
      Action = actRename
    end
    object pmiDelete: TMenuItem
      Action = actDelete
    end
    object pmiSep3: TMenuItem
      Caption = '-'
    end
    object pmiProperties: TMenuItem
      Action = actProperties
    end
  end
  object pmTabs: TPopupMenu
    OnPopup = pmTabsPopup
    Left = 40
    Top = 260
    object pmtReconnect: TMenuItem
      Action = actTabReconnect
    end
    object pmtDisconnect: TMenuItem
      Action = actTabDisconnect
    end
    object pmtSep1: TMenuItem
      Caption = '-'
    end
    object pmtMoveToOtherPane: TMenuItem
      Action = actTabMoveToOtherPane
    end
    object pmtDetach: TMenuItem
      Action = actTabDetach
    end
    object pmtFullScreen: TMenuItem
      Action = actTabFullScreen
    end
    object pmtDock: TMenuItem
      Action = actTabDock
    end
    object pmtScale: TMenuItem
      Caption = 'Schaal'
      object pmtScaleAuto: TMenuItem
        Tag = 0
        Caption = 'Automatisch (volgt de monitor)'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale100: TMenuItem
        Tag = 100
        Caption = '100%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale125: TMenuItem
        Tag = 125
        Caption = '125%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale150: TMenuItem
        Tag = 150
        Caption = '150%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale175: TMenuItem
        Tag = 175
        Caption = '175%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale200: TMenuItem
        Tag = 200
        Caption = '200%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale250: TMenuItem
        Tag = 250
        Caption = '250%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
      object pmtScale300: TMenuItem
        Tag = 300
        Caption = '300%'
        GroupIndex = 3
        RadioItem = True
        OnClick = pmtScaleItemClick
      end
    end
    object pmtSep2: TMenuItem
      Caption = '-'
    end
    object pmtClose: TMenuItem
      Action = actTabClose
    end
  end
  object ilNodes: TImageList
    ColorDepth = cd32Bit
    Left = 40
    Top = 320
  end
  object dlgOpen: TOpenDialog
    DefaultExt = 'rdg'
    Filter = 'Verbindingsbestanden (*.rdg;*.rdcx)|*.rdg;*.rdcx|RDCMan-bestanden (*.rdg)|*.rdg|RDCManX-bestanden (*.rdcx)|*.rdcx|Alle bestanden (*.*)|*.*'
    Options = [ofHideReadOnly, ofAllowMultiSelect, ofPathMustExist, ofFileMustExist, ofEnableSizing]
    Title = 'Bestand openen'
    Left = 120
    Top = 80
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'rdg'
    Filter = 'RDCMan-bestand (*.rdg)|*.rdg|RDCManX-bestand (*.rdcx)|*.rdcx'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofPathMustExist, ofEnableSizing]
    Title = 'Bestand opslaan als'
    Left = 120
    Top = 140
  end
  object tmrClose: TTimer
    Enabled = False
    Interval = 5000
    OnTimer = tmrCloseTimer
    Left = 40
    Top = 380
  end
end
