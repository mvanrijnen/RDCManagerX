unit RdcmX.Model;

{
  Datamodel: TRdcFile (root) > TRdcGroup (genest) > TRdcServer.

  Properties en instellingssecties worden bewaard als XML-elementen (TRdcXmlNode) met getypeerde accessors
  erbovenop. Daardoor gaan onbekende elementen, onbekende enum-waarden en onvolledige secties ongewijzigd mee
  bij opslaan (round-trip met RDCMan), zonder dat het model elke RDCMan-variant hoeft te kennen.

  Overerving:
  - Elke node heeft per instellingsgroep een sectie met een Inherit-vlag. Een in het bestand ontbrekende
    sectie betekent Inherit = True. Effective(...) loopt omhoog tot de eerste node met Inherit = False;
    anders gelden de RDCMan-defaults (TRdcNode.AppDefaults: een lege sectie, dus alle getters geven de default).
  - Een eigen sectie (Inherit = False) waarin een kind-element ontbreekt: dat element krijgt de RDCMan-default
    en erft NIET van de ouder.
    TE VERIFIËREN in RDCMan: bij pcv-dev-04 ontbreekt <size> in <remoteDesktop>. Vermoeden: RDCMan
    schrijft <size> alleen bij een vaste afmeting (sameSizeAsClientArea = True maakt hem overbodig).
    Controle: RDCMan > eigenschappen van pcv-dev-04 > Remote Desktop Settings: staat er een custom size
    en welke? Zet hem op een vaste afmeting, sla op en kijk of <size> in het bestand verschijnt.
  - De root (file) erft in RDCMan van de "default settings" uit RDCMan's eigen opties (per gebruiker, buiten
    het bestand). Die kennen we niet; we gebruiken de hardcoded RDCMan-defaults hieronder.

  Wachtwoorden worden NOOIT opgeslagen (eis van de gebruiker): bij inlezen wordt de inhoud van <password>
  verwijderd (en gemeld), bij schrijven is <password /> altijd leeg.

  RDCMan-defaults en enum-waarden: wat in Voorbeeld.rdg voorkomt is zeker; de rest is gebaseerd op kennis van
  RDCMan 2.7/2.90 en gemarkeerd met "ONZEKER". Omdat waarden als tekst bewaard worden, gaat een onbekende
  waarde nooit verloren; de getypeerde getter geeft dan de default terug.
}

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils,
  RdcmX.XmlTree;

type
  // --- Enums met RDCMan-tekstwaarden --------------------------------------------------------------------------

  TRdcAudioRedirection = (arClient, arRemote, arNoSound);                 // ONZEKER: Client/Remote (NoSound gezien)
  TRdcAudioQuality = (aqDynamic, aqMedium, aqHigh);                       // ONZEKER: Medium/High (Dynamic gezien)
  TRdcAudioCapture = (acRecord, acDoNotRecord);                           // ONZEKER: Record (DoNotRecord gezien)
  TRdcKeyboardHook = (khClient, khRemote, khFullScreenClient);            // ONZEKER: Client/Remote (FullScreenClient gezien)
  TRdcSmartSize = (ssNone, ssScale);                                      // gezien: None, Scale. ONZEKER of er meer waarden zijn
  TRdcAuthentication = (auNone, auRequired, auWarn);                      // ONZEKER (namen); volgorde = AuthenticationLevel 0/1/2
  TRdcGatewayLogonMethod = (glmNTLM, glmSmartCard, glmAny);               // ONZEKER
  TRdcEncryptionMethod = (emLogonCredentials, emCertificate);             // ONZEKER
  TRdcProfileScope = (psLocal, psFile);
  TRdcDisplayMode = (dmDynamic, dmClientArea, dmFixed, dmFullScreen);     // RDCManX-extra
  /// <summary>Verbindingsroute (RDCManX-extra). Direct = het bestaande gedrag, inclusief gatewaySettings uit de .rdg.</summary>
  TRdcRouteKind = (rkDirect, rkTailscale, rkGateway);
  /// <summary>Gateway gebruiken: altijd / automatisch detecteren / altijd behalve voor lokale adressen.</summary>
  TRdcGatewayUsage = (guAlways, guAutoDetect, guBypassLocal);
  /// <summary>Aanmeldgegevens voor de gateway: die van de sessie / eigen (wachtwoord in de kluis) / vragen / smartcard.</summary>
  TRdcGatewayCredsMode = (gcmSession, gcmSeparate, gcmAsk, gcmSmartCard);

const
  cRdcAudioRedirectionNames: array[TRdcAudioRedirection] of string = ('Client', 'Remote', 'NoSound');
  cRdcAudioQualityNames: array[TRdcAudioQuality] of string = ('Dynamic', 'Medium', 'High');
  cRdcAudioCaptureNames: array[TRdcAudioCapture] of string = ('Record', 'DoNotRecord');
  cRdcKeyboardHookNames: array[TRdcKeyboardHook] of string = ('Client', 'Remote', 'FullScreenClient');
  cRdcSmartSizeNames: array[TRdcSmartSize] of string = ('None', 'Scale');
  cRdcAuthenticationNames: array[TRdcAuthentication] of string = ('None', 'Required', 'Warn');
  cRdcGatewayLogonMethodNames: array[TRdcGatewayLogonMethod] of string = ('NTLM', 'SmartCard', 'Any');
  cRdcEncryptionMethodNames: array[TRdcEncryptionMethod] of string = ('LogonCredentials', 'Certificate');
  cRdcProfileScopeNames: array[TRdcProfileScope] of string = ('Local', 'File');
  cRdcDisplayModeNames: array[TRdcDisplayMode] of string = ('Dynamic', 'ClientArea', 'Fixed', 'FullScreen');
  cRdcRouteKindNames: array[TRdcRouteKind] of string = ('Direct', 'Tailscale', 'Gateway');
  cRdcGatewayUsageNames: array[TRdcGatewayUsage] of string = ('Always', 'AutoDetect', 'BypassLocal');
  cRdcGatewayCredsModeNames: array[TRdcGatewayCredsMode] of string = ('Session', 'Separate', 'Ask', 'SmartCard');
  cRdcDefaultRdpPort = 3389;

  cRdcCustomProfileName = 'Custom';
  cRdcInheritNone = 'None';
  cRdcTrue = 'True';
  cRdcFalse = 'False';

