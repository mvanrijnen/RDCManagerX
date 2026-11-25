object frmProperties: TfrmProperties
  ShowHint = True
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Eigenschappen'
  ClientHeight = 610
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
  object pcPages: TPageControl
    AlignWithMargins = True
    Left = 8
    Top = 8
    Width = 544
    Height = 548
    Margins.Left = 8
    Margins.Top = 8
    Margins.Right = 8
    Margins.Bottom = 0
    ActivePage = tsGeneral
    Align = alClient
    MultiLine = True
    TabOrder = 0
    object tsGeneral: TTabSheet
      Caption = 'Algemeen'
      object lblName: TLabel
        Hint =
          'Weergavenaam in de boom en op de tab. Bij een server optioneel: leeg ' +
          '= de servernaam.'
        Left = 12
        Top = 16
        Width = 32
        Height = 15
        Caption = 'Naam'
      end
      object lblServer: TLabel
        Hint = 'Hostnaam, volledige naam (FQDN) of IP-adres van de server.'
        Left = 12
        Top = 48
        Width = 98
        Height = 15
        Caption = 'Servernaam of IP'
      end
      object lblComment: TLabel
        Hint =
          'Vrije opmerking, bijv. waarvoor de server dient. Zichtbaar in de tool' +
          'tip in de boom.'
        Left = 12
        Top = 80
        Width = 61
        Height = 15
        Caption = 'Opmerking'
      end
      object edtName: TEdit
        Hint =
          'Weergavenaam in de boom en op de tab. Bij een server optioneel: leeg ' +
          '= de servernaam.'
        Left = 150
        Top = 12
        Width = 360
        Height = 23
        TabOrder = 0
        OnChange = edtNameChange
      end
      object edtServer: TEdit
        Hint = 'Hostnaam, volledige naam (FQDN) of IP-adres van de server.'
        Left = 150
        Top = 44
        Width = 360
        Height = 23
        TabOrder = 1
        OnChange = edtServerChange
      end
      object memComment: TMemo
        Hint =
          'Vrije opmerking, bijv. waarvoor de server dient. Zichtbaar in de tool' +
          'tip in de boom.'
        Left = 150
        Top = 76
        Width = 360
        Height = 110
        ScrollBars = ssVertical
        TabOrder = 2
      end
      object gbWakeOnLan: TGroupBox
        Left = 12
        Top = 200
        Width = 498
        Height = 166
        Caption = 'Wake-on-LAN'
        TabOrder = 3
        object lblMac: TLabel
          Hint =
            'MAC-adres van de netwerkkaart, nodig voor Wake-on-LAN (Server > Wake-' +
            'on-LAN-signaal versturen). Bijv. 00-11-22-33-44-55.'
          Left = 12
          Top = 28
          Width = 64
          Height = 15
          Caption = 'MAC-adres'
        end
        object lblWolBroadcast: TLabel
          Hint =
            'Broadcastadres waarheen het wekpakket gaat: 255.255.255.255, of het b' +
            'roadcastadres van het subnet van de server.'
          Left = 12
          Top = 60
          Width = 91
          Height = 15
          Caption = 'Broadcastadres'
        end
        object lblWolPort: TLabel
          Hint = 'UDP-poort voor het wekpakket (meestal 9, soms 7).'
          Left = 12
          Top = 92
          Width = 50
          Height = 15
          Caption = 'UDP-poort'
        end
        object lblWolHint: TLabel
          Left = 12
          Top = 120
          Width = 474
          Height = 38
          AutoSize = False
          Caption =
            'Leeg = geen Wake-on-LAN. Voor een ander subnet het broadcastadre' +
            's van dat subnet invullen (bijv. 192.168.10.255).'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clGrayText
          Font.Height = -12
          Font.Name = 'Segoe UI'
          Font.Style = []
          ParentFont = False
          WordWrap = True
        end
        object edtMac: TEdit
          Hint =
            'MAC-adres van de netwerkkaart, nodig voor Wake-on-LAN (Server > Wake-' +
            'on-LAN-signaal versturen). Bijv. 00-11-22-33-44-55.'
          Left = 138
          Top = 24
          Width = 160
          Height = 23
          TabOrder = 0
          TextHint = '00-11-22-33-44-55'
        end
        object edtWolBroadcast: TEdit
          Hint =
            'Broadcastadres waarheen het wekpakket gaat: 255.255.255.255, of het b' +
            'roadcastadres van het subnet van de server.'
          Left = 138
          Top = 56
          Width = 160
          Height = 23
          TabOrder = 1
        end
        object edtWolPort: TEdit
          Hint = 'UDP-poort voor het wekpakket (meestal 9, soms 7).'
          Left = 138
          Top = 88
          Width = 60
          Height = 23
          NumbersOnly = True
          TabOrder = 2
        end
      end
    end
    object tsLogon: TTabSheet
      Caption = 'Aanmelden'
      ImageIndex = 1
      object lblProfile: TLabel
        Hint =
          'Eigen aanmeldgegevens, of een credential-profiel van dit bestand (beh' +
          'eer via Bestand > Credential-profielen).'
        Left = 12
        Top = 48
        Width = 33
        Height = 15
        Caption = 'Profiel'
      end
      object lblUser: TLabel
        Hint = 'Gebruikersnaam; mag ook als DOMEIN\gebruiker of gebruiker@domein.'
        Left = 12
        Top = 80
        Width = 87
        Height = 15
        Caption = 'Gebruikersnaam'
      end
      object lblDomain: TLabel
        Hint =
          'Domein van de gebruiker. Leeg bij een lokaal account op de server, of' +
          ' als het domein al in de gebruikersnaam staat.'
        Left = 12
        Top = 112
        Width = 42
        Height = 15
        Caption = 'Domein'
      end
      object lblLogonHint: TLabel
        Left = 12
        Top = 152
        Width = 498
        Height = 64
        AutoSize = False
        Caption = 'Wachtwoorden worden nooit opgeslagen; bij elke verbinding wordt erom gevraagd.'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGrayText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = []
        ParentFont = False
        WordWrap = True
      end
      object chkLogonInherit: TCheckBox
        Hint =
          'Aan: de aanmeldgegevens van de bovenliggende groep gebruiken. Uit: ei' +
          'gen aanmeldgegevens voor deze server of groep.'
        Left = 12
        Top = 14
        Width = 498
        Height = 17
        Caption = 'Overnemen van bovenliggende groep'
        TabOrder = 0
        OnClick = chkLogonInheritClick
      end
      object cbProfile: TComboBox
        Hint =
          'Eigen aanmeldgegevens, of een credential-profiel van dit bestand (beh' +
          'eer via Bestand > Credential-profielen).'
        Left = 150
        Top = 44
        Width = 360
        Height = 23
        Style = csDropDownList
        TabOrder = 1
        OnChange = cbProfileChange
      end
      object edtUser: TEdit
        Hint = 'Gebruikersnaam; mag ook als DOMEIN\gebruiker of gebruiker@domein.'
        Left = 150
        Top = 76
        Width = 360
        Height = 23
        TabOrder = 2
      end
      object edtDomain: TEdit
        Hint =
          'Domein van de gebruiker. Leeg bij een lokaal account op de server, of' +
          ' als het domein al in de gebruikersnaam staat.'
        Left = 150
        Top = 108
        Width = 360
        Height = 23
        TabOrder = 3
      end
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 556
    Width = 560
    Height = 54
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
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