type
  TRdcGroup = class;
  TRdcFile = class;

  // --- Instellingssecties ------------------------------------------------------------------------------------

  TRdcSettingsGroup = class abstract
  private
    FInherit: Boolean;
    FNode: TRdcXmlNode;
  protected
    function GetBool(const aName: string): Boolean;
    function GetInt(const aName: string): Integer;
    function GetValue(const aName: string): string;
    procedure SetBool(const aName: string; aValue: Boolean);
    procedure SetInt(const aName: string; aValue: Integer);
    procedure SetValue(const aName, aValue: string);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    /// <summary>Elementnaam in de .rdg (en sleutel in JSON).</summary>
    class function XmlName: string; virtual; abstract;
    /// <summary>Volgorde van de kind-elementen zoals RDCMan ze schrijft.</summary>
    class function ElementOrder: TArray<string>; virtual; abstract;
    /// <summary>RDCMan-default per element, in dezelfde volgorde als ElementOrder.</summary>
    class function ElementDefaults: TArray<string>; virtual; abstract;
    /// <summary>False voor RDCManX-extra's: die gaan nooit in de .rdg.</summary>
    class function InRdg: Boolean; virtual;
    class function DefaultFor(const aName: string): string;
    procedure Assign(aSource: TRdcSettingsGroup); virtual;
    /// <summary>Alle ontbrekende elementen met hun default toevoegen (voor een nieuw aangemaakte eigen sectie).</summary>
    procedure FillDefaults; virtual;
    function HasValue(const aName: string): Boolean;
    function IsEqual(aOther: TRdcSettingsGroup): Boolean;
    /// <summary>Wis alle waarden (sectie wordt "leeg": alle getters geven de default).</summary>
    procedure Clear;
    /// <summary>Vervangt het element (neemt eigendom over); de naam wordt XmlName.</summary>
    procedure ReplaceNode(aNode: TRdcXmlNode);
    property Inherit: Boolean read FInherit write FInherit;
    /// <summary>Ruwe tekstwaarde van een kind-element (ontbrekend = RDCMan-default); schrijven in RDCMan-volgorde.</summary>
    property Values[const aName: string]: string read GetValue write SetValue;
    /// <summary>Het element zelf (naam = XmlName, met attributen zoals inherit="None").</summary>
    property Node: TRdcXmlNode read FNode;
  end;

  TRdcSettingsGroupClass = class of TRdcSettingsGroup;

  /// <summary>Gedeelde basis voor logonCredentials en credentialsProfile: profileName (scope), userName, password, domain.</summary>
  TRdcCredentialsSettings = class(TRdcSettingsGroup)
  private
    function GetDomain: string;
    function GetProfileName: string;
    function GetProfileScope: TRdcProfileScope;
    function GetUserName: string;
    procedure SetDomain(const aValue: string);
    procedure SetProfileName(const aValue: string);
    procedure SetProfileScope(aValue: TRdcProfileScope);
    procedure SetUserName(const aValue: string);
  public
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;
    procedure FillDefaults; override;
    /// <summary>Inline credentials (profileName "Custom", scope Local).</summary>
    function IsCustom: Boolean;
    /// <summary>Verwijzing naar een profiel in credentialsProfiles van het bestand.</summary>
    function IsFileProfile: Boolean;
    /// <summary>Verwijzing naar een globaal RDCMan-profiel buiten het bestand: niet beschikbaar in RDCManX.</summary>
    function IsExternalProfile: Boolean;
    /// <summary>Splitst userName/domain in de combinatie voor de RDP-control, zonder dubbel domein.</summary>
    class procedure SplitLogon(const aRawUserName, aRawDomain: string; out aDomain, aUserName: string); static;
    property Domain: string read GetDomain write SetDomain;
    property ProfileName: string read GetProfileName write SetProfileName;
    property ProfileScope: TRdcProfileScope read GetProfileScope write SetProfileScope;
    property UserName: string read GetUserName write SetUserName;
  end;

  TRdcLogonCredentials = class(TRdcCredentialsSettings)
  public
    class function XmlName: string; override;
  end;

  TRdcConnectionSettings = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;   // ONZEKER: elementnamen en volgorde (niet in het voorbeeld)
    class function ElementDefaults: TArray<string>; override;
    function ConnectToConsole: Boolean;
    function LoadBalanceInfo: string;
    function Port: Integer;
    function StartProgram: string;
    function WorkingDir: string;
    procedure SetPort(aValue: Integer);
  end;

  TRdcGatewaySettings = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;   // ONZEKER: elementnamen en volgorde (niet in het voorbeeld)
    class function ElementDefaults: TArray<string>; override;
    procedure FillDefaults; override;
    function Enabled: Boolean;
    function HostName: string;
    function LocalBypass: Boolean;
    function CredSharing: Boolean;
    function LogonMethod: TRdcGatewayLogonMethod;
    function UserName: string;
    function Domain: string;
  end;

  TRdcRemoteDesktopSettings = class(TRdcSettingsGroup)
  private
    function GetColorDepth: Integer;
    function GetFullScreen: Boolean;
    function GetSameSizeAsClientArea: Boolean;
    procedure SetColorDepth(aValue: Integer);
    procedure SetFullScreen(aValue: Boolean);
    procedure SetSameSizeAsClientArea(aValue: Boolean);
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;   // ONZEKER: default size 1024 x 768
    function Width: Integer;
    function Height: Integer;
    procedure SetSize(aWidth, aHeight: Integer);
    property ColorDepth: Integer read GetColorDepth write SetColorDepth;
    property FullScreen: Boolean read GetFullScreen write SetFullScreen;
    property SameSizeAsClientArea: Boolean read GetSameSizeAsClientArea write SetSameSizeAsClientArea;
  end;

  TRdcLocalResources = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;   // ONZEKER: defaults
    function AudioRedirection: TRdcAudioRedirection;
    function AudioQuality: TRdcAudioQuality;
    function AudioCapture: TRdcAudioCapture;
    function KeyboardHook: TRdcKeyboardHook;
    function RedirectClipboard: Boolean;
    function RedirectDrives: Boolean;
    function RedirectPrinters: Boolean;
    function RedirectPorts: Boolean;
    function RedirectSmartCards: Boolean;
    function RedirectPnpDevices: Boolean;
  end;

  TRdcSecuritySettings = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;   // ONZEKER: elementnaam "authentication"
    class function ElementDefaults: TArray<string>; override;
    function Authentication: TRdcAuthentication;
    procedure SetAuthentication(aValue: TRdcAuthentication);
  end;

  TRdcDisplaySettings = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;   // ONZEKER: defaults
    function LiveThumbnailUpdates: Boolean;
    function AllowThumbnailSessionInteraction: Boolean;
    function ShowDisconnectedThumbnails: Boolean;
    function ThumbnailScale: Integer;
    function SmartSizeDockedWindows: TRdcSmartSize;
    function SmartSizeUndockedWindows: TRdcSmartSize;
  end;

  TRdcEncryptionSettings = class(TRdcSettingsGroup)
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;   // ONZEKER: elementnamen en volgorde (niet in het voorbeeld)
    class function ElementDefaults: TArray<string>; override;
    function EncryptionMethod: TRdcEncryptionMethod;
  end;

  /// <summary>RDCManX-extra's: niet in de .rdg (sidecar / .rdcx).</summary>
  TRdcxSettings = class(TRdcSettingsGroup)
  private
    function GetDesktopScale: Integer;
    function GetDisplayMode: TRdcDisplayMode;
    function GetReconnectOnResizeFallback: Boolean;
    function GetResizeDebounceMs: Integer;
    procedure SetDesktopScale(aValue: Integer);
    procedure SetDisplayMode(aValue: TRdcDisplayMode);
    procedure SetReconnectOnResizeFallback(aValue: Boolean);
    procedure SetResizeDebounceMs(aValue: Integer);
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;
    class function InRdg: Boolean; override;
    property DisplayMode: TRdcDisplayMode read GetDisplayMode write SetDisplayMode;
    /// <summary>Schaal in de sessie in procenten; 0 = automatisch (volgt de monitor).</summary>
    property DesktopScale: Integer read GetDesktopScale write SetDesktopScale;
    property ReconnectOnResizeFallback: Boolean read GetReconnectOnResizeFallback write SetReconnectOnResizeFallback;
    property ResizeDebounceMs: Integer read GetResizeDebounceMs write SetResizeDebounceMs;
  end;

  /// <summary>RDCManX-gegevens van de machine zelf (Wake-on-LAN). Erft NIET: alleen de eigen sectie van een server telt.
  /// Inherit = True betekent hier "niets ingevuld".</summary>
  TRdcxHostSettings = class(TRdcSettingsGroup)
  private
    function GetMacAddress: string;
    function GetWolBroadcast: string;
    function GetWolPort: Integer;
    procedure SetMacAddress(const aValue: string);
    procedure SetWolBroadcast(const aValue: string);
    procedure SetWolPort(aValue: Integer);
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;
    class function InRdg: Boolean; override;
    property MacAddress: string read GetMacAddress write SetMacAddress;
    property WolBroadcast: string read GetWolBroadcast write SetWolBroadcast;
    property WolPort: Integer read GetWolPort write SetWolPort;
  end;

  /// <summary>RDCManX-extra: route per server of groep (erft, zoals de andere secties). Verwijst met een id naar
  /// een Tailscale-netwerk of gateway uit het bestand (TRdcFile.Tailnets/Gateways).</summary>
  TRdcxRouteSettings = class(TRdcSettingsGroup)
  private
    function GetGatewayId: string;
    function GetKind: TRdcRouteKind;
    function GetTailnetHost: string;
    function GetTailnetId: string;
    function GetPingEnabled: Boolean;
    procedure SetPingEnabled(aValue: Boolean);
    procedure SetGatewayId(const aValue: string);
    procedure SetKind(aValue: TRdcRouteKind);
    procedure SetTailnetHost(const aValue: string);
    procedure SetTailnetId(const aValue: string);
  public
    class function XmlName: string; override;
    class function ElementOrder: TArray<string>; override;
    class function ElementDefaults: TArray<string>; override;
    class function InRdg: Boolean; override;
    property Kind: TRdcRouteKind read GetKind write SetKind;
    property TailnetId: string read GetTailnetId write SetTailnetId;
    /// <summary>Adres van de server in het tailnet (MagicDNS-naam of 100.x); leeg = de hostnaam van de server.</summary>
    property TailnetHost: string read GetTailnetHost write SetTailnetHost;
    property GatewayId: string read GetGatewayId write SetGatewayId;
    /// <summary>Bereikbaarheid op de achtergrond controleren (ping, anders TCP naar de RDP-poort); alleen bij Direct.</summary>
    property PingEnabled: Boolean read GetPingEnabled write SetPingEnabled;
  end;

  TRdcNodeSettings = class
  private
    FGroups: TObjectList<TRdcSettingsGroup>;
    function GetConnection: TRdcConnectionSettings;
    function GetDisplay: TRdcDisplaySettings;
    function GetEncryption: TRdcEncryptionSettings;
    function GetExtras: TRdcxSettings;
    function GetGateway: TRdcGatewaySettings;
    function GetHost: TRdcxHostSettings;
    function GetLocalResources: TRdcLocalResources;
    function GetLogon: TRdcLogonCredentials;
    function GetRemoteDesktop: TRdcRemoteDesktopSettings;
    function GetRoute: TRdcxRouteSettings;
    function GetSecurity: TRdcSecuritySettings;
  public
    constructor Create(aInherit: Boolean);
    destructor Destroy; override;
    procedure Assign(aSource: TRdcNodeSettings);
    function Find(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
    function FindByXmlName(const aXmlName: string): TRdcSettingsGroup;
    /// <summary>Alle secties in de volgorde waarin RDCMan ze schrijft (ONZEKER voor connection/gateway/security/encryption).</summary>
    property Groups: TObjectList<TRdcSettingsGroup> read FGroups;
    property Connection: TRdcConnectionSettings read GetConnection;
    property Display: TRdcDisplaySettings read GetDisplay;
    property Encryption: TRdcEncryptionSettings read GetEncryption;
    property Extras: TRdcxSettings read GetExtras;
    property Gateway: TRdcGatewaySettings read GetGateway;
    /// <summary>Machinegegevens (WOL); nooit via Effective gebruiken, erft niet.</summary>
    property Host: TRdcxHostSettings read GetHost;
    property LocalResources: TRdcLocalResources read GetLocalResources;
    property Logon: TRdcLogonCredentials read GetLogon;
    property RemoteDesktop: TRdcRemoteDesktopSettings read GetRemoteDesktop;
    property Route: TRdcxRouteSettings read GetRoute;
    property Security: TRdcSecuritySettings read GetSecurity;
  end;

  // --- Nodes -------------------------------------------------------------------------------------------------

  TRdcNode = class;

  /// <summary>Onbekend element op node-niveau; wordt teruggeschreven direct na zijn anker.</summary>
  TRdcUnknownElement = class
  public
    Element: TRdcXmlNode;
    /// <summary>Elementnaam van het voorgaande bekende element ('' = vooraan), of leeg als AnchorNode gezet is.</summary>
    AnchorName: string;
    /// <summary>Voorgaande kind-node (group/server), indien het anker een kind is.</summary>
    AnchorNode: TRdcNode;
    destructor Destroy; override;
  end;

  TRdcNode = class abstract
  private
    class var FAppDefaults: TRdcNodeSettings;
  private
    FParent: TRdcGroup;
    FElementAttributes: TRdcXmlNode;
    FProperties: TRdcXmlNode;
    FSettings: TRdcNodeSettings;
    FUnknown: TObjectList<TRdcUnknownElement>;
    function GetComment: string;
    function GetFile: TRdcFile;
    function GetName: string;
    procedure SetComment(const aValue: string);
    procedure SetName(const aValue: string);
  protected
    function PropertyOrder: TArray<string>; virtual; abstract;
    procedure SetProperty(const aName, aValue: string);
  public
    constructor Create(const aName: string); virtual;
    destructor Destroy; override;
    class constructor CreateClass;
    class destructor DestroyClass;
    /// <summary>Weergavetekst in boom en favorites-pad: groep = Name, server = DisplayName of anders Name.</summary>
    function Caption: string; virtual;
    function Effective(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
    /// <summary>Wat deze node zou erven als Inherit aan staat (beginnend bij de parent).</summary>
    function InheritedValue(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
    function EffectiveConnection: TRdcConnectionSettings;
    function EffectiveDisplay: TRdcDisplaySettings;
    function EffectiveExtras: TRdcxSettings;
    function EffectiveGateway: TRdcGatewaySettings;
    function EffectiveLocalResources: TRdcLocalResources;
    function EffectiveLogon: TRdcLogonCredentials;
    function EffectiveRemoteDesktop: TRdcRemoteDesktopSettings;
    function EffectiveRoute: TRdcxRouteSettings;
    function EffectiveSecurity: TRdcSecuritySettings;
    /// <summary>Effectieve credentials (inclusief file-profiel) gesplitst voor de RDP-control. False bij een extern profiel of onbekend file-profiel.</summary>
    function ResolveLogon(out aDomain, aUserName: string): Boolean;
    function IsDescendantOf(aGroup: TRdcGroup): Boolean;
    /// <summary>Pad zoals in &lt;favorites&gt;: rootnaam\groep\...\caption. Met aDuplicateSuffix: #2, #3 ... bij dubbele captions op hetzelfde niveau.</summary>
    function Path(aDuplicateSuffix: Boolean = False): string;
    /// <summary>Caption, met #n als er eerder op hetzelfde niveau een node met dezelfde caption staat.</summary>
    function PathSegment(aDuplicateSuffix: Boolean): string;
    class property AppDefaults: TRdcNodeSettings read FAppDefaults;
    property Comment: string read GetComment write SetComment;
    /// <summary>Attributen op het &lt;group&gt;/&lt;server&gt;-element zelf (normaal geen); bewaard voor round-trip.</summary>
    property ElementAttributes: TRdcXmlNode read FElementAttributes;
    /// <summary>Groep: naam. Server: hostnaam.</summary>
    property Name: string read GetName write SetName;
    property Parent: TRdcGroup read FParent;
    property Properties: TRdcXmlNode read FProperties;
    property RdcFile: TRdcFile read GetFile;
    property Settings: TRdcNodeSettings read FSettings;
    property Unknown: TObjectList<TRdcUnknownElement> read FUnknown;
  end;

  TRdcNodeClass = class of TRdcNode;

  TRdcGroup = class(TRdcNode)
  private
    FChildren: TObjectList<TRdcNode>;
    function GetChild(aIndex: Integer): TRdcNode;
    function GetCount: Integer;
    function GetExpanded: Boolean;
    procedure SetExpanded(aValue: Boolean);
  protected
    function PropertyOrder: TArray<string>; override;
  public
    constructor Create(const aName: string); override;
    destructor Destroy; override;
    function Add(aNode: TRdcNode): TRdcNode;
    procedure Insert(aIndex: Integer; aNode: TRdcNode);
    function Extract(aNode: TRdcNode): TRdcNode;
    /// <summary>Verwijdert en geeft vrij; verwijzingen in favorites/connected/recentlyUsed worden opgeruimd.</summary>
    procedure Delete(aNode: TRdcNode);
    function IndexOf(aNode: TRdcNode): Integer;
    procedure MoveHere(aNode: TRdcNode; aIndex: Integer = -1);
    procedure CollectServers(aList: TList<TRdcNode>);
    procedure CollectNodes(aList: TList<TRdcNode>);
    function FindChildByCaption(const aCaption: string; aOccurrence: Integer; aPreferServer: Boolean): TRdcNode;
    property Count: Integer read GetCount;
    property Children[aIndex: Integer]: TRdcNode read GetChild; default;
    property Expanded: Boolean read GetExpanded write SetExpanded;
  end;

  TRdcServer = class(TRdcNode)
  private
    function GetDisplayName: string;
    procedure SetDisplayName(const aValue: string);
  protected
    function PropertyOrder: TArray<string>; override;
  public
    function Caption: string; override;
    property DisplayName: string read GetDisplayName write SetDisplayName;
  end;

  // --- Bestand -------------------------------------------------------------------------------------------------

  TRdcCredentialProfile = class(TRdcCredentialsSettings)
  public
    class function XmlName: string; override;
  end;

  TRdcNodeRef = record
    Path: string;
    Node: TRdcNode;
  end;

  /// <summary>&lt;favorites&gt; / &lt;connected&gt; / &lt;recentlyUsed&gt;: verwijzingen naar nodes; onherleidbare paden blijven als tekst bewaard.</summary>
  TRdcNodeRefList = class
  private
    FItems: TList<TRdcNodeRef>;
    FPresent: Boolean;
    function GetCount: Integer;
    function GetItem(aIndex: Integer): TRdcNodeRef;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(aNode: TRdcNode); overload;
    procedure AddPath(const aPath: string; aNode: TRdcNode);
    procedure Clear;
    function Contains(aNode: TRdcNode): Boolean;
    procedure Remove(aNode: TRdcNode);
    /// <summary>Huidig pad: van de node als die bestaat, anders het oorspronkelijke pad.</summary>
    function CurrentPath(aIndex: Integer): string;
    property Count: Integer read GetCount;
    property Items[aIndex: Integer]: TRdcNodeRef read GetItem; default;
    /// <summary>Element stond in het bestand (ook leeg, bijv. &lt;connected /&gt;).</summary>
    property Present: Boolean read FPresent write FPresent;
  end;

  TRdcFileFormat = (ffRdg, ffRdcx);

  /// <summary>Tailscale-netwerk (RDCManX-extra, per bestand; nooit in de .rdg). Geheimen (auth key, state-sleutel)
  /// staan NIET hier maar in de wachtwoordkluis van deze pc, op Id.</summary>
  TRdcTailnetDef = class
  public
    Id: string;
    Name: string;
    /// <summary>Naam van deze pc in het tailnet; leeg = rdpclient-&lt;computernaam&gt; van de pc waarop je werkt.</summary>
    NodeHostName: string;
    /// <summary>Node verdwijnt na afsluiten; state alleen in het geheugen.</summary>
    Ephemeral: Boolean;
    /// <summary>Eigen control server (Headscale); leeg = Tailscale.</summary>
    ControlUrl: string;
    /// <summary>Lokaal adres voor de forwards; leeg = 127.0.0.2.</summary>
    LocalAddress: string;
    constructor Create;
    procedure Assign(aSource: TRdcTailnetDef);
  end;

  /// <summary>RD Gateway (RDCManX-extra, per bestand; nooit in de .rdg). Het wachtwoord staat in de kluis, op Id.</summary>
  TRdcGatewayDef = class
  public
    Id: string;
    Name: string;
    HostName: string;
    /// <summary>0 = standaard (443).</summary>
    Port: Integer;
    Usage: TRdcGatewayUsage;
    CredsMode: TRdcGatewayCredsMode;
    AuthMethod: TRdcGatewayLogonMethod;
    UserName: string;
    Domain: string;
    /// <summary>Voor later: gateway bereikbaar via dit Tailscale-netwerk (nog niet gebruikt).</summary>
    TailnetId: string;
    constructor Create;
    procedure Assign(aSource: TRdcGatewayDef);
    /// <summary>host of host:poort, zoals de RDP-control hem verwacht.</summary>
    function Address: string;
  end;

  TRdcFile = class(TRdcGroup)
  private
    FFileName: string;
    FFormat: TRdcFileFormat;
    FModified: Boolean;
    FRootElement: TRdcXmlNode;
    FXmlFormat: TRdcXmlFormat;
    FProfiles: TObjectList<TRdcCredentialProfile>;
    FProfilesElement: TRdcXmlNode;
    FFavorites: TRdcNodeRefList;
    FConnected: TRdcNodeRefList;
    FRecentlyUsed: TRdcNodeRefList;
    FRootUnknown: TObjectList<TRdcUnknownElement>;
    FSidecarOrphans: TDictionary<string, string>;
    FTailnets: TObjectList<TRdcTailnetDef>;
    FGateways: TObjectList<TRdcGatewayDef>;
    FWarnings: TStringList;
    FLoadedHash: string;
    FLoadedTimestamp: TDateTime;
    FBackupMade: Boolean;
  public
    constructor Create(const aName: string); override;
    destructor Destroy; override;
    function FindProfile(const aProfileName: string): TRdcCredentialProfile;
    /// <summary>Nieuw profiel in credentialsProfiles (zonder wachtwoord, dat wordt nooit opgeslagen).</summary>
    function AddProfile(const aProfileName, aUserName, aDomain: string): TRdcCredentialProfile;
    /// <summary>Aantal eigen secties (logonCredentials/gatewaySettings) die met scope="File" naar dit profiel verwijzen.</summary>
    function ProfileUsageCount(const aProfileName: string): Integer;
    /// <summary>Verwijzingen (scope="File") naar aOldName omzetten naar aNewName.</summary>
    procedure RenameProfileReferences(const aOldName, aNewName: string);
    /// <summary>Zoekt een node op pad (formaat van &lt;favorites&gt;); met #n-suffix voor dubbele captions.</summary>
    function FindByPath(const aPath: string): TRdcNode;
    /// <summary>Opruimen van verwijzingen naar een node die verwijderd wordt (incl. subnodes).</summary>
    procedure NodeRemoved(aNode: TRdcNode);
    function FindTailnet(const aId: string): TRdcTailnetDef;
    function FindGateway(const aId: string): TRdcGatewayDef;
    /// <summary>Aantal eigen route-secties die naar dit netwerk / deze gateway verwijzen.</summary>
    function TailnetUsageCount(const aId: string): Integer;
    function GatewayUsageCount(const aId: string): Integer;
    property FileName: string read FFileName write FFileName;
    property Format: TRdcFileFormat read FFormat write FFormat;
    property Modified: Boolean read FModified write FModified;
    /// <summary>Het &lt;RDCMan&gt;-element zonder kinderen: attributen programVersion/schemaVersion e.d.</summary>
    property RootElement: TRdcXmlNode read FRootElement;
    property XmlFormat: TRdcXmlFormat read FXmlFormat write FXmlFormat;
    property Profiles: TObjectList<TRdcCredentialProfile> read FProfiles;
    /// <summary>Het &lt;credentialsProfiles&gt;-element (attributen), nil als het niet in het bestand stond.</summary>
    property ProfilesElement: TRdcXmlNode read FProfilesElement write FProfilesElement;
    property Favorites: TRdcNodeRefList read FFavorites;
    property Connected: TRdcNodeRefList read FConnected;
    property RecentlyUsed: TRdcNodeRefList read FRecentlyUsed;
    /// <summary>Onbekende elementen direct onder &lt;RDCMan&gt;; anker 'file', 'connected', 'favorites', 'recentlyUsed' of ''.</summary>
    property RootUnknown: TObjectList<TRdcUnknownElement> read FRootUnknown;
    /// <summary>Sidecar-entries (pad -> JSON) zonder bijbehorende node; worden ongewijzigd terug geschreven.</summary>
    property SidecarOrphans: TDictionary<string, string> read FSidecarOrphans;
    /// <summary>Tailscale-netwerken en gateways van dit bestand (sidecar / .rdcx).</summary>
    property Tailnets: TObjectList<TRdcTailnetDef> read FTailnets;
    property Gateways: TObjectList<TRdcGatewayDef> read FGateways;
    /// <summary>Meldingen bij laden (bijv. verwijderde wachtwoorden, onherleidbare paden).</summary>
    property Warnings: TStringList read FWarnings;
    property LoadedHash: string read FLoadedHash write FLoadedHash;
    property LoadedTimestamp: TDateTime read FLoadedTimestamp write FLoadedTimestamp;
    property BackupMade: Boolean read FBackupMade write FBackupMade;
  end;

function RdcBoolText(aValue: Boolean): string;
function RdcTextToBool(const aText: string; aDefault: Boolean): Boolean;
function RdcTextToEnum(const aText: string; const aNames: array of string; aDefault: Integer): Integer;

implementation

uses
  System.StrUtils,
  RdcmX.Lang;

function RdcBoolText(aValue: Boolean): string;
begin
  if aValue then
    Result := cRdcTrue
  else
    Result := cRdcFalse;
end;

function RdcTextToBool(const aText: string; aDefault: Boolean): Boolean;
begin
  if SameText(aText, cRdcTrue) then
    Result := True
  else if SameText(aText, cRdcFalse) then
    Result := False
  else
    Result := aDefault;
end;

function RdcTextToEnum(const aText: string; const aNames: array of string; aDefault: Integer): Integer;
var
  lIndex: Integer;
begin
  for lIndex := Low(aNames) to High(aNames) do
    if SameText(aNames[lIndex], aText) then
      Exit(lIndex);
  Result := aDefault;
end;

{ TRdcSettingsGroup }

constructor TRdcSettingsGroup.Create;
begin
  inherited Create;
  FInherit := True;
  FNode := TRdcXmlNode.Create(XmlName);
end;

destructor TRdcSettingsGroup.Destroy;
begin
  FNode.Free;
  inherited Destroy;
end;

class function TRdcSettingsGroup.InRdg: Boolean;
begin
  Result := True;
end;

class function TRdcSettingsGroup.DefaultFor(const aName: string): string;
var
  lDefaults: TArray<string>;
  lIndex: Integer;
  lOrder: TArray<string>;
begin
  lOrder := ElementOrder;
  lDefaults := ElementDefaults;
  for lIndex := 0 to High(lOrder) do
    if lOrder[lIndex] = aName then
      Exit(lDefaults[lIndex]);
  Result := '';
end;

procedure TRdcSettingsGroup.Assign(aSource: TRdcSettingsGroup);
begin
  FInherit := aSource.FInherit;
  FNode.Free;
  FNode := aSource.FNode.Clone;
end;

procedure TRdcSettingsGroup.Clear;
begin
  FNode.Children.Clear;
end;

procedure TRdcSettingsGroup.ReplaceNode(aNode: TRdcXmlNode);
begin
  FNode.Free;
  FNode := aNode;
  FNode.Name := XmlName;
end;

procedure TRdcSettingsGroup.FillDefaults;
var
  lDefaults: TArray<string>;
  lIndex: Integer;
  lOrder: TArray<string>;
begin
  lOrder := ElementOrder;
  lDefaults := ElementDefaults;
  for lIndex := 0 to High(lOrder) do
    if not HasValue(lOrder[lIndex]) then
      SetChildTextOrdered(FNode, lOrder[lIndex], lDefaults[lIndex], lOrder);
end;

function TRdcSettingsGroup.HasValue(const aName: string): Boolean;
begin
  Result := FNode.FindChild(aName) <> nil;
end;

function TRdcSettingsGroup.IsEqual(aOther: TRdcSettingsGroup): Boolean;
begin
  Result := (aOther <> nil) and (FInherit = aOther.FInherit) and FNode.IsEqual(aOther.FNode);
end;

function TRdcSettingsGroup.GetValue(const aName: string): string;
begin
  Result := FNode.ChildText(aName, DefaultFor(aName));
end;

procedure TRdcSettingsGroup.SetValue(const aName, aValue: string);
begin
  SetChildTextOrdered(FNode, aName, aValue, ElementOrder);
end;

function TRdcSettingsGroup.GetBool(const aName: string): Boolean;
begin
  Result := RdcTextToBool(GetValue(aName), RdcTextToBool(DefaultFor(aName), False));
end;

procedure TRdcSettingsGroup.SetBool(const aName: string; aValue: Boolean);
begin
  SetValue(aName, RdcBoolText(aValue));
end;

function TRdcSettingsGroup.GetInt(const aName: string): Integer;
begin
  Result := StrToIntDef(GetValue(aName), StrToIntDef(DefaultFor(aName), 0));
end;

procedure TRdcSettingsGroup.SetInt(const aName: string; aValue: Integer);
begin
  SetValue(aName, IntToStr(aValue));
end;

{ TRdcCredentialsSettings }

class function TRdcCredentialsSettings.ElementOrder: TArray<string>;
begin
  Result := ['profileName', 'userName', 'password', 'domain'];
end;

class function TRdcCredentialsSettings.ElementDefaults: TArray<string>;
begin
  Result := [cRdcCustomProfileName, '', '', ''];
end;

procedure TRdcCredentialsSettings.FillDefaults;
var
  lProfile: TRdcXmlNode;
begin
  inherited FillDefaults;
  lProfile := Node.FindChild('profileName');
  if (lProfile <> nil) and not lProfile.HasAttribute('scope') then
    lProfile.SetAttribute('scope', cRdcProfileScopeNames[psLocal]);
end;

function TRdcCredentialsSettings.GetDomain: string;
begin
  Result := GetValue('domain');
end;

function TRdcCredentialsSettings.GetProfileName: string;
begin
  Result := GetValue('profileName');
end;

function TRdcCredentialsSettings.GetProfileScope: TRdcProfileScope;
var
  lProfile: TRdcXmlNode;
begin
  lProfile := Node.FindChild('profileName');
  if lProfile <> nil then
    Result := TRdcProfileScope(RdcTextToEnum(lProfile.GetAttribute('scope'), cRdcProfileScopeNames, Ord(psLocal)))
  else
    Result := psLocal;
end;

function TRdcCredentialsSettings.GetUserName: string;
begin
  Result := GetValue('userName');
end;

procedure TRdcCredentialsSettings.SetDomain(const aValue: string);
begin
  SetValue('domain', aValue);
end;

procedure TRdcCredentialsSettings.SetProfileName(const aValue: string);
begin
  SetValue('profileName', aValue);
  if not Node.FindChild('profileName').HasAttribute('scope') then
    Node.FindChild('profileName').SetAttribute('scope', cRdcProfileScopeNames[psLocal]);
end;

procedure TRdcCredentialsSettings.SetProfileScope(aValue: TRdcProfileScope);
begin
  if Node.FindChild('profileName') = nil then
    SetValue('profileName', cRdcCustomProfileName);
  Node.FindChild('profileName').SetAttribute('scope', cRdcProfileScopeNames[aValue]);
end;

procedure TRdcCredentialsSettings.SetUserName(const aValue: string);
begin
  SetValue('userName', aValue);
end;

function TRdcCredentialsSettings.IsCustom: Boolean;
begin
  Result := (ProfileScope = psLocal) and SameText(ProfileName, cRdcCustomProfileName);
end;

function TRdcCredentialsSettings.IsFileProfile: Boolean;
begin
  Result := ProfileScope = psFile;
end;

function TRdcCredentialsSettings.IsExternalProfile: Boolean;
begin
  Result := (ProfileScope = psLocal) and not SameText(ProfileName, cRdcCustomProfileName);
end;

class procedure TRdcCredentialsSettings.SplitLogon(const aRawUserName, aRawDomain: string; out aDomain, aUserName: string);
var
  lSlash: Integer;
begin
  lSlash := Pos('\', aRawUserName);
  if lSlash > 0 then
  begin
    // DOMEIN\gebruiker (ook .\gebruiker voor een lokaal account): het voorvoegsel wint, geen dubbel domein.
    aDomain := Copy(aRawUserName, 1, lSlash - 1);
    aUserName := Copy(aRawUserName, lSlash + 1, MaxInt);
  end
  else if Pos('@', aRawUserName) > 0 then
  begin
    // UPN (gebruiker@domein): domein leeg laten.
    aDomain := '';
    aUserName := aRawUserName;
  end
  else
  begin
    aDomain := aRawDomain;
    aUserName := aRawUserName;
  end;
end;

{ TRdcLogonCredentials }

class function TRdcLogonCredentials.XmlName: string;
begin
  Result := 'logonCredentials';
end;

{ TRdcCredentialProfile }

class function TRdcCredentialProfile.XmlName: string;
begin
  Result := 'credentialsProfile';
end;

{ TRdcConnectionSettings }

class function TRdcConnectionSettings.XmlName: string;
begin
  Result := 'connectionSettings';
end;

class function TRdcConnectionSettings.ElementOrder: TArray<string>;
begin
  Result := ['connectToConsole', 'startProgram', 'workingDir', 'port', 'loadBalanceInfo'];
end;

class function TRdcConnectionSettings.ElementDefaults: TArray<string>;
begin
  Result := [cRdcFalse, '', '', '3389', ''];
end;

function TRdcConnectionSettings.ConnectToConsole: Boolean;
begin
  Result := GetBool('connectToConsole');
end;

function TRdcConnectionSettings.LoadBalanceInfo: string;
begin
  Result := GetValue('loadBalanceInfo');
end;

function TRdcConnectionSettings.Port: Integer;
begin
  Result := GetInt('port');
end;

procedure TRdcConnectionSettings.SetPort(aValue: Integer);
begin
  SetInt('port', aValue);
end;

function TRdcConnectionSettings.StartProgram: string;
begin
  Result := GetValue('startProgram');
end;

function TRdcConnectionSettings.WorkingDir: string;
begin
  Result := GetValue('workingDir');
end;

{ TRdcGatewaySettings }

class function TRdcGatewaySettings.XmlName: string;
begin
  Result := 'gatewaySettings';
end;

class function TRdcGatewaySettings.ElementOrder: TArray<string>;
begin
  Result := ['enabled', 'hostName', 'logonMethod', 'localBypass', 'credSharing', 'profileName', 'userName', 'password', 'domain'];
end;

class function TRdcGatewaySettings.ElementDefaults: TArray<string>;
begin
  Result := [cRdcFalse, '', 'Any', cRdcTrue, cRdcTrue, cRdcCustomProfileName, '', '', ''];
end;

procedure TRdcGatewaySettings.FillDefaults;
var
  lProfile: TRdcXmlNode;
begin
  inherited FillDefaults;
  lProfile := Node.FindChild('profileName');
  if (lProfile <> nil) and not lProfile.HasAttribute('scope') then
    lProfile.SetAttribute('scope', cRdcProfileScopeNames[psLocal]);
end;

function TRdcGatewaySettings.Enabled: Boolean;
begin
  Result := GetBool('enabled');
end;

function TRdcGatewaySettings.HostName: string;
begin
  Result := GetValue('hostName');
end;

function TRdcGatewaySettings.LocalBypass: Boolean;
begin
  Result := GetBool('localBypass');
end;

function TRdcGatewaySettings.CredSharing: Boolean;
begin
  Result := GetBool('credSharing');
end;

function TRdcGatewaySettings.LogonMethod: TRdcGatewayLogonMethod;
begin
  Result := TRdcGatewayLogonMethod(RdcTextToEnum(GetValue('logonMethod'), cRdcGatewayLogonMethodNames, Ord(glmAny)));
end;

function TRdcGatewaySettings.UserName: string;
begin
  Result := GetValue('userName');
end;

function TRdcGatewaySettings.Domain: string;
begin
  Result := GetValue('domain');
end;

{ TRdcRemoteDesktopSettings }

class function TRdcRemoteDesktopSettings.XmlName: string;
begin
  Result := 'remoteDesktop';
end;

class function TRdcRemoteDesktopSettings.ElementOrder: TArray<string>;
begin
  Result := ['size', 'sameSizeAsClientArea', 'fullScreen', 'colorDepth'];
end;

class function TRdcRemoteDesktopSettings.ElementDefaults: TArray<string>;
begin
  Result := ['1024 x 768', cRdcFalse, cRdcFalse, '24'];
end;

function ParseSize(const aText: string; out aWidth, aHeight: Integer): Boolean;
var
  lParts: TArray<string>;
begin
  // RDCMan schrijft "1920 x 1080".
  lParts := aText.ToLower.Split(['x']);
  Result := (Length(lParts) = 2) and TryStrToInt(Trim(lParts[0]), aWidth) and TryStrToInt(Trim(lParts[1]), aHeight);
end;

function TRdcRemoteDesktopSettings.Width: Integer;
var
  lHeight: Integer;
begin
  if not ParseSize(GetValue('size'), Result, lHeight) then
    ParseSize(DefaultFor('size'), Result, lHeight);
end;

function TRdcRemoteDesktopSettings.Height: Integer;
var
  lWidth: Integer;
begin
  if not ParseSize(GetValue('size'), lWidth, Result) then
    ParseSize(DefaultFor('size'), lWidth, Result);
end;

procedure TRdcRemoteDesktopSettings.SetSize(aWidth, aHeight: Integer);
begin
  SetValue('size', Format('%d x %d', [aWidth, aHeight]));
end;

function TRdcRemoteDesktopSettings.GetColorDepth: Integer;
begin
  Result := GetInt('colorDepth');
end;

function TRdcRemoteDesktopSettings.GetFullScreen: Boolean;
begin
  Result := GetBool('fullScreen');
end;

function TRdcRemoteDesktopSettings.GetSameSizeAsClientArea: Boolean;
begin
  Result := GetBool('sameSizeAsClientArea');
end;

procedure TRdcRemoteDesktopSettings.SetColorDepth(aValue: Integer);
begin
  SetInt('colorDepth', aValue);
end;

procedure TRdcRemoteDesktopSettings.SetFullScreen(aValue: Boolean);
begin
  SetBool('fullScreen', aValue);
end;

procedure TRdcRemoteDesktopSettings.SetSameSizeAsClientArea(aValue: Boolean);
begin
  SetBool('sameSizeAsClientArea', aValue);
end;

{ TRdcLocalResources }

class function TRdcLocalResources.XmlName: string;
begin
  Result := 'localResources';
end;

class function TRdcLocalResources.ElementOrder: TArray<string>;
begin
  Result := ['audioRedirection', 'audioRedirectionQuality', 'audioCaptureRedirection', 'keyboardHook', 'redirectClipboard', 'redirectDrives', 'redirectDrivesList', 'redirectPrinters', 'redirectPorts', 'redirectSmartCards', 'redirectPnpDevices'];
end;

class function TRdcLocalResources.ElementDefaults: TArray<string>;
begin
  Result := ['Client', 'Dynamic', 'DoNotRecord', 'FullScreenClient', cRdcTrue, cRdcFalse, '', cRdcFalse, cRdcFalse, cRdcTrue, cRdcFalse];
end;

function TRdcLocalResources.AudioRedirection: TRdcAudioRedirection;
begin
  Result := TRdcAudioRedirection(RdcTextToEnum(GetValue('audioRedirection'), cRdcAudioRedirectionNames, Ord(arClient)));
end;

function TRdcLocalResources.AudioQuality: TRdcAudioQuality;
begin
  Result := TRdcAudioQuality(RdcTextToEnum(GetValue('audioRedirectionQuality'), cRdcAudioQualityNames, Ord(aqDynamic)));
end;

function TRdcLocalResources.AudioCapture: TRdcAudioCapture;
begin
  Result := TRdcAudioCapture(RdcTextToEnum(GetValue('audioCaptureRedirection'), cRdcAudioCaptureNames, Ord(acDoNotRecord)));
end;

function TRdcLocalResources.KeyboardHook: TRdcKeyboardHook;
begin
  Result := TRdcKeyboardHook(RdcTextToEnum(GetValue('keyboardHook'), cRdcKeyboardHookNames, Ord(khFullScreenClient)));
end;

function TRdcLocalResources.RedirectClipboard: Boolean;
begin
  Result := GetBool('redirectClipboard');
end;

function TRdcLocalResources.RedirectDrives: Boolean;
begin
  Result := GetBool('redirectDrives');
end;

function TRdcLocalResources.RedirectPrinters: Boolean;
begin
  Result := GetBool('redirectPrinters');
end;

function TRdcLocalResources.RedirectPorts: Boolean;
begin
  Result := GetBool('redirectPorts');
end;

function TRdcLocalResources.RedirectSmartCards: Boolean;
begin
  Result := GetBool('redirectSmartCards');
end;

function TRdcLocalResources.RedirectPnpDevices: Boolean;
begin
  Result := GetBool('redirectPnpDevices');
end;

{ TRdcSecuritySettings }

class function TRdcSecuritySettings.XmlName: string;
begin
  Result := 'securitySettings';
end;

class function TRdcSecuritySettings.ElementOrder: TArray<string>;
begin
  Result := ['authentication'];
end;

class function TRdcSecuritySettings.ElementDefaults: TArray<string>;
begin
  Result := ['Warn'];
end;

function TRdcSecuritySettings.Authentication: TRdcAuthentication;
begin
  Result := TRdcAuthentication(RdcTextToEnum(GetValue('authentication'), cRdcAuthenticationNames, Ord(auWarn)));
end;

procedure TRdcSecuritySettings.SetAuthentication(aValue: TRdcAuthentication);
begin
  SetValue('authentication', cRdcAuthenticationNames[aValue]);
end;

{ TRdcDisplaySettings }

class function TRdcDisplaySettings.XmlName: string;
begin
  Result := 'displaySettings';
end;

class function TRdcDisplaySettings.ElementOrder: TArray<string>;
begin
  Result := ['liveThumbnailUpdates', 'allowThumbnailSessionInteraction', 'showDisconnectedThumbnails', 'thumbnailScale', 'smartSizeDockedWindows', 'smartSizeUndockedWindows'];
end;

class function TRdcDisplaySettings.ElementDefaults: TArray<string>;
begin
  Result := [cRdcTrue, cRdcFalse, cRdcTrue, '1', 'None', 'None'];
end;

function TRdcDisplaySettings.LiveThumbnailUpdates: Boolean;
begin
  Result := GetBool('liveThumbnailUpdates');
end;

function TRdcDisplaySettings.AllowThumbnailSessionInteraction: Boolean;
begin
  Result := GetBool('allowThumbnailSessionInteraction');
end;

function TRdcDisplaySettings.ShowDisconnectedThumbnails: Boolean;
begin
  Result := GetBool('showDisconnectedThumbnails');
end;

function TRdcDisplaySettings.ThumbnailScale: Integer;
begin
  Result := GetInt('thumbnailScale');
end;

function TRdcDisplaySettings.SmartSizeDockedWindows: TRdcSmartSize;
begin
  Result := TRdcSmartSize(RdcTextToEnum(GetValue('smartSizeDockedWindows'), cRdcSmartSizeNames, Ord(ssNone)));
end;

function TRdcDisplaySettings.SmartSizeUndockedWindows: TRdcSmartSize;
begin
  Result := TRdcSmartSize(RdcTextToEnum(GetValue('smartSizeUndockedWindows'), cRdcSmartSizeNames, Ord(ssNone)));
end;

{ TRdcEncryptionSettings }

class function TRdcEncryptionSettings.XmlName: string;
begin
  Result := 'encryptionSettings';
end;

class function TRdcEncryptionSettings.ElementOrder: TArray<string>;
begin
  Result := ['encryptionMethod', 'credentialName', 'credentialData'];
end;

class function TRdcEncryptionSettings.ElementDefaults: TArray<string>;
begin
  Result := ['LogonCredentials', '', ''];
end;

function TRdcEncryptionSettings.EncryptionMethod: TRdcEncryptionMethod;
begin
  Result := TRdcEncryptionMethod(RdcTextToEnum(GetValue('encryptionMethod'), cRdcEncryptionMethodNames, Ord(emLogonCredentials)));
end;

{ TRdcxSettings }

class function TRdcxSettings.XmlName: string;
begin
  Result := 'rdcmx';
end;

class function TRdcxSettings.ElementOrder: TArray<string>;
begin
  Result := ['displayMode', 'resizeDebounceMs', 'reconnectOnResizeFallback', 'desktopScale'];
end;

class function TRdcxSettings.ElementDefaults: TArray<string>;
begin
  Result := ['Dynamic', '400', cRdcTrue, '0'];
end;

class function TRdcxSettings.InRdg: Boolean;
begin
  Result := False;
end;

function TRdcxSettings.GetDesktopScale: Integer;
begin
  Result := GetInt('desktopScale');
  if (Result <> 0) and ((Result < 100) or (Result > 500)) then
    Result := 0;
end;

procedure TRdcxSettings.SetDesktopScale(aValue: Integer);
begin
  SetInt('desktopScale', aValue);
end;

function TRdcxSettings.GetDisplayMode: TRdcDisplayMode;
begin
  Result := TRdcDisplayMode(RdcTextToEnum(GetValue('displayMode'), cRdcDisplayModeNames, Ord(dmDynamic)));
end;

procedure TRdcxSettings.SetDisplayMode(aValue: TRdcDisplayMode);
begin
  SetValue('displayMode', cRdcDisplayModeNames[aValue]);
end;

function TRdcxSettings.GetResizeDebounceMs: Integer;
begin
  Result := GetInt('resizeDebounceMs');
end;

procedure TRdcxSettings.SetResizeDebounceMs(aValue: Integer);
begin
  SetInt('resizeDebounceMs', aValue);
end;

function TRdcxSettings.GetReconnectOnResizeFallback: Boolean;
begin
  Result := GetBool('reconnectOnResizeFallback');
end;

procedure TRdcxSettings.SetReconnectOnResizeFallback(aValue: Boolean);
begin
  SetBool('reconnectOnResizeFallback', aValue);
end;

{ TRdcxHostSettings }

class function TRdcxHostSettings.XmlName: string;
begin
  Result := 'rdcmxHost';
end;

class function TRdcxHostSettings.ElementOrder: TArray<string>;
begin
  Result := ['macAddress', 'wolBroadcast', 'wolPort'];
end;

class function TRdcxHostSettings.ElementDefaults: TArray<string>;
begin
  Result := ['', '255.255.255.255', '9'];
end;

class function TRdcxHostSettings.InRdg: Boolean;
begin
  Result := False;
end;

function TRdcxHostSettings.GetMacAddress: string;
begin
  Result := GetValue('macAddress');
end;

function TRdcxHostSettings.GetWolBroadcast: string;
begin
  Result := GetValue('wolBroadcast');
end;

function TRdcxHostSettings.GetWolPort: Integer;
begin
  Result := GetInt('wolPort');
end;

procedure TRdcxHostSettings.SetMacAddress(const aValue: string);
begin
  SetValue('macAddress', aValue);
end;

procedure TRdcxHostSettings.SetWolBroadcast(const aValue: string);
begin
  SetValue('wolBroadcast', aValue);
end;

procedure TRdcxHostSettings.SetWolPort(aValue: Integer);
begin
  SetInt('wolPort', aValue);
end;

{ TRdcxRouteSettings }

class function TRdcxRouteSettings.XmlName: string;
begin
  Result := 'rdcmxRoute';
end;

class function TRdcxRouteSettings.ElementOrder: TArray<string>;
begin
  Result := ['route', 'tailnetId', 'tailnetHost', 'gatewayId', 'ping'];
end;

class function TRdcxRouteSettings.ElementDefaults: TArray<string>;
begin
  Result := ['Direct', '', '', '', cRdcFalse];
end;

function TRdcxRouteSettings.GetPingEnabled: Boolean;
begin
  Result := GetBool('ping');
end;

procedure TRdcxRouteSettings.SetPingEnabled(aValue: Boolean);
begin
  SetBool('ping', aValue);
end;


class function TRdcxRouteSettings.InRdg: Boolean;
begin
  Result := False;
end;

function TRdcxRouteSettings.GetKind: TRdcRouteKind;
begin
  Result := TRdcRouteKind(RdcTextToEnum(GetValue('route'), cRdcRouteKindNames, Ord(rkDirect)));
end;

procedure TRdcxRouteSettings.SetKind(aValue: TRdcRouteKind);
begin
  SetValue('route', cRdcRouteKindNames[aValue]);
end;

function TRdcxRouteSettings.GetTailnetId: string;
begin
  Result := GetValue('tailnetId');
end;

procedure TRdcxRouteSettings.SetTailnetId(const aValue: string);
begin
  SetValue('tailnetId', aValue);
end;

function TRdcxRouteSettings.GetTailnetHost: string;
begin
  Result := GetValue('tailnetHost');
end;

procedure TRdcxRouteSettings.SetTailnetHost(const aValue: string);
begin
  SetValue('tailnetHost', aValue);
end;

function TRdcxRouteSettings.GetGatewayId: string;
begin
  Result := GetValue('gatewayId');
end;

procedure TRdcxRouteSettings.SetGatewayId(const aValue: string);
begin
  SetValue('gatewayId', aValue);
end;

{ TRdcNodeSettings }

constructor TRdcNodeSettings.Create(aInherit: Boolean);
var
  lGroup: TRdcSettingsGroup;
begin
  inherited Create;
  FGroups := TObjectList<TRdcSettingsGroup>.Create(True);
  // Volgorde = volgorde in de .rdg.
  FGroups.Add(TRdcLogonCredentials.Create);
  FGroups.Add(TRdcConnectionSettings.Create);
  FGroups.Add(TRdcGatewaySettings.Create);
  FGroups.Add(TRdcRemoteDesktopSettings.Create);
  FGroups.Add(TRdcLocalResources.Create);
  FGroups.Add(TRdcSecuritySettings.Create);
  FGroups.Add(TRdcDisplaySettings.Create);
  FGroups.Add(TRdcEncryptionSettings.Create);
  FGroups.Add(TRdcxSettings.Create);
  FGroups.Add(TRdcxHostSettings.Create);
  FGroups.Add(TRdcxRouteSettings.Create);
  for lGroup in FGroups do
    lGroup.Inherit := aInherit;
end;

destructor TRdcNodeSettings.Destroy;
begin
  FGroups.Free;
  inherited Destroy;
end;

procedure TRdcNodeSettings.Assign(aSource: TRdcNodeSettings);
var
  lGroup: TRdcSettingsGroup;
begin
  for lGroup in FGroups do
    lGroup.Assign(aSource.Find(TRdcSettingsGroupClass(lGroup.ClassType)));
end;

function TRdcNodeSettings.Find(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
var
  lGroup: TRdcSettingsGroup;
begin
  for lGroup in FGroups do
    if lGroup.ClassType = aClass then
      Exit(lGroup);
  raise EArgumentException.CreateFmt(_('Onbekende instellingsgroep %s'), [aClass.ClassName]);
end;

function TRdcNodeSettings.FindByXmlName(const aXmlName: string): TRdcSettingsGroup;
var
  lGroup: TRdcSettingsGroup;
begin
  for lGroup in FGroups do
    if lGroup.XmlName = aXmlName then
      Exit(lGroup);
  Result := nil;
end;

function TRdcNodeSettings.GetConnection: TRdcConnectionSettings;
begin
  Result := TRdcConnectionSettings(Find(TRdcConnectionSettings));
end;

function TRdcNodeSettings.GetDisplay: TRdcDisplaySettings;
begin
  Result := TRdcDisplaySettings(Find(TRdcDisplaySettings));
end;

function TRdcNodeSettings.GetEncryption: TRdcEncryptionSettings;
begin
  Result := TRdcEncryptionSettings(Find(TRdcEncryptionSettings));
end;

function TRdcNodeSettings.GetExtras: TRdcxSettings;
begin
  Result := TRdcxSettings(Find(TRdcxSettings));
end;

function TRdcNodeSettings.GetGateway: TRdcGatewaySettings;
begin
  Result := TRdcGatewaySettings(Find(TRdcGatewaySettings));
end;

function TRdcNodeSettings.GetHost: TRdcxHostSettings;
begin
  Result := TRdcxHostSettings(Find(TRdcxHostSettings));
end;

function TRdcNodeSettings.GetRoute: TRdcxRouteSettings;
begin
  Result := TRdcxRouteSettings(Find(TRdcxRouteSettings));
end;

function TRdcNodeSettings.GetLocalResources: TRdcLocalResources;
begin
  Result := TRdcLocalResources(Find(TRdcLocalResources));
end;

function TRdcNodeSettings.GetLogon: TRdcLogonCredentials;
begin
  Result := TRdcLogonCredentials(Find(TRdcLogonCredentials));
end;

function TRdcNodeSettings.GetRemoteDesktop: TRdcRemoteDesktopSettings;
begin
  Result := TRdcRemoteDesktopSettings(Find(TRdcRemoteDesktopSettings));
end;

function TRdcNodeSettings.GetSecurity: TRdcSecuritySettings;
begin
  Result := TRdcSecuritySettings(Find(TRdcSecuritySettings));
end;

{ TRdcUnknownElement }

destructor TRdcUnknownElement.Destroy;
begin
  Element.Free;
  inherited Destroy;
end;

{ TRdcNode }

class constructor TRdcNode.CreateClass;
begin
  FAppDefaults := TRdcNodeSettings.Create(False);
end;

class destructor TRdcNode.DestroyClass;
begin
  FreeAndNil(FAppDefaults);
end;

constructor TRdcNode.Create(const aName: string);
begin
  inherited Create;
  FProperties := TRdcXmlNode.Create('properties');
  FElementAttributes := TRdcXmlNode.Create('');
  FSettings := TRdcNodeSettings.Create(True);
  FUnknown := TObjectList<TRdcUnknownElement>.Create(True);
  if aName <> '' then
    SetName(aName);
end;

destructor TRdcNode.Destroy;
begin
  FUnknown.Free;
  FSettings.Free;
  FElementAttributes.Free;
  FProperties.Free;
  inherited Destroy;
end;

procedure TRdcNode.SetProperty(const aName, aValue: string);
begin
  SetChildTextOrdered(FProperties, aName, aValue, PropertyOrder);
end;

function TRdcNode.GetName: string;
begin
  Result := FProperties.ChildText('name');
end;

procedure TRdcNode.SetName(const aValue: string);
begin
  SetProperty('name', aValue);
end;

function TRdcNode.GetComment: string;
begin
  Result := FProperties.ChildText('comment');
end;

procedure TRdcNode.SetComment(const aValue: string);
begin
  if (aValue = '') and (FProperties.FindChild('comment') = nil) then
    Exit;
  SetProperty('comment', aValue);
end;

function TRdcNode.Caption: string;
begin
  Result := Name;
end;

function TRdcNode.GetFile: TRdcFile;
var
  lNode: TRdcNode;
begin
  lNode := Self;
  while lNode.Parent <> nil do
    lNode := lNode.Parent;
  if lNode is TRdcFile then
    Result := TRdcFile(lNode)
  else
    Result := nil;
end;

function TRdcNode.Effective(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
var
  lNode: TRdcNode;
begin
  lNode := Self;
  while lNode <> nil do
  begin
    Result := lNode.Settings.Find(aClass);
    if not Result.Inherit then
      Exit;
    lNode := lNode.Parent;
  end;
  Result := FAppDefaults.Find(aClass);
end;

function TRdcNode.InheritedValue(aClass: TRdcSettingsGroupClass): TRdcSettingsGroup;
begin
  if FParent <> nil then
    Result := FParent.Effective(aClass)
  else
    Result := FAppDefaults.Find(aClass);
end;

function TRdcNode.EffectiveConnection: TRdcConnectionSettings;
begin
  Result := TRdcConnectionSettings(Effective(TRdcConnectionSettings));
end;

function TRdcNode.EffectiveDisplay: TRdcDisplaySettings;
begin
  Result := TRdcDisplaySettings(Effective(TRdcDisplaySettings));
end;

function TRdcNode.EffectiveExtras: TRdcxSettings;
begin
  Result := TRdcxSettings(Effective(TRdcxSettings));
end;

function TRdcNode.EffectiveRoute: TRdcxRouteSettings;
begin
  Result := TRdcxRouteSettings(Effective(TRdcxRouteSettings));
end;

function TRdcNode.EffectiveGateway: TRdcGatewaySettings;
begin
  Result := TRdcGatewaySettings(Effective(TRdcGatewaySettings));
end;

function TRdcNode.EffectiveLocalResources: TRdcLocalResources;
begin
  Result := TRdcLocalResources(Effective(TRdcLocalResources));
end;

function TRdcNode.EffectiveLogon: TRdcLogonCredentials;
begin
  Result := TRdcLogonCredentials(Effective(TRdcLogonCredentials));
end;

function TRdcNode.EffectiveRemoteDesktop: TRdcRemoteDesktopSettings;
begin
  Result := TRdcRemoteDesktopSettings(Effective(TRdcRemoteDesktopSettings));
end;

function TRdcNode.EffectiveSecurity: TRdcSecuritySettings;
begin
  Result := TRdcSecuritySettings(Effective(TRdcSecuritySettings));
end;

function TRdcNode.ResolveLogon(out aDomain, aUserName: string): Boolean;
var
  lFile: TRdcFile;
  lLogon: TRdcLogonCredentials;
  lProfile: TRdcCredentialProfile;
begin
  aDomain := '';
  aUserName := '';
  lLogon := EffectiveLogon;
  if lLogon.IsFileProfile then
  begin
    lFile := RdcFile;
    if lFile <> nil then
      lProfile := lFile.FindProfile(lLogon.ProfileName)
    else
      lProfile := nil;
    if lProfile = nil then
      Exit(False);
    TRdcCredentialsSettings.SplitLogon(lProfile.UserName, lProfile.Domain, aDomain, aUserName);
    Exit(True);
  end;
  if lLogon.IsExternalProfile then
    Exit(False); // globaal RDCMan-profiel buiten het bestand: niet beschikbaar
  TRdcCredentialsSettings.SplitLogon(lLogon.UserName, lLogon.Domain, aDomain, aUserName);
  Result := True;
end;

function TRdcNode.IsDescendantOf(aGroup: TRdcGroup): Boolean;
var
  lNode: TRdcGroup;
begin
  lNode := FParent;
  while lNode <> nil do
  begin
    if lNode = aGroup then
      Exit(True);
    lNode := lNode.Parent;
  end;
  Result := False;
end;

function TRdcNode.PathSegment(aDuplicateSuffix: Boolean): string;
var
  lIndex: Integer;
  lOccurrence: Integer;
  lSibling: TRdcNode;
begin
  Result := Caption;
  if not aDuplicateSuffix or (FParent = nil) then
    Exit;
  lOccurrence := 1;
  for lIndex := 0 to FParent.Count - 1 do
  begin
    lSibling := FParent[lIndex];
    if lSibling = Self then
      Break;
    if SameText(lSibling.Caption, Result) then
      Inc(lOccurrence);
  end;
  if lOccurrence > 1 then
    Result := Result + '#' + IntToStr(lOccurrence);
end;

function TRdcNode.Path(aDuplicateSuffix: Boolean): string;
var
  lNode: TRdcNode;
begin
  Result := PathSegment(aDuplicateSuffix);
  lNode := FParent;
  while lNode <> nil do
  begin
    Result := lNode.PathSegment(aDuplicateSuffix) + '\' + Result;
    lNode := lNode.Parent;
  end;
end;

{ TRdcGroup }

constructor TRdcGroup.Create(const aName: string);
begin
  FChildren := TObjectList<TRdcNode>.Create(True);
  inherited Create(aName);
  // RDCMan schrijft bij een groep altijd <expanded> vóór <name>.
  if aName <> '' then
    SetExpanded(True);
end;

destructor TRdcGroup.Destroy;
begin
  FChildren.Free;
  inherited Destroy;
end;

function TRdcGroup.PropertyOrder: TArray<string>;
begin
  Result := ['expanded', 'name', 'comment']; // ONZEKER: positie van comment
end;

function TRdcGroup.GetExpanded: Boolean;
begin
  Result := RdcTextToBool(Properties.ChildText('expanded'), False);
end;

procedure TRdcGroup.SetExpanded(aValue: Boolean);
begin
  SetProperty('expanded', RdcBoolText(aValue));
end;

function TRdcGroup.Add(aNode: TRdcNode): TRdcNode;
begin
  Insert(FChildren.Count, aNode);
  Result := aNode;
end;

procedure TRdcGroup.Insert(aIndex: Integer; aNode: TRdcNode);
begin
  if aNode.FParent <> nil then
    raise EInvalidOpException.Create(_('Node zit al in een groep; gebruik MoveHere.'));
  FChildren.Insert(aIndex, aNode);
  aNode.FParent := Self;
end;

function TRdcGroup.Extract(aNode: TRdcNode): TRdcNode;
var
  lUnknown: TRdcUnknownElement;
begin
  // Onbekende elementen die aan deze node verankerd waren, schuiven door naar het vorige anker.
  for lUnknown in Unknown do
    if lUnknown.AnchorNode = aNode then
    begin
      if IndexOf(aNode) > 0 then
        lUnknown.AnchorNode := FChildren[IndexOf(aNode) - 1]
      else
      begin
        lUnknown.AnchorNode := nil;
        lUnknown.AnchorName := 'properties';
      end;
    end;
  Result := FChildren.Extract(aNode);
  if Result <> nil then
    Result.FParent := nil;
end;

procedure TRdcGroup.Delete(aNode: TRdcNode);
var
  lFile: TRdcFile;
begin
  lFile := RdcFile;
  if lFile <> nil then
    lFile.NodeRemoved(aNode);
  Extract(aNode).Free;
end;

function TRdcGroup.IndexOf(aNode: TRdcNode): Integer;
begin
  Result := FChildren.IndexOf(aNode);
end;

procedure TRdcGroup.MoveHere(aNode: TRdcNode; aIndex: Integer);
begin
  if (aNode = Self) or ((aNode is TRdcGroup) and IsDescendantOf(TRdcGroup(aNode))) then
    raise EInvalidOpException.Create(_('Een groep kan niet in zichzelf of een eigen subgroep worden geplaatst.'));
  if aNode.FParent <> nil then
    aNode.FParent.Extract(aNode);
  if (aIndex < 0) or (aIndex > FChildren.Count) then
    aIndex := FChildren.Count;
  Insert(aIndex, aNode);
end;

procedure TRdcGroup.CollectServers(aList: TList<TRdcNode>);
var
  lChild: TRdcNode;
begin
  for lChild in FChildren do
    if lChild is TRdcServer then
      aList.Add(lChild)
    else if lChild is TRdcGroup then
      TRdcGroup(lChild).CollectServers(aList);
end;

procedure TRdcGroup.CollectNodes(aList: TList<TRdcNode>);
var
  lChild: TRdcNode;
begin
  for lChild in FChildren do
  begin
    aList.Add(lChild);
    if lChild is TRdcGroup then
      TRdcGroup(lChild).CollectNodes(aList);
  end;
end;

function TRdcGroup.FindChildByCaption(const aCaption: string; aOccurrence: Integer; aPreferServer: Boolean): TRdcNode;
var
  lChild: TRdcNode;
  lFound: Integer;
  lPass: Integer;
begin
  // Eerst het voorkeurstype (server voor het laatste padsegment, groep anders), dan de rest.
  for lPass := 0 to 1 do
  begin
    lFound := 0;
    for lChild in FChildren do
      if ((lChild is TRdcServer) = (aPreferServer xor (lPass = 1))) and SameText(lChild.Caption, aCaption) then
      begin
        Inc(lFound);
        if lFound = aOccurrence then
          Exit(lChild);
      end;
  end;
  Result := nil;
end;

function TRdcGroup.GetChild(aIndex: Integer): TRdcNode;
begin
  Result := FChildren[aIndex];
end;

function TRdcGroup.GetCount: Integer;
begin
  Result := FChildren.Count;
end;

{ TRdcServer }

function TRdcServer.PropertyOrder: TArray<string>;
begin
  Result := ['displayName', 'name', 'comment']; // ONZEKER: positie van comment
end;

function TRdcServer.Caption: string;
begin
  Result := DisplayName;
  if Result = '' then
    Result := Name;
end;

function TRdcServer.GetDisplayName: string;
begin
  Result := Properties.ChildText('displayName');
end;

procedure TRdcServer.SetDisplayName(const aValue: string);
begin
  if aValue = '' then
    Properties.RemoveChild('displayName') // RDCMan laat displayName weg als die leeg is
  else
    SetProperty('displayName', aValue);
end;

{ TRdcNodeRefList }

constructor TRdcNodeRefList.Create;
begin
  inherited Create;
  FItems := TList<TRdcNodeRef>.Create;
  FPresent := True;
end;

destructor TRdcNodeRefList.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TRdcNodeRefList.Add(aNode: TRdcNode);
begin
  AddPath('', aNode);
end;

procedure TRdcNodeRefList.AddPath(const aPath: string; aNode: TRdcNode);
var
  lRef: TRdcNodeRef;
begin
  lRef.Path := aPath;
  lRef.Node := aNode;
  FItems.Add(lRef);
end;

procedure TRdcNodeRefList.Clear;
begin
  FItems.Clear;
end;

function TRdcNodeRefList.Contains(aNode: TRdcNode): Boolean;
var
  lRef: TRdcNodeRef;
begin
  for lRef in FItems do
    if lRef.Node = aNode then
      Exit(True);
  Result := False;
end;

procedure TRdcNodeRefList.Remove(aNode: TRdcNode);
var
  lIndex: Integer;
begin
  for lIndex := FItems.Count - 1 downto 0 do
    if FItems[lIndex].Node = aNode then
      FItems.Delete(lIndex);
end;

function TRdcNodeRefList.CurrentPath(aIndex: Integer): string;
begin
  if FItems[aIndex].Node <> nil then
    Result := FItems[aIndex].Node.Path(False)
  else
    Result := FItems[aIndex].Path;
end;

function TRdcNodeRefList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TRdcNodeRefList.GetItem(aIndex: Integer): TRdcNodeRef;
begin
  Result := FItems[aIndex];
end;

{ TRdcTailnetDef }

constructor TRdcTailnetDef.Create;
begin
  inherited Create;
  Ephemeral := True;
end;

procedure TRdcTailnetDef.Assign(aSource: TRdcTailnetDef);
begin
  Id := aSource.Id;
  Name := aSource.Name;
  NodeHostName := aSource.NodeHostName;
  Ephemeral := aSource.Ephemeral;
  ControlUrl := aSource.ControlUrl;
  LocalAddress := aSource.LocalAddress;
end;

{ TRdcGatewayDef }

constructor TRdcGatewayDef.Create;
begin
  inherited Create;
  Usage := guAlways;
  CredsMode := gcmSession;
  AuthMethod := glmNTLM;
end;

procedure TRdcGatewayDef.Assign(aSource: TRdcGatewayDef);
begin
  Id := aSource.Id;
  Name := aSource.Name;
  HostName := aSource.HostName;
  Port := aSource.Port;
  Usage := aSource.Usage;
  CredsMode := aSource.CredsMode;
  AuthMethod := aSource.AuthMethod;
  UserName := aSource.UserName;
  Domain := aSource.Domain;
  TailnetId := aSource.TailnetId;
end;

function TRdcGatewayDef.Address: string;
begin
  // ONZEKER: de control accepteert host:poort in GatewayHostname (zoals mstsc "gateway:4443").
  if (Port > 0) and (Port <> 443) then
    Result := System.SysUtils.Format('%s:%d', [Trim(HostName), Port])
  else
    Result := Trim(HostName);
end;

{ TRdcFile }

constructor TRdcFile.Create(const aName: string);
begin
  inherited Create(aName);
  FFormat := ffRdg;
  FXmlFormat := TRdcXmlFormat.RdcmanDefault;
  FRootElement := TRdcXmlNode.Create('RDCMan');
  FRootElement.SetAttribute('programVersion', '2.90');
  FRootElement.SetAttribute('schemaVersion', '3');
  FProfiles := TObjectList<TRdcCredentialProfile>.Create(True);
  FFavorites := TRdcNodeRefList.Create;
  FConnected := TRdcNodeRefList.Create;
  FRecentlyUsed := TRdcNodeRefList.Create;
  FRootUnknown := TObjectList<TRdcUnknownElement>.Create(True);
  FSidecarOrphans := TDictionary<string, string>.Create;
  FTailnets := TObjectList<TRdcTailnetDef>.Create(True);
  FGateways := TObjectList<TRdcGatewayDef>.Create(True);
  FWarnings := TStringList.Create;
end;

destructor TRdcFile.Destroy;
begin
  FWarnings.Free;
  FGateways.Free;
  FTailnets.Free;
  FSidecarOrphans.Free;
  FRootUnknown.Free;
  FRecentlyUsed.Free;
  FConnected.Free;
  FFavorites.Free;
  FProfilesElement.Free;
  FProfiles.Free;
  FRootElement.Free;
  inherited Destroy;
end;

function TRdcFile.FindTailnet(const aId: string): TRdcTailnetDef;
var
  lTailnet: TRdcTailnetDef;
begin
  for lTailnet in FTailnets do
    if SameText(lTailnet.Id, aId) then
      Exit(lTailnet);
  Result := nil;
end;

function TRdcFile.FindGateway(const aId: string): TRdcGatewayDef;
var
  lGateway: TRdcGatewayDef;
begin
  for lGateway in FGateways do
    if SameText(lGateway.Id, aId) then
      Exit(lGateway);
  Result := nil;
end;

function TRdcFile.TailnetUsageCount(const aId: string): Integer;
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := 0;
  lNodes := TList<TRdcNode>.Create;
  try
    lNodes.Add(Self);
    CollectNodes(lNodes);
    for lNode in lNodes do
      if not lNode.Settings.Route.Inherit and (lNode.Settings.Route.Kind = rkTailscale) and SameText(lNode.Settings.Route.TailnetId, aId) then
        Inc(Result);
  finally
    lNodes.Free;
  end;
end;

function TRdcFile.GatewayUsageCount(const aId: string): Integer;
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := 0;
  lNodes := TList<TRdcNode>.Create;
  try
    lNodes.Add(Self);
    CollectNodes(lNodes);
    for lNode in lNodes do
      if not lNode.Settings.Route.Inherit and (lNode.Settings.Route.Kind = rkGateway) and SameText(lNode.Settings.Route.GatewayId, aId) then
        Inc(Result);
  finally
    lNodes.Free;
  end;
end;

function TRdcFile.FindProfile(const aProfileName: string): TRdcCredentialProfile;
var
  lProfile: TRdcCredentialProfile;
begin
  for lProfile in FProfiles do
    if SameText(lProfile.ProfileName, aProfileName) then
      Exit(lProfile);
  Result := nil;
end;

function TRdcFile.AddProfile(const aProfileName, aUserName, aDomain: string): TRdcCredentialProfile;
begin
  Result := TRdcCredentialProfile.Create;
  try
    Result.Inherit := False;
    Result.Node.SetAttribute('inherit', cRdcInheritNone);
    Result.FillDefaults;
    Result.ProfileName := aProfileName;
    Result.UserName := aUserName;
    Result.Domain := aDomain;
  except
    Result.Free;
    raise;
  end;
  FProfiles.Add(Result);
end;

function ProfileReference(aSection: TRdcSettingsGroup; const aProfileName: string): TRdcXmlNode;
begin
  // Logon- en gateway-secties verwijzen met <profileName scope="File">naam</profileName> naar een bestandsprofiel.
  if aSection.Inherit then
    Exit(nil);
  Result := aSection.Node.FindChild('profileName');
  if (Result <> nil) and not (SameText(Result.GetAttribute('scope'), cRdcProfileScopeNames[psFile]) and SameText(Result.Text, aProfileName)) then
    Result := nil;
end;

function TRdcFile.ProfileUsageCount(const aProfileName: string): Integer;
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := 0;
  lNodes := TList<TRdcNode>.Create;
  try
    lNodes.Add(Self);
    CollectNodes(lNodes);
    for lNode in lNodes do
    begin
      if ProfileReference(lNode.Settings.Logon, aProfileName) <> nil then
        Inc(Result);
      if ProfileReference(lNode.Settings.Gateway, aProfileName) <> nil then
        Inc(Result);
    end;
  finally
    lNodes.Free;
  end;
end;

procedure TRdcFile.RenameProfileReferences(const aOldName, aNewName: string);
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
  lReference: TRdcXmlNode;
begin
  lNodes := TList<TRdcNode>.Create;
  try
    lNodes.Add(Self);
    CollectNodes(lNodes);
    for lNode in lNodes do
    begin
      lReference := ProfileReference(lNode.Settings.Logon, aOldName);
      if lReference <> nil then
        lReference.Text := aNewName;
      lReference := ProfileReference(lNode.Settings.Gateway, aOldName);
      if lReference <> nil then
        lReference.Text := aNewName;
    end;
  finally
    lNodes.Free;
  end;
end;

function TRdcFile.FindByPath(const aPath: string): TRdcNode;
var
  lCaption: string;
  lGroup: TRdcGroup;
  lHash: Integer;
  lIndex: Integer;
  lNode: TRdcNode;
  lOccurrence: Integer;
  lSegments: TArray<string>;
begin
  Result := nil;
  lSegments := aPath.Split(['\']);
  if (Length(lSegments) = 0) or not SameText(lSegments[0], Caption) then
    Exit;
  lNode := Self;
  for lIndex := 1 to High(lSegments) do
  begin
    if not (lNode is TRdcGroup) then
      Exit(nil);
    lGroup := TRdcGroup(lNode);
    lCaption := lSegments[lIndex];
    lOccurrence := 1;
    // #n-suffix (sidecar) alleen als er daadwerkelijk zo'n n-de exemplaar bestaat.
    lHash := LastDelimiter('#', lCaption);
    if (lHash > 1) and TryStrToInt(Copy(lCaption, lHash + 1, MaxInt), lOccurrence) and (lOccurrence > 1) and (lGroup.FindChildByCaption(Copy(lCaption, 1, lHash - 1), lOccurrence, lIndex = High(lSegments)) <> nil) then
      lCaption := Copy(lCaption, 1, lHash - 1)
    else
      lOccurrence := 1;
    lNode := lGroup.FindChildByCaption(lCaption, lOccurrence, lIndex = High(lSegments));
    if lNode = nil then
      Exit(nil);
  end;
  Result := lNode;
end;

procedure TRdcFile.NodeRemoved(aNode: TRdcNode);
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  lNodes := TList<TRdcNode>.Create;
  try
    lNodes.Add(aNode);
    if aNode is TRdcGroup then
      TRdcGroup(aNode).CollectNodes(lNodes);
    for lNode in lNodes do
    begin
      FFavorites.Remove(lNode);
      FConnected.Remove(lNode);
      FRecentlyUsed.Remove(lNode);
    end;
  finally
    lNodes.Free;
  end;
end;

end.
