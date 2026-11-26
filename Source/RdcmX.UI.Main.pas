unit RdcmX.UI.Main;

{
  Hoofdvenster: links de boom (bestanden > groepen > servers), rechts een tabstrook met de open sessies en
  daaronder het sessiegebied.

  - De boom is voor navigeren en verbinden: dubbelklik/Enter verbindt (of activeert de tab als de sessie al
    open is). Een enkele klik in de boom verandert de zichtbare sessie niet. De boom is alfabetisch gesorteerd
    (groepen eerst); dat is alleen weergave, de volgorde in het bestand blijft ongewijzigd.
  - Elke open sessie heeft een tab; de actieve tab bepaalt welke sessie zichtbaar is. Na verbreken of een fout
    blijft de tab staan met de melding; sluiten met middelklik of het contextmenu van de tab.
  - Het sessiegebied (pnlSession) is een raster van 1..6 kolommen x 1..3 rijen met versleepbare splitters,
    elk vak met eigen tabs: RdcmX.UI.SessionPanes (Beeld: snelle keuzes, Aangepast..., Gelijk verdelen). De hosts blijven altijd kind van pnlSession en krijgen alleen een positie.
  - Vensterpositie/-grootte, gemaximaliseerd en boombreedte worden per monitorconfiguratie onthouden.
  - Het hoofdmenu staat niet over de volle breedte (Form.Menu is leeg) maar als werkbalk-menu (tbMenu.Menu =
    mmMain) boven de boom; zo begint het sessiegebied direct onder de titelbalk.

  Sneltoetsen werken alleen als de boom de focus heeft (HandleTreeKey) en staan bewust niet als ShortCut op
  de acties: VCL-sneltoetsen zouden anders ook toetsaanslagen in de remote sessie afvangen. De toets staat
  wel in het menu-opschrift (na een tab) als hint.

  Codeerregel: event-handlers en action-executes bevatten geen logica, ze roepen een benoemde methode aan.
}

interface

uses
  Winapi.CommCtrl, Winapi.Messages, Winapi.MultiMon, Winapi.Windows,
  System.Actions, System.Classes, System.DateUtils, System.Generics.Collections, System.ImageList, System.Math, System.StrUtils, System.SysUtils, System.Types, System.UITypes,
  Vcl.ActnList, Vcl.ComCtrls, Vcl.Controls, Vcl.Dialogs, Vcl.ExtCtrls, Vcl.Forms, Vcl.Graphics, Vcl.ImgList, Vcl.Menus, Vcl.StdCtrls, Vcl.WinXCtrls,
  RdcmX.AppSettings, RdcmX.Credentials, RdcmX.Lang, RdcmX.Model, RdcmX.Ping, RdcmX.Rdp.Session, RdcmX.Sessions, RdcmX.Shortcuts, RdcmX.Storage, RdcmX.Tailscale, RdcmX.UI.SessionPanes, RdcmX.UI.SessionWindow, RdcmX.UI.Theme;

type
  TRdcTreeShortcutKind = (tskFavoritesHeader, tskRecentHeader, tskFavorite, tskRecent);

  /// <summary>Data van de boom-nodes onder Favorieten/Recent (gewone nodes hebben een TRdcNode als Data).</summary>
  TRdcTreeShortcut = class
  public
    Kind: TRdcTreeShortcutKind;
    /// <summary>De echte server (nil bij een kopje).</summary>
    Server: TRdcServer;
    /// <summary>Volgorde binnen Recent (0 = nieuwste).</summary>
    Order: Integer;
  end;

  TfrmMain = class(TForm, IRdcSecretAccess)
    mmMain: TMainMenu;
    miFile: TMenuItem;
    miNewFile: TMenuItem;
    miOpen: TMenuItem;
    miRecent: TMenuItem;
    miFileSep1: TMenuItem;
    miSave: TMenuItem;
    miSaveAs: TMenuItem;
    miSaveAll: TMenuItem;
    miFileSep2: TMenuItem;
    miCloseFile: TMenuItem;
    miFileSepProfiles: TMenuItem;
    miProfiles: TMenuItem;
    miTailnets: TMenuItem;
    miGateways: TMenuItem;
    miFileSep3: TMenuItem;
    miExit: TMenuItem;
    miServer: TMenuItem;
    miConnect: TMenuItem;
    miDisconnect: TMenuItem;
    miConnectGroup: TMenuItem;
    miDisconnectGroup: TMenuItem;
    miWakeOnLan: TMenuItem;
    miFavorite: TMenuItem;
    miForgetPassword: TMenuItem;
    miOptions: TMenuItem;
    miSep1: TMenuItem;
    miNewServer: TMenuItem;
    miNewGroup: TMenuItem;
    miSep2: TMenuItem;
    miRename: TMenuItem;
    miDelete: TMenuItem;
    miSep3: TMenuItem;
    miProperties: TMenuItem;
    miView: TMenuItem;
    miHelp: TMenuItem;
    miHelpManual: TMenuItem;
    miGrid11: TMenuItem;
    miGrid21: TMenuItem;
    miGrid31: TMenuItem;
    miGrid41: TMenuItem;
    miGrid12: TMenuItem;
    miGrid22: TMenuItem;
    miGrid32: TMenuItem;
    miGrid42: TMenuItem;
    miGridCustom: TMenuItem;
    miGridSep: TMenuItem;
    miGridEqualize: TMenuItem;
    miViewSep1: TMenuItem;
    miTheme: TMenuItem;
    miThemeSystem: TMenuItem;
    miThemeLight: TMenuItem;
    miThemeDark: TMenuItem;
    alMain: TActionList;
    actConnect: TAction;
    actDisconnect: TAction;
    actNewServer: TAction;
    actNewGroup: TAction;
    actRename: TAction;
    actDelete: TAction;
    actProperties: TAction;
    actExit: TAction;
    actNewFile: TAction;
    actOpen: TAction;
    actSave: TAction;
    actSaveAs: TAction;
    actSaveAll: TAction;
    actCloseFile: TAction;
    actProfiles: TAction;
    actTailnets: TAction;
    actGateways: TAction;
    actWakeOnLan: TAction;
    actFavorite: TAction;
    actForgetPassword: TAction;
    actLockVault: TAction;
    actChangeMasterPassword: TAction;
    actConnectGroup: TAction;
    actTabDetach: TAction;
    actTabFullScreen: TAction;
    actTabDock: TAction;
    actDisconnectGroup: TAction;
    actOptions: TAction;
    actHelpManual: TAction;
    actGrid11: TAction;
    actGrid21: TAction;
    actGrid31: TAction;
    actGrid41: TAction;
    actGrid12: TAction;
    actGrid22: TAction;
    actGrid32: TAction;
    actGrid42: TAction;
    actGridCustom: TAction;
    actGridEqualize: TAction;
    actThemeSystem: TAction;
    actThemeLight: TAction;
    actThemeDark: TAction;
    actTabMoveToOtherPane: TAction;
    dlgOpen: TOpenDialog;
    dlgSave: TSaveDialog;
    actTabReconnect: TAction;
    actTabDisconnect: TAction;
    actTabClose: TAction;
    pmTree: TPopupMenu;
    pmiConnect: TMenuItem;
    pmiDisconnect: TMenuItem;
    pmiConnectGroup: TMenuItem;
    pmiDisconnectGroup: TMenuItem;
    pmiWakeOnLan: TMenuItem;
    pmiFavorite: TMenuItem;
    pmiForgetPassword: TMenuItem;
    pmiSep1: TMenuItem;
    pmiNewServer: TMenuItem;
    pmiNewGroup: TMenuItem;
    pmiSep2: TMenuItem;
    pmiRename: TMenuItem;
    pmiDelete: TMenuItem;
    pmiSep3: TMenuItem;
    pmiProperties: TMenuItem;
    pmTabs: TPopupMenu;
    pmtReconnect: TMenuItem;
    pmtDisconnect: TMenuItem;
    pmtSep1: TMenuItem;
    pmtMoveToOtherPane: TMenuItem;
    pmtDetach: TMenuItem;
    pmtFullScreen: TMenuItem;
    pmtDock: TMenuItem;
    pmtScale: TMenuItem;
    pmtScaleAuto: TMenuItem;
    pmtScale100: TMenuItem;
    pmtScale125: TMenuItem;
    pmtScale150: TMenuItem;
    pmtScale175: TMenuItem;
    pmtScale200: TMenuItem;
    pmtScale250: TMenuItem;
    pmtScale300: TMenuItem;
    pmtSep2: TMenuItem;
    pmtClose: TMenuItem;
    ilNodes: TImageList;
    sbStatus: TStatusBar;
    pnlLeft: TPanel;
    tbMenu: TToolBar;
    sbSearch: TSearchBox;
    tvServers: TTreeView;
    splTree: TSplitter;
    pnlRight: TPanel;
    pnlSession: TPanel;
    lblPlaceholder: TLabel;
    tmrClose: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
    procedure alMainUpdate(Action: TBasicAction; var Handled: Boolean);
    procedure actConnectExecute(Sender: TObject);
    procedure actDisconnectExecute(Sender: TObject);
    procedure actNewServerExecute(Sender: TObject);
    procedure actNewGroupExecute(Sender: TObject);
    procedure actRenameExecute(Sender: TObject);
    procedure actDeleteExecute(Sender: TObject);
    procedure actPropertiesExecute(Sender: TObject);
    procedure actExitExecute(Sender: TObject);
    procedure actNewFileExecute(Sender: TObject);
    procedure actOpenExecute(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
    procedure actSaveAsExecute(Sender: TObject);
    procedure actSaveAllExecute(Sender: TObject);
    procedure actCloseFileExecute(Sender: TObject);
    procedure actProfilesExecute(Sender: TObject);
    procedure actTailnetsExecute(Sender: TObject);
    procedure actGatewaysExecute(Sender: TObject);
    procedure actWakeOnLanExecute(Sender: TObject);
    procedure actFavoriteExecute(Sender: TObject);
    procedure actForgetPasswordExecute(Sender: TObject);
    procedure actLockVaultExecute(Sender: TObject);
    procedure actChangeMasterPasswordExecute(Sender: TObject);
    procedure actConnectGroupExecute(Sender: TObject);
    procedure actTabDetachExecute(Sender: TObject);
    procedure actTabFullScreenExecute(Sender: TObject);
    procedure actTabDockExecute(Sender: TObject);
    procedure pmtScaleItemClick(Sender: TObject);
    procedure pmTabsPopup(Sender: TObject);
    procedure actDisconnectGroupExecute(Sender: TObject);
    procedure actOptionsExecute(Sender: TObject);
    procedure actHelpManualExecute(Sender: TObject);
    procedure actTabReconnectExecute(Sender: TObject);
    procedure actTabDisconnectExecute(Sender: TObject);
    procedure actTabCloseExecute(Sender: TObject);
    procedure actTabMoveToOtherPaneExecute(Sender: TObject);
    procedure actGridPresetExecute(Sender: TObject);
    procedure actGridCustomExecute(Sender: TObject);
    procedure actGridEqualizeExecute(Sender: TObject);
    procedure actThemeSystemExecute(Sender: TObject);
    procedure actThemeLightExecute(Sender: TObject);
    procedure actThemeDarkExecute(Sender: TObject);
    procedure tvServersCompare(Sender: TObject; Node1, Node2: TTreeNode; Data: Integer; var Compare: Integer);
    procedure tvServersExpanded(Sender: TObject; Node: TTreeNode);
    procedure tvServersCollapsed(Sender: TObject; Node: TTreeNode);
    procedure tvServersDblClick(Sender: TObject);
    procedure tvServersMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure tvServersChange(Sender: TObject; Node: TTreeNode);
    procedure tvServersKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tvServersMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure tvServersDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
    procedure tvServersDragDrop(Sender, Source: TObject; X, Y: Integer);
    procedure tvServersEditing(Sender: TObject; Node: TTreeNode; var AllowEdit: Boolean);
    procedure tvServersEdited(Sender: TObject; Node: TTreeNode; var S: string);
    procedure tvServersCancelEdit(Sender: TObject; Node: TTreeNode);
    procedure tvServersContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure sbStatusResize(Sender: TObject);
    procedure sbSearchChange(Sender: TObject);
    procedure sbSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure tmrCloseTimer(Sender: TObject);
  protected
    procedure DoCreate; override;
  private
    FAppSettings: TRdcAppSettings;
    FClosing: Boolean;
    FFiles: TObjectList<TRdcFile>;
    FFilesConfirmed: Boolean;
    FFilter: string;
    // Groep verbinden: één keer aanmeldgegevens vragen voor alle servers (wachtwoord alleen tijdens het verbinden).
    FSessionWindows: TDictionary<TRdcServer, TfrmSessionWindow>;
    FAutoSaveTimer: TTimer;
    FBatchActive: Boolean;
    FBatchUserName: string;
    FBatchDomain: string;
    FBatchPassword: string;
    FBatchRemember: Boolean;
    // Onthouden wachtwoorden (Windows Referentiebeheer): welk opgeslagen wachtwoord een verbinding gebruikte, zodat
    // een door de server geweigerd wachtwoord automatisch vergeten wordt.
    FStoredPasswordUsed: TDictionary<TRdcServer, string>;
    FSelectingFromTree: Boolean; // tab wordt geactiveerd vanuit de boom: geen focus naar de sessie, boom niet terugzetten
    FVault: TRdcPasswordVault;
    FTailnetManager: TRdcTailnetManager;
    // Bereikbaarheid (ping op de achtergrond): status per doel (host:poort), en de huidige doelen.
    FPinger: TRdcPinger;
    FPingStates: TDictionary<string, TRdcPingResult>;
    FPingSince: TDictionary<string, TDateTime>;
    FPingTargetKeys: string;
    FPingLastSeen: TDictionary<string, TDateTime>;  // laatste keer bereikbaar (deze sessie)
    FPingChecked: TDictionary<string, TDateTime>;   // laatste controle
    FHintTreeNode: TTreeNode;
    FVaultTimer: TTimer;
    FShortcuts: TRdcClientShortcuts;
    FShortcutData: TObjectList<TRdcTreeShortcut>;
    FFavoritesHeader: TTreeNode;
    FRecentHeader: TTreeNode;
    FFavoritesCollapsed: Boolean;
    FRecentCollapsed: Boolean;
    FCollapsedFiles: TList<TRdcFile>; // bestanden waarvan de hoofdknoop ingeklapt is (bij starten: alle)
    FForceClose: Boolean;
    FPanes: TRdcSessionPanes;
    FRenaming: Boolean;
    FRestoredTreeWidth: Integer;
    FSessions: TRdcSessionManager;
    FShown: Boolean;
    FTreeNodes: TDictionary<TRdcNode, TTreeNode>;
    // Formulier
    procedure InitializeForm;
    procedure FinalizeForm;
    procedure FormShown;
    procedure HandleDpiChanged;
    function CanCloseApplication: Boolean;
    procedure ForceCloseAfterTimeout;
    procedure HideWhileDisconnecting;
    procedure OpenStartupFiles;
    procedure CollapseAllFiles;
    procedure ShowManual;
    procedure UpdatePingTargets;
    procedure PingResultsArrived(const aResults: TArray<TRdcPingResult>);
    function PingKeyOf(aServer: TRdcServer; out aKey: string): Boolean;
    function PingStateOf(aServer: TRdcServer): TRdcPingState;
    procedure ShowPingStatusOfSelected;
    procedure UpdateTreeHint(X, Y: Integer);
    function TreeNodeHint(aTreeNode: TTreeNode): string;
    function ServerHint(aServer: TRdcServer): string;
    // Layout
    function MonitorConfigKey: string;
    procedure RestoreWindowLayout;
    procedure StoreWindowLayout;
    function CurrentRectInWorkspace(var aRect: TRect): Boolean;
    procedure RestoreTreeWidth;
    // Boom
    function AddTreeNode(aParent: TTreeNode; aNode: TRdcNode): TTreeNode;
    procedure BuildTree;
    function CompareTreeNodes(aNode1, aNode2: TTreeNode): Integer;
    procedure ApplyTreeFilter;
    // Favorieten en Recent (bovenaan de boom)
    function AddShortcutSection(aHeaderKind: TRdcTreeShortcutKind; const aCaption: string; aImageIndex: Integer; const aServers: TArray<TRdcServer>; aItemKind: TRdcTreeShortcutKind; aCollapsed: Boolean): TTreeNode;
    function NewShortcutData(aKind: TRdcTreeShortcutKind; aServer: TRdcServer; aOrder: Integer): TRdcTreeShortcut;
    function NodeOfTreeNode(aTreeNode: TTreeNode): TRdcNode;
    procedure RebuildShortcutNodes;
    procedure RemoveSelectedShortcut;
    function SelectedShortcut: TRdcTreeShortcut;
    function ShortcutCaption(aServer: TRdcServer): string;
    function ShortcutOf(aTreeNode: TTreeNode): TRdcTreeShortcut;
    procedure StoreShortcuts;
    procedure ToggleFavoriteSelected;
    procedure UpdateShortcutImages(aNode: TRdcNode);
    procedure RefreshAfterRename;
    procedure ShowOptions;
    procedure AnnounceLanguageChange(aLanguage: TRdcLanguage);
    procedure FocusSearch;
    function HandleSearchKey(aKey: Word): Boolean;
    function NodeMatchesFilter(aNode: TRdcNode): Boolean;
    function HandleTreeKey(aKey: Word; aShift: TShiftState): Boolean;
    function NodeImageIndex(aNode: TRdcNode): Integer;
    procedure RebuildImages;
    procedure RemoveTreeMapping(aNode: TRdcNode);
    function SelectedNode: TRdcNode;
    function SelectedServer: TRdcServer;
    procedure SelectNode(aNode: TRdcNode);
    procedure SetGroupExpanded(aTreeNode: TTreeNode; aExpanded: Boolean);
    procedure SortTree;
    function TargetGroup: TRdcGroup;
    procedure UpdateNodeCaption(aNode: TRdcNode);
    procedure UpdateNodeImage(aNode: TRdcNode);
    // Boom: bewerken
    procedure AddNewGroup;
    procedure AddNewServer;
    procedure AddNodeToTree(aGroup: TRdcGroup; aNode: TRdcNode);
    function ApplyRename(aTreeNode: TTreeNode; const aText: string): string;
    procedure DeleteSelectedNode;
    procedure EditSelectedProperties;
    procedure ApplyScaleToOpenSessions(aNode: TRdcNode);
    procedure EditProfilesOfSelectedFile;
    procedure EditTailnetsOfSelectedFile;
    procedure EditGatewaysOfSelectedFile;
    function IdInOtherFile(aFile: TRdcFile; const aId: string): Boolean;
    // IRdcSecretAccess (kluis voor de beheerschermen van Tailscale-netwerken en gateways)
    function CanStoreSecrets: Boolean;
    function HasSecret(const aTarget: string): Boolean;
    function LoadSecret(const aTarget, aReason: string; out aSecret: string): Boolean;
    function SaveSecret(const aTarget, aAccount, aSecret, aReason: string): Boolean;
    procedure DeleteSecret(const aTarget: string);
    procedure DeleteSecretsWithPrefix(const aPrefix: string);
    procedure WakeSelectedServer;
    procedure StartRenameSelected;
    // Boom: slepen
    function CanDropAt(aSource: TObject; X, Y: Integer): Boolean;
    procedure DropSelectedNodeAt(X, Y: Integer);
    function DropTarget(aDragged: TRdcNode; X, Y: Integer; out aTargetGroup: TRdcGroup; out aBefore: TRdcNode): Boolean;
    procedure StartTreeDrag(aButton: TMouseButton; aShift: TShiftState; X, Y: Integer);
    procedure SelectNodeForContextMenu(const aMousePos: TPoint);
    // Bestanden
    procedure AddFile(aFile: TRdcFile);
    function CloseFile(aFile: TRdcFile; aAskSave: Boolean): Boolean;
    procedure CloseSelectedFile;
    function ConfirmSaveFile(aFile: TRdcFile): Boolean;
    function ExternalChangePrompt(aFile: TRdcFile): TRdcExternalChangeAction;
    function FileDisplayText(aFile: TRdcFile): string;
    procedure MarkModified(aNode: TRdcNode);
    procedure AutoSaveTimerFired(Sender: TObject);
    procedure AutoSaveModifiedFiles;
    procedure ScheduleAutoSave;
    procedure NewFile;
    procedure CloseUntouchedNewFiles;
    function OpenFile(const aFileName: string; aQuiet: Boolean = False): TRdcFile;
    procedure OpenFilesWithDialog;
    procedure OpenRecentFile(aIndex: Integer);
    procedure RecentFileClick(Sender: TObject);
    procedure ReloadFile(aFile: TRdcFile);
    procedure SaveAllFiles;
    function SaveFile(aFile: TRdcFile; aSaveAs: Boolean): Boolean;
    procedure SaveSelectedFile(aSaveAs: Boolean);
    function SelectedFile: TRdcFile;
    procedure ShowLoadWarnings(aFile: TRdcFile);
    procedure UpdateFileNodeText(aFile: TRdcFile);
    procedure UpdateRecentMenu;
    // Sessies en tabs
    procedure ActivateServerTab(aServer: TRdcServer);
    procedure ActiveTabChanged;
    function ActiveServer: TRdcServer;
    procedure CloseServerTab(aServer: TRdcServer);
    procedure CloseTabServer;
    procedure ConnectNodeAtCursor;
    procedure ConnectSelectedServer;
    procedure ConnectServer(aServer: TRdcServer);
    procedure ConnectSelectedGroup;
    // Onthouden wachtwoorden
    function CredentialTargetFor(aServer: TRdcServer; const aUserName, aDomain: string): string;
    function LoadRememberedPassword(aServer: TRdcServer; const aContext: TRdcCredentialContext; const aUserName, aDomain: string; out aPassword: string): TRdcLoadResult;
    procedure RememberPassword(aServer: TRdcServer; const aContext: TRdcCredentialContext; const aUserName, aDomain, aPassword: string);
    function ConfirmHostApproval(const aAccount: string; const aMissing: TArray<TRdcHostRef>): Boolean;
    function ApproveGroupHosts(const aServers: TArray<TRdcServer>; const aUserName, aDomain: string): Boolean;
    function HasRememberedPassword(aServer: TRdcServer; const aUserName, aDomain: string): Boolean;
    function AccountText(const aUserName, aDomain: string): string;
    // Wachtwoordkluis (hoofdwachtwoord)
    function CreateVault: Boolean;
    function EnsureVaultUnlocked(const aReason: string): Boolean;
    procedure ResetVaultAfterForgotten;
    procedure LockVault;
    procedure ChangeMasterPassword;
    procedure VaultTimerFired(Sender: TObject);
    procedure AutoLockVault;
    procedure UpdateVaultStatus;
    procedure DropLegacyPasswords;
    procedure ForgetSelectedPassword;
    procedure HandleRejectedPassword(aServer: TRdcServer);
    function ConfirmForgetAllPasswords: Boolean;
    function ApplyRememberPasswordsOption(aWanted: Boolean): Boolean;
    // Losmaken (eigen venster / volledig scherm)
    procedure DetachServer(aServer: TRdcServer; aFullScreen: Boolean);
    // Schaal van een open sessie (tab-menu)
    procedure SetTabServerScale(aPercent: Integer);
    procedure UpdateScaleMenu;
    procedure DockServer(aServer: TRdcServer);
    procedure DockAllServers;
    procedure FocusDetachedSession(aServer: TRdcServer);
    function SessionWindowOf(aServer: TRdcServer): TfrmSessionWindow;
    procedure SessionWindowActivated(aSender: TObject; aServer: TRdcServer);
    procedure SessionWindowDockRequest(aSender: TObject; aServer: TRdcServer);
    procedure SessionWindowFullScreenToggle(aSender: TObject; aServer: TRdcServer);
    procedure SessionWindowHostResized(aSender: TObject; aServer: TRdcServer);
    procedure DisconnectSelectedGroup;
    function SelectedGroupServers: TArray<TRdcServer>;
    function CredentialRequest(aServer: TRdcServer; const aContext: TRdcCredentialContext; var aUserName, aDomain: string; out aPassword: string; out aFromVault: Boolean): Boolean;
    procedure TailnetOptions(aDef: TRdcTailnetDef; out aMatchHostName, aAllowShared: Boolean);
    procedure DisconnectSelectedServer;
    procedure ShowTabOfSelectedServer;
    function OpenSessionsCloseQuestion(aActive: Integer): string;
    procedure CloseTabAfterDisconnect(aServer: TRdcServer);
    procedure DisconnectTabServer;
    procedure MoveTabServerToOtherPane;
    procedure PanesActiveChanged(aSender: TObject);
    procedure PanesCloseRequest(aSender: TObject; aServer: TRdcServer);
    procedure PanesLayoutChanged(aSender: TObject);
    procedure PlaceNewHost(aServer: TRdcServer; aHost: TControl);
    procedure ReconnectTabServer;
    procedure RestoreGrid;
    procedure StoreGrid;
    procedure ApplyGridPreset(aPresetTag: Integer);
    procedure ChooseCustomGrid;
    procedure EqualizeGrid;
    procedure SetGrid(aColumns, aRows: Integer);
    procedure UpdateGridActions;
    procedure SessionsActivated(aSender: TObject; aServer: TRdcServer);
    // Thema
    procedure SetTheme(aTheme: TRdcTheme);
    procedure SwitchThemeNowOrLater(aTheme: TRdcTheme; aAnnounce: Boolean);
    procedure SystemThemeChanged;
    procedure WMSettingChange(var aMessage: TWMSettingChange); message WM_SETTINGCHANGE;
    procedure SessionsDisplayChanged(aSender: TObject; aServer: TRdcServer);
    procedure SessionsStateChanged(aSender: TObject; aServer: TRdcServer);
    procedure ShowActiveSession;
    function TabImageFor(aServer: TRdcServer): Integer;
    function TabMenuServer: TRdcServer;
    procedure UpdateActionStates;
    procedure UpdateStatusBar;
    function AppVersionText: string;
    procedure LayoutStatusBar;
    procedure UpdateTabImages;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  Winapi.ShellAPI,
  System.IOUtils,
  RdcmX.Log, RdcmX.UI.CredentialPrompt, RdcmX.UI.Gateways, RdcmX.UI.Icons, RdcmX.UI.MasterPassword, RdcmX.UI.Options, RdcmX.UI.Profiles, RdcmX.UI.Properties, RdcmX.UI.Tailnets, RdcmX.WakeOnLan;

const
  cMinTreeWidth96 = 120;

{ Event-handlers: alleen doorverwijzen }

procedure TfrmMain.DoCreate;
begin
  // Translate the DFM texts before OnCreate. The toolbar menu copies the captions of mmMain into its buttons when
  // the menu is assigned, so assign it again to show the translated captions.
  TranslateComponent(Self);
  tbMenu.Menu := nil;
  tbMenu.Menu := mmMain;
  inherited;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  InitializeForm;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FinalizeForm;
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  FormShown;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  StoreWindowLayout;
end;

procedure TfrmMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := CanCloseApplication;
end;

procedure TfrmMain.FormAfterMonitorDpiChanged(Sender: TObject; OldDPI, NewDPI: Integer);
begin
  HandleDpiChanged;
end;

procedure TfrmMain.tmrCloseTimer(Sender: TObject);
begin
  ForceCloseAfterTimeout;
end;

procedure TfrmMain.alMainUpdate(Action: TBasicAction; var Handled: Boolean);
begin
  UpdateActionStates;
  Handled := True;
end;

procedure TfrmMain.actConnectExecute(Sender: TObject);
begin
  ConnectSelectedServer;
end;

procedure TfrmMain.tvServersMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  UpdateTreeHint(X, Y);
end;

procedure TfrmMain.tvServersChange(Sender: TObject; Node: TTreeNode);
begin
  ShowTabOfSelectedServer;
  ShowPingStatusOfSelected;
end;

procedure TfrmMain.actDisconnectExecute(Sender: TObject);
begin
  DisconnectSelectedServer;
end;

procedure TfrmMain.actNewServerExecute(Sender: TObject);
begin
  AddNewServer;
end;

procedure TfrmMain.actNewGroupExecute(Sender: TObject);
begin
  AddNewGroup;
end;

procedure TfrmMain.actRenameExecute(Sender: TObject);
begin
  StartRenameSelected;
end;

procedure TfrmMain.actDeleteExecute(Sender: TObject);
begin
  DeleteSelectedNode;
end;

procedure TfrmMain.actPropertiesExecute(Sender: TObject);
begin
  EditSelectedProperties;
end;

procedure TfrmMain.actExitExecute(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.actNewFileExecute(Sender: TObject);
begin
  NewFile;
end;

procedure TfrmMain.actOpenExecute(Sender: TObject);
begin
  OpenFilesWithDialog;
end;

procedure TfrmMain.actSaveExecute(Sender: TObject);
begin
  SaveSelectedFile(False);
end;

procedure TfrmMain.actSaveAsExecute(Sender: TObject);
begin
  SaveSelectedFile(True);
end;

procedure TfrmMain.actSaveAllExecute(Sender: TObject);
begin
  SaveAllFiles;
end;

procedure TfrmMain.actCloseFileExecute(Sender: TObject);
begin
  CloseSelectedFile;
end;

procedure TfrmMain.actProfilesExecute(Sender: TObject);
begin
  EditProfilesOfSelectedFile;
end;

procedure TfrmMain.actTailnetsExecute(Sender: TObject);
begin
  EditTailnetsOfSelectedFile;
end;

procedure TfrmMain.actGatewaysExecute(Sender: TObject);
begin
  EditGatewaysOfSelectedFile;
end;

procedure TfrmMain.actWakeOnLanExecute(Sender: TObject);
begin
  WakeSelectedServer;
end;

procedure TfrmMain.actFavoriteExecute(Sender: TObject);
begin
  ToggleFavoriteSelected;
end;

procedure TfrmMain.actLockVaultExecute(Sender: TObject);
begin
  LockVault;
end;

procedure TfrmMain.actChangeMasterPasswordExecute(Sender: TObject);
begin
  ChangeMasterPassword;
end;

procedure TfrmMain.actForgetPasswordExecute(Sender: TObject);
begin
  ForgetSelectedPassword;
end;

procedure TfrmMain.actConnectGroupExecute(Sender: TObject);
begin
  ConnectSelectedGroup;
end;

procedure TfrmMain.actTabDetachExecute(Sender: TObject);
begin
  DetachServer(TabMenuServer, False);
end;

procedure TfrmMain.actTabFullScreenExecute(Sender: TObject);
begin
  DetachServer(TabMenuServer, True);
end;

procedure TfrmMain.actTabDockExecute(Sender: TObject);
begin
  DockServer(TabMenuServer);
end;

procedure TfrmMain.pmtScaleItemClick(Sender: TObject);
begin
  SetTabServerScale(TMenuItem(Sender).Tag);
end;

procedure TfrmMain.pmTabsPopup(Sender: TObject);
begin
  UpdateScaleMenu;
end;

procedure TfrmMain.actDisconnectGroupExecute(Sender: TObject);
begin
  DisconnectSelectedGroup;
end;

procedure TfrmMain.actHelpManualExecute(Sender: TObject);
begin
  ShowManual;
end;

procedure TfrmMain.actOptionsExecute(Sender: TObject);
begin
  ShowOptions;
end;

procedure TfrmMain.actTabReconnectExecute(Sender: TObject);
begin
  ReconnectTabServer;
end;

procedure TfrmMain.actTabDisconnectExecute(Sender: TObject);
begin
  DisconnectTabServer;
end;


procedure TfrmMain.actTabCloseExecute(Sender: TObject);
begin
  CloseTabServer;
end;

procedure TfrmMain.actTabMoveToOtherPaneExecute(Sender: TObject);
begin
  MoveTabServerToOtherPane;
end;

procedure TfrmMain.actGridPresetExecute(Sender: TObject);
begin
  ApplyGridPreset(TAction(Sender).Tag);
end;

procedure TfrmMain.actGridCustomExecute(Sender: TObject);
begin
  ChooseCustomGrid;
end;

procedure TfrmMain.actGridEqualizeExecute(Sender: TObject);
begin
  EqualizeGrid;
end;

procedure TfrmMain.actThemeSystemExecute(Sender: TObject);
begin
  SetTheme(rtSystem);
end;

procedure TfrmMain.actThemeLightExecute(Sender: TObject);
begin
  SetTheme(rtLight);
end;

procedure TfrmMain.actThemeDarkExecute(Sender: TObject);
begin
  SetTheme(rtDark);
end;

procedure TfrmMain.WMSettingChange(var aMessage: TWMSettingChange);
begin
  inherited;
  if (aMessage.Section <> nil) and SameText(aMessage.Section, 'ImmersiveColorSet') then
    SystemThemeChanged;
end;

procedure TfrmMain.tvServersCompare(Sender: TObject; Node1, Node2: TTreeNode; Data: Integer; var Compare: Integer);
begin
  Compare := CompareTreeNodes(Node1, Node2);
end;

procedure TfrmMain.tvServersExpanded(Sender: TObject; Node: TTreeNode);
begin
  SetGroupExpanded(Node, True);
end;

procedure TfrmMain.tvServersCollapsed(Sender: TObject; Node: TTreeNode);
begin
  SetGroupExpanded(Node, False);
end;

procedure TfrmMain.tvServersDblClick(Sender: TObject);
begin
  ConnectNodeAtCursor;
end;

procedure TfrmMain.tvServersKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if HandleTreeKey(Key, Shift) then
    Key := 0;
end;

procedure TfrmMain.tvServersMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  StartTreeDrag(Button, Shift, X, Y);
end;

procedure TfrmMain.tvServersContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
begin
  SelectNodeForContextMenu(MousePos);
end;

procedure TfrmMain.sbStatusResize(Sender: TObject);
begin
  LayoutStatusBar;
end;

procedure TfrmMain.sbSearchChange(Sender: TObject);
begin
  ApplyTreeFilter;
end;

procedure TfrmMain.sbSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if HandleSearchKey(Key) then
    Key := 0;
end;

procedure TfrmMain.tvServersDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
begin
  Accept := CanDropAt(Source, X, Y);
end;

procedure TfrmMain.tvServersDragDrop(Sender, Source: TObject; X, Y: Integer);
begin
  if CanDropAt(Source, X, Y) then
    DropSelectedNodeAt(X, Y);
end;

procedure TfrmMain.tvServersEditing(Sender: TObject; Node: TTreeNode; var AllowEdit: Boolean);
begin
  AllowEdit := FRenaming and (TObject(Node.Data) is TRdcNode);
end;

procedure TfrmMain.tvServersEdited(Sender: TObject; Node: TTreeNode; var S: string);
begin
  S := ApplyRename(Node, S);
end;

procedure TfrmMain.tvServersCancelEdit(Sender: TObject; Node: TTreeNode);
begin
  FRenaming := False;
end;

procedure TfrmMain.RecentFileClick(Sender: TObject);
begin
  OpenRecentFile(TMenuItem(Sender).Tag);
end;

{ Formulier }

procedure TfrmMain.InitializeForm;
begin
  FFiles := TObjectList<TRdcFile>.Create(True);
  FTreeNodes := TDictionary<TRdcNode, TTreeNode>.Create;
  FAppSettings := TRdcAppSettings.Create;
  FAppSettings.Load;
  FShortcutData := TObjectList<TRdcTreeShortcut>.Create(True);
  FCollapsedFiles := TList<TRdcFile>.Create;
  FShortcuts := TRdcClientShortcuts.Create;
  FShortcuts.MaxRecent := FAppSettings.RecentServerCount;
  FShortcuts.LoadFrom(FAppSettings.Favorites, FAppSettings.RecentServers);

  FSessions := TRdcSessionManager.Create(pnlSession);
  FSessions.OnStateChanged := SessionsStateChanged;
  FSessions.OnDisplayChanged := SessionsDisplayChanged;
  FSessions.OnCredentialRequest := CredentialRequest;
  FSessions.OnTailnetOptions := TailnetOptions;
  FSessions.OnPlaceHost := PlaceNewHost;
  FSessionWindows := TDictionary<TRdcServer, TfrmSessionWindow>.Create;
  FStoredPasswordUsed := TDictionary<TRdcServer, string>.Create;
  FVault := TRdcPasswordVault.Create(TRdcWindowsBlobStore.Create);
  FTailnetManager := TRdcTailnetManager.Create;
  FPingStates := TDictionary<string, TRdcPingResult>.Create;
  FPingSince := TDictionary<string, TDateTime>.Create;
  FPingLastSeen := TDictionary<string, TDateTime>.Create;
  FPingChecked := TDictionary<string, TDateTime>.Create;
  Application.HintHidePause := 10000; // tooltips met meerdere regels: tijd om te lezen
  FPinger := TRdcPinger.Create(PingResultsArrived);
  FPinger.SetInterval(FAppSettings.PingIntervalSec * 1000);
  FSessions.TailnetManager := FTailnetManager;
  FSessions.Secrets := Self;
  FVaultTimer := TTimer.Create(Self);
  FVaultTimer.Interval := 30000;
  FVaultTimer.OnTimer := VaultTimerFired;
  DropLegacyPasswords;
  FAutoSaveTimer := TTimer.Create(Self);
  FAutoSaveTimer.Enabled := False;
  FAutoSaveTimer.Interval := 2000;
  FAutoSaveTimer.OnTimer := AutoSaveTimerFired;
  FSessions.OnActivated := SessionsActivated;

  FPanes := TRdcSessionPanes.Create(pnlSession, lblPlaceholder, ilNodes, pmTabs);
  FPanes.EmptyText := _('Geen open sessies.'#13#10#13#10'Dubbelklik op een server in de boom (of selecteer hem en druk op Enter) om te verbinden.');
  FPanes.EmptyPaneText := _('Leeg vak'#13#10#13#10'Sleep een tab hierheen of klik hier en dubbelklik op een server.');
  FPanes.ApplyColors(RdcActiveStyleIsDark);
  FPanes.OnActiveChanged := PanesActiveChanged;
  FPanes.OnCloseRequest := PanesCloseRequest;
  FPanes.OnLayoutChanged := PanesLayoutChanged;
  FPanes.OnTabImage := TabImageFor;
  RestoreGrid;

  RestoreWindowLayout;
  RebuildImages;
  sbStatus.Panels[3].Text := AppVersionText;
  LayoutStatusBar;
  BuildTree;
  UpdateRecentMenu;
  ShowActiveSession;
  // Bestanden pas openen als het venster er staat (meldingen hebben een eigenaar nodig).
  TThread.ForceQueue(nil, OpenStartupFiles);
end;

procedure TfrmMain.FinalizeForm;
var
  lFile: TRdcFile;
begin
  if FAppSettings <> nil then
  begin
    FAppSettings.OpenFiles.Clear;
    if FFiles <> nil then
      for lFile in FFiles do
        if lFile.FileName <> '' then
          FAppSettings.OpenFiles.Add(lFile.FileName);
    StoreGrid;
    StoreShortcuts;
    FAppSettings.Save;
  end;
  // Losgemaakte sessies eerst terug: een host mag niet met zijn (Win32-)venster mee verdwijnen.
  DockAllServers;
  FreeAndNil(FPinger); // wacht op de lopende ronde; nog niet afgeleverde resultaten vervallen
  FreeAndNil(FPingStates);
  FreeAndNil(FPingSince);
  FreeAndNil(FPingLastSeen);
  FreeAndNil(FPingChecked);
  FreeAndNil(FSessionWindows);
  FreeAndNil(FStoredPasswordUsed);
  if FVaultTimer <> nil then
    FVaultTimer.Enabled := False;
  FreeAndNil(FVault); // vergrendelt en wist de sleutel
  FreeAndNil(FPanes);
  FreeAndNil(FShortcuts);
  FreeAndNil(FShortcutData);
  FreeAndNil(FCollapsedFiles);
  FreeAndNil(FSessions);
  FreeAndNil(FTailnetManager); // na de sessies: sluit alle Tailscale-netwerken (ephemeral nodes melden zich af)
  FreeAndNil(FTreeNodes);
  FreeAndNil(FFiles);
  FreeAndNil(FAppSettings);
end;

procedure TfrmMain.FormShown;
begin
  // Pas nu is de schaal voor de monitor bekend (Per-Monitor V2).
  RebuildImages;
  LayoutStatusBar;
  if not FShown then
  begin
    FShown := True;
    RestoreTreeWidth;
  end;
end;

procedure TfrmMain.OpenStartupFiles;
var
  lFileName: string;
  lFileNames: TArray<string>;
  lIndex: Integer;
begin
  lFileNames := FAppSettings.OpenFiles.ToStringArray;
  // Niet zichtbaar opbouwen: pas tekenen als alles geopend en ingeklapt is.
  tvServers.Items.BeginUpdate;
  try
    for lFileName in lFileNames do
      OpenFile(lFileName, True);
    // Bestanden op de opdrachtregel (bijv. "Openen met" vanuit de Verkenner).
    for lIndex := 1 to ParamCount do
      if not CharInSet(ParamStr(lIndex)[1], ['/', '-']) then
        OpenFile(ExpandFileName(ParamStr(lIndex)));
    // Bij starten: alleen Favorieten en Recent open, de rest ingeklapt (gebruikerswens).
    CollapseAllFiles;
    UpdatePingTargets;
    // Geen bestanden: lege boom (Bestand > Nieuw bestand of Openen); geen automatisch leeg "Nieuw bestand" meer.
    if tvServers.Items.Count > 0 then
      tvServers.Items[0].Selected := True;
  finally
    tvServers.Items.EndUpdate;
  end;
end;

function TfrmMain.PingKeyOf(aServer: TRdcServer; out aKey: string): Boolean;
var
  lRoute: TRdcxRouteSettings;
begin
  // Alleen bij route Direct: via Tailscale of een gateway is de server vanaf deze pc niet rechtstreeks bereikbaar.
  aKey := '';
  lRoute := aServer.EffectiveRoute;
  Result := lRoute.PingEnabled and (lRoute.Kind = rkDirect) and (Trim(aServer.Name) <> '');
  if Result then
    aKey := TRdcPingTarget.Create(aServer.Name, aServer.EffectiveConnection.Port).Key;
end;

function TfrmMain.PingStateOf(aServer: TRdcServer): TRdcPingState;
var
  lKey: string;
  lResult: TRdcPingResult;
begin
  if (FPingStates = nil) or not PingKeyOf(aServer, lKey) or not FPingStates.TryGetValue(lKey, lResult) then
    Exit(psUnknown);
  if lResult.Online and lResult.Mismatch then
    Result := psWrongHost
  else if lResult.Online then
    Result := psOnline
  else
    Result := psOffline;
end;

procedure TfrmMain.UpdatePingTargets;
var
  lFile: TRdcFile;
  lKey: string;
  lKeys: TStringList;
  lNode: TRdcNode;
  lServers: TList<TRdcNode>;
  lTargets: TArray<TRdcPingTarget>;
begin
  if FPinger = nil then
    Exit;
  lTargets := [];
  lKeys := TStringList.Create;
  lServers := TList<TRdcNode>.Create;
  try
    lKeys.Sorted := True;
    lKeys.Duplicates := dupIgnore;
    for lFile in FFiles do
    begin
      lServers.Clear;
      lFile.CollectServers(lServers);
      for lNode in lServers do
        if PingKeyOf(TRdcServer(lNode), lKey) and (lKeys.IndexOf(lKey) < 0) then
        begin
          lKeys.Add(lKey);
          lTargets := lTargets + [TRdcPingTarget.Create(lNode.Name, TRdcServer(lNode).EffectiveConnection.Port)];
        end;
    end;
    // Alleen doorgeven als de lijst echt veranderd is (anders start elke wijziging een nieuwe ronde).
    if lKeys.Text = FPingTargetKeys then
      Exit;
    FPingTargetKeys := lKeys.Text;
  finally
    lServers.Free;
    lKeys.Free;
  end;
  FPinger.SetTargets(lTargets);
end;

procedure TfrmMain.PingResultsArrived(const aResults: TArray<TRdcPingResult>);
var
  lChanged: Boolean;
  lNode: TRdcNode;
  lOld: TRdcPingResult;
  lResult: TRdcPingResult;
begin
  if FClosing or (FPingStates = nil) then
    Exit;
  lChanged := False;
  for lResult in aResults do
  begin
    if not FPingStates.TryGetValue(lResult.Key, lOld) or (lOld.Online <> lResult.Online) then
    begin
      FPingSince.AddOrSetValue(lResult.Key, Now);
      lChanged := True;
    end
    else if (lOld.Mismatch <> lResult.Mismatch) or not SameText(lOld.ActualName, lResult.ActualName) then
      lChanged := True;
    FPingStates.AddOrSetValue(lResult.Key, lResult);
    FPingChecked.AddOrSetValue(lResult.Key, Now);
    if lResult.Online then
      FPingLastSeen.AddOrSetValue(lResult.Key, Now);
  end;
  // Tooltip die nu zichtbaar is bijwerken bij de volgende muisbeweging.
  FHintTreeNode := nil;
  if lChanged then
    for lNode in FTreeNodes.Keys.ToArray do
      if lNode is TRdcServer then
        UpdateNodeImage(lNode);
  ShowPingStatusOfSelected;
end;

procedure TfrmMain.UpdateTreeHint(X, Y: Integer);
var
  lTreeNode: TTreeNode;
begin
  // Tooltip per knoop: alleen opnieuw opbouwen als de muis naar een andere knoop gaat.
  lTreeNode := tvServers.GetNodeAt(X, Y);
  if lTreeNode = FHintTreeNode then
    Exit;
  FHintTreeNode := lTreeNode;
  if lTreeNode = nil then
    tvServers.Hint := ''
  else
    tvServers.Hint := TreeNodeHint(lTreeNode);
  Application.CancelHint;
end;

function TfrmMain.TreeNodeHint(aTreeNode: TTreeNode): string;
var
  lCount: Integer;
  lNode: TRdcNode;
  lOnline: Integer;
  lServers: TList<TRdcNode>;
  lShortcut: TRdcTreeShortcut;
  lState: TRdcPingState;
begin
  lShortcut := ShortcutOf(aTreeNode);
  if (lShortcut <> nil) and (lShortcut.Kind = tskFavoritesHeader) then
    Exit(_('Favoriete servers (Server > Aan favorieten toevoegen)'));
  if (lShortcut <> nil) and (lShortcut.Kind = tskRecentHeader) then
    Exit(_('Laatst verbonden servers, nieuwste bovenaan (aantal: Bestand > Opties)'));
  lNode := NodeOfTreeNode(aTreeNode);
  if lNode is TRdcServer then
    Exit(ServerHint(TRdcServer(lNode)));
  if not (lNode is TRdcGroup) then
    Exit('');
  // Groep of bestand: aantal servers en, met ping, hoeveel er bereikbaar zijn.
  lServers := TList<TRdcNode>.Create;
  try
    TRdcGroup(lNode).CollectServers(lServers);
    lCount := lServers.Count;
    lOnline := 0;
    for lNode in lServers do
    begin
      lState := PingStateOf(TRdcServer(lNode));
      if lState in [psOnline, psWrongHost] then
        Inc(lOnline);
    end;
  finally
    lServers.Free;
  end;
  if TObject(aTreeNode.Data) is TRdcFile then
    Result := Format(_('%s'#13#10'%d server(s)'), [IfThen(TRdcFile(aTreeNode.Data).FileName <> '', TRdcFile(aTreeNode.Data).FileName, _('Nog niet opgeslagen')), lCount])
  else
    Result := Format(_('%s'#13#10'%d server(s)'), [TRdcNode(aTreeNode.Data).Caption, lCount]);
  if lOnline > 0 then
    Result := Result + Format(_(', %d bereikbaar'), [lOnline]);
end;

function TfrmMain.ServerHint(aServer: TRdcServer): string;

  function SessionText(aState: TRdpSessionState): string;
  begin
    case aState of
      rssConnecting:
        Result := _('Verbinden...');
      rssConnected:
        Result := _('Verbonden');
      rssLoggedIn:
        Result := _('Aangemeld');
      rssDisconnecting:
        Result := _('Verbreken...');
    else
      Result := '';
    end;
  end;

var
  lChecked: TDateTime;
  lKey: string;
  lLines: TStringList;
  lResult: TRdcPingResult;
  lSeen: TDateTime;
  lSince: TDateTime;
begin
  lLines := TStringList.Create;
  try
    lLines.Add(aServer.Caption);
    if not SameText(aServer.Caption, aServer.Name) then
      lLines.Add(Format(_('Server: %s'), [aServer.Name]));
    // Sessie
    if FSessions.StateOf(aServer) <> rssDisconnected then
      lLines.Add(Format(_('Sessie: %s'), [SessionText(FSessions.StateOf(aServer))]))
    else if FSessions.HasError(aServer) then
      lLines.Add(_('Sessie: fout bij de laatste verbinding'));
    // Bereikbaarheid
    if not PingKeyOf(aServer, lKey) then
    begin
      if aServer.EffectiveRoute.Kind <> rkDirect then
        lLines.Add(_('Bereikbaarheid: niet gecontroleerd (route via Tailscale of gateway)'))
      else
        lLines.Add(_('Bereikbaarheid: niet gecontroleerd (zet aan via Eigenschappen > Route)'));
    end
    else if not FPingStates.TryGetValue(lKey, lResult) then
      lLines.Add(_('Bereikbaarheid: nog niet gecontroleerd'))
    else
    begin
      if lResult.Online and lResult.Mismatch then
        lLines.Add(Format(_('Bereikbaarheid: op %s antwoordt %s, niet deze server (DNS-record verouderd?)'), [lResult.Address, lResult.ActualName]))
      else if lResult.Online then
        lLines.Add(Format(_('Bereikbaarheid: online (%d ms, %s)'), [lResult.RoundTripMs, lResult.Address]))
      else if FPingSince.TryGetValue(lKey, lSince) then
        lLines.Add(Format(_('Bereikbaarheid: niet bereikbaar sinds %s'), [FormatDateTime('dd-mm hh:nn', lSince)]))
      else
        lLines.Add(_('Bereikbaarheid: niet bereikbaar'));
      if FPingLastSeen.TryGetValue(lKey, lSeen) then
        lLines.Add(Format(_('Laatst gezien: %s'), [FormatDateTime('dd-mm-yyyy hh:nn:ss', lSeen)]))
      else
        lLines.Add(_('Laatst gezien: niet sinds de start van RDCManagerX'));
      if FPingChecked.TryGetValue(lKey, lChecked) then
        lLines.Add(Format(_('Laatste controle: %s'), [FormatDateTime('hh:nn:ss', lChecked)]));
    end;
    if aServer.Comment <> '' then
      lLines.Add(Format(_('Opmerking: %s'), [aServer.Comment]));
    Result := lLines.Text.TrimRight;
  finally
    lLines.Free;
  end;
end;

procedure TfrmMain.ShowPingStatusOfSelected;
var
  lKey: string;
  lResult: TRdcPingResult;
  lServer: TRdcServer;
  lSince: TDateTime;
begin
  // Alleen voor een niet-verbonden server met ping aan (anders laat de statusbalk zijn eigen meldingen staan).
  lServer := SelectedServer;
  if (lServer = nil) or (FSessions.StateOf(lServer) <> rssDisconnected) or not PingKeyOf(lServer, lKey) or not FPingStates.TryGetValue(lKey, lResult) then
    Exit;
  if lResult.Online and lResult.Mismatch then
    sbStatus.Panels[0].Text := Format(_('Op %s antwoordt %s, niet %s (DNS-record verouderd?)'), [lResult.Address, lResult.ActualName, lServer.Name])
  else if lResult.Online then
    sbStatus.Panels[0].Text := Format(_('%s is online (%d ms)'), [lServer.Caption, lResult.RoundTripMs])
  else if FPingSince.TryGetValue(lKey, lSince) then
    sbStatus.Panels[0].Text := Format(_('%s is niet bereikbaar (sinds %s)'), [lServer.Caption, FormatDateTime('hh:nn', lSince)])
  else
    sbStatus.Panels[0].Text := Format(_('%s is niet bereikbaar'), [lServer.Caption]);
end;

procedure TfrmMain.ShowManual;
var
  lDir: string;
  lEnglish: Boolean;
  lExisting: TBytes;
  lFile: string;
  lName: string;
  lResource: TResourceStream;
  lBytes: TBytes;
begin
  // De handleiding zit in de exe (zoals tsbridge.dll): uitpakken naar het eigen profiel en openen. Een CHM vanaf een
  // netwerkshare toont Windows niet (beveiliging); lokaal wel. Is er geen CHM ingebouwd, dan de HTML in de browser.
  // English UI: the English manual, falling back to the Dutch one when it is not embedded.
  lEnglish := UiLanguageCode = 'en';
  if lEnglish and (FindResource(HInstance, 'HELPCHM_EN', RT_RCDATA) <> 0) then
  begin
    lName := 'HELPCHM_EN';
    lFile := 'RDCManagerX-en.chm';
  end
  else if lEnglish and (FindResource(HInstance, 'HELPHTML_EN', RT_RCDATA) <> 0) then
  begin
    lName := 'HELPHTML_EN';
    lFile := 'RDCManagerX-Manual.html';
  end
  else if FindResource(HInstance, 'HELPCHM', RT_RCDATA) <> 0 then
  begin
    lName := 'HELPCHM';
    lFile := 'RDCManagerX.chm';
  end
  else
  begin
    lName := 'HELPHTML';
    lFile := 'RDCManagerX-Handleiding.html';
  end;
  lDir := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RDCManagerX'), 'help');
  lFile := TPath.Combine(lDir, lFile);
  try
    lResource := TResourceStream.Create(HInstance, lName, RT_RCDATA);
    try
      SetLength(lBytes, lResource.Size);
      if Length(lBytes) > 0 then
        lResource.ReadBuffer(lBytes[0], Length(lBytes));
    finally
      lResource.Free;
    end;
    TDirectory.CreateDirectory(lDir);
    // Alleen schrijven als de inhoud anders is (nieuwe versie) of het bestand ontbreekt.
    if TFile.Exists(lFile) then
      lExisting := TFile.ReadAllBytes(lFile)
    else
      lExisting := nil;
    if (Length(lExisting) <> Length(lBytes)) or ((Length(lBytes) > 0) and not CompareMem(@lExisting[0], @lBytes[0], Length(lBytes))) then
      TFile.WriteAllBytes(lFile, lBytes);
  except
    on E: Exception do
    begin
      MessageDlg(Format(_('De handleiding kon niet worden geopend: %s'), [E.Message]), mtWarning, [mbOK], 0);
      Exit;
    end;
  end;
  ShellExecute(Handle, 'open', PChar(lFile), nil, nil, SW_SHOWNORMAL);
end;

procedure TfrmMain.CollapseAllFiles;
var
  lFile: TRdcFile;
  lGroup: TRdcNode;
  lNodes: TList<TRdcNode>;
  lTreeNode: TTreeNode;
begin
  // Ook in het model (zonder "gewijzigd"), zodat een latere herbouw van de boom (bijv. na zoeken) ingeklapt blijft.
  lNodes := TList<TRdcNode>.Create;
  try
    for lFile in FFiles do
    begin
      lNodes.Clear;
      lFile.CollectNodes(lNodes);
      for lGroup in lNodes do
        if (lGroup is TRdcGroup) and TRdcGroup(lGroup).Expanded then
          TRdcGroup(lGroup).Expanded := False;
      if not FCollapsedFiles.Contains(lFile) then
        FCollapsedFiles.Add(lFile);
      if FTreeNodes.TryGetValue(lFile, lTreeNode) then
        lTreeNode.Collapse(True);
    end;
  finally
    lNodes.Free;
  end;
end;

procedure TfrmMain.HandleDpiChanged;
begin
  RebuildImages;
  FSessions.NotifyDpiChanged;
  UpdateStatusBar;
end;

function TfrmMain.OpenSessionsCloseQuestion(aActive: Integer): string;
const
  cMaxListed = 10;
var
  lCount: Integer;
  lNames: string;
  lServer: TRdcServer;
begin
  // Vraag bij afsluiten met de namen van de open sessies (maximaal cMaxListed).
  lNames := '';
  lCount := 0;
  for lServer in FSessions.ActiveServers do
  begin
    Inc(lCount);
    if lCount <= cMaxListed then
      lNames := lNames + #13#10'  - ' + lServer.Caption;
  end;
  if lCount > cMaxListed then
    lNames := lNames + #13#10 + Format(_('  ... en nog %d'), [lCount - cMaxListed]);
  Result := Format(_('Er zijn nog %d open sessie(s):%s'#13#10#13#10'Weet u zeker dat u RDCManagerX wilt afsluiten? Alle sessies worden verbroken (niet afgemeld).'), [aActive, lNames]);
end;

function TfrmMain.CanCloseApplication: Boolean;
var
  lActive: Integer;
  lFile: TRdcFile;
begin
  Result := True;
  if FForceClose then
    Exit;
  // Eerst niet-opgeslagen wijzigingen (één keer vragen, ook als het sluiten daarna op sessies wacht).
  if not FFilesConfirmed then
  begin
    for lFile in FFiles do
      if not ConfirmSaveFile(lFile) then
        Exit(False);
    FFilesConfirmed := True;
  end;
  lActive := FSessions.ActiveCount;
  if lActive = 0 then
    Exit;
  Result := False;
  if FClosing then
    Exit;
  if MessageDlg(OpenSessionsCloseQuestion(lActive), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
  begin
    FFilesConfirmed := False;
    Exit;
  end;
  // Netjes verbreken; sluiten gebeurt zodra alles verbroken is (of na de time-out van tmrClose).
  FClosing := True;
  tmrClose.Enabled := True;
  FSessions.DisconnectAll;
  HideWhileDisconnecting;
end;

procedure TfrmMain.HideWhileDisconnecting;
begin
  // Het verbreken (wachten op OnDisconnected, max. tmrClose) gebeurt onzichtbaar; layout nu vastleggen, verborgen klopt die niet meer.
  StoreWindowLayout;
  Hide;
end;

procedure TfrmMain.ForceCloseAfterTimeout;
begin
  tmrClose.Enabled := False;
  FForceClose := True;
  Close;
end;

{ Layout }

function TfrmMain.MonitorConfigKey: string;
var
  lIndex: Integer;
  lMonitor: TMonitor;
begin
  // Aantal monitoren + positie/afmeting/DPI van elk: laptop los en laptop in docking krijgen elk een eigen layout.
  Result := '';
  for lIndex := 0 to Screen.MonitorCount - 1 do
  begin
    lMonitor := Screen.Monitors[lIndex];
    Result := Result + Format('%d,%d,%d,%d@%d;', [lMonitor.BoundsRect.Left, lMonitor.BoundsRect.Top, lMonitor.BoundsRect.Right, lMonitor.BoundsRect.Bottom, lMonitor.PixelsPerInch]);
  end;
end;

procedure TfrmMain.RestoreWindowLayout;
var
  lLayout: TRdcWindowLayout;
  lPlacement: TWindowPlacement;
  lRect: TRect;
begin
  lLayout := FAppSettings.GetLayout(MonitorConfigKey);
  FRestoredTreeWidth := lLayout.TreeWidth;
  if not lLayout.Valid or (lLayout.Width <= 0) or (lLayout.Height <= 0) then
    Exit;
  lRect := Rect(lLayout.Left, lLayout.Top, lLayout.Left + lLayout.Width, lLayout.Top + lLayout.Height);
  // Alleen herstellen als het venster op een bestaande monitor valt (anders: standaardpositie).
  if MonitorFromRect(@lRect, MONITOR_DEFAULTTONULL) = 0 then
    Exit;
  Position := poDesigned;
  FillChar(lPlacement, SizeOf(lPlacement), 0);
  lPlacement.length := SizeOf(lPlacement);
  GetWindowPlacement(Handle, @lPlacement);
  lPlacement.rcNormalPosition := lRect;
  lPlacement.showCmd := SW_HIDE;
  // Twee keer: de eerste keer kan een DPI-wissel (andere monitor) de afmeting nog aanpassen.
  SetWindowPlacement(Handle, @lPlacement);
  SetWindowPlacement(Handle, @lPlacement);
  if lLayout.Maximized then
    WindowState := wsMaximized;
end;

function TfrmMain.CurrentRectInWorkspace(var aRect: TRect): Boolean;
var
  lMonitor: HMONITOR;
  lMonitorInfo: TMonitorInfo;
  lWindowRect: TRect;
begin
  // WINDOWPLACEMENT werkt in werkgebied-coördinaten (verschoven als de taakbalk links/boven staat).
  Result := False;
  if not GetWindowRect(Handle, lWindowRect) then
    Exit;
  lMonitor := MonitorFromWindow(Handle, MONITOR_DEFAULTTONEAREST);
  lMonitorInfo.cbSize := SizeOf(lMonitorInfo);
  if not GetMonitorInfo(lMonitor, @lMonitorInfo) then
    Exit;
  lWindowRect.Offset(-(lMonitorInfo.rcWork.Left - lMonitorInfo.rcMonitor.Left), -(lMonitorInfo.rcWork.Top - lMonitorInfo.rcMonitor.Top));
  aRect := lWindowRect;
  Result := True;
end;

procedure TfrmMain.StoreWindowLayout;
var
  lLayout: TRdcWindowLayout;
  lPlacement: TWindowPlacement;
begin
  // Verborgen = al vastgelegd in HideWhileDisconnecting.
  if (FAppSettings = nil) or not HandleAllocated or not Visible then
    Exit;
  FillChar(lPlacement, SizeOf(lPlacement), 0);
  lPlacement.length := SizeOf(lPlacement);
  if not GetWindowPlacement(Handle, @lPlacement) then
    Exit;
  // Gesnapt (Snap-indeling, Win+pijl, slepen naar de rand) telt voor Windows als "normaal", maar rcNormalPosition
  // is dan de positie van vóór het snappen. Daarom bij een normaal venster de werkelijke positie nemen.
  if not IsIconic(Handle) and not IsZoomed(Handle) then
    CurrentRectInWorkspace(lPlacement.rcNormalPosition);
  lLayout.Valid := True;
  lLayout.Left := lPlacement.rcNormalPosition.Left;
  lLayout.Top := lPlacement.rcNormalPosition.Top;
  lLayout.Width := lPlacement.rcNormalPosition.Width;
  lLayout.Height := lPlacement.rcNormalPosition.Height;
  // Geminimaliseerd afgesloten: herstellen zoals het vóór minimaliseren was.
  lLayout.Maximized := (WindowState = wsMaximized) or ((WindowState = wsMinimized) and (lPlacement.flags and WPF_RESTORETOMAXIMIZED <> 0));
  lLayout.TreeWidth := MulDiv(pnlLeft.Width, 96, CurrentPPI);
  FAppSettings.SetLayout(MonitorConfigKey, lLayout);
end;

procedure TfrmMain.RestoreTreeWidth;
var
  lWidth: Integer;
begin
  if FRestoredTreeWidth < cMinTreeWidth96 then
    Exit;
  lWidth := MulDiv(FRestoredTreeWidth, CurrentPPI, 96);
  pnlLeft.Width := Min(lWidth, Max(ClientWidth - MulDiv(200, CurrentPPI, 96), MulDiv(cMinTreeWidth96, CurrentPPI, 96)));
end;

procedure TfrmMain.RebuildImages;
begin
  BuildNodeImages(ilNodes, CurrentPPI);
  // Opnieuw toewijzen zodat boom en tabs de hoogte aan de nieuwe icoongrootte aanpassen.
  tvServers.Images := nil;
  tvServers.Images := ilNodes;
  // Ruimere, modernere rijen (ook na een handle-recreate, bijv. thema- of DPI-wissel).
  TreeView_SetItemHeight(tvServers.Handle, MulDiv(26, CurrentPPI, 96));
  if FPanes <> nil then
  begin
    FPanes.SetImages(ilNodes);
    FPanes.Layout;
  end;
end;

{ Boom }

function TfrmMain.AddTreeNode(aParent: TTreeNode; aNode: TRdcNode): TTreeNode;
var
  lIndex: Integer;
begin
  Result := nil;
  // Met een zoekfilter alleen wat overeenkomt (plus de groepen erboven); bestanden blijven altijd staan.
  if (FFilter <> '') and not (aNode is TRdcFile) and not NodeMatchesFilter(aNode) then
    Exit;
  if aNode is TRdcFile then
    Result := tvServers.Items.AddChildObject(aParent, FileDisplayText(TRdcFile(aNode)), aNode)
  else
    Result := tvServers.Items.AddChildObject(aParent, aNode.Caption, aNode);
  FTreeNodes.AddOrSetValue(aNode, Result);
  Result.ImageIndex := NodeImageIndex(aNode);
  Result.SelectedIndex := Result.ImageIndex;
  if aNode is TRdcGroup then
  begin
    for lIndex := 0 to TRdcGroup(aNode).Count - 1 do
      AddTreeNode(Result, TRdcGroup(aNode)[lIndex]);
    // Uitklapstand uit het bestand (RDCMan: <expanded>); een bestand staat open tenzij de gebruiker het inklapte
    // (of bij starten); bij zoeken alles open.
    if (FFilter <> '') or ((aNode is TRdcFile) and not FCollapsedFiles.Contains(TRdcFile(aNode))) or (not (aNode is TRdcFile) and TRdcGroup(aNode).Expanded) then
      Result.Expand(False);
  end;
end;

procedure TfrmMain.BuildTree;
var
  lFile: TRdcFile;
begin
  tvServers.Items.BeginUpdate;
  try
    tvServers.Items.Clear;
    FTreeNodes.Clear;
    FFavoritesHeader := nil;
    FRecentHeader := nil;
    FShortcutData.Clear;
    for lFile in FFiles do
      AddTreeNode(nil, lFile);
  finally
    tvServers.Items.EndUpdate;
  end;
  RebuildShortcutNodes;
end;

function TfrmMain.CompareTreeNodes(aNode1, aNode2: TTreeNode): Integer;
const
  // Volgorde bovenin de boom: Recent, dan Favorieten.
  cShortcutKindOrder: array[TRdcTreeShortcutKind] of Integer = (1, 0, 3, 2);
var
  lNode1: TRdcNode;
  lNode2: TRdcNode;
  lShortcut1: TRdcTreeShortcut;
  lShortcut2: TRdcTreeShortcut;
begin
  // Alleen de weergave wordt gesorteerd; de volgorde in het bestand blijft ongewijzigd (round-trip met RDCMan).
  // Recent en Favorieten bovenaan (Recent eerst, gebruikerswens); favorieten alfabetisch, recent nieuwste eerst.
  lShortcut1 := ShortcutOf(aNode1);
  lShortcut2 := ShortcutOf(aNode2);
  if (lShortcut1 <> nil) or (lShortcut2 <> nil) then
  begin
    if lShortcut1 = nil then
      Exit(1);
    if lShortcut2 = nil then
      Exit(-1);
    if lShortcut1.Kind <> lShortcut2.Kind then
      Exit(cShortcutKindOrder[lShortcut1.Kind] - cShortcutKindOrder[lShortcut2.Kind]);
    if lShortcut1.Kind = tskRecent then
      Exit(lShortcut1.Order - lShortcut2.Order);
    Exit(CompareText(aNode1.Text, aNode2.Text));
  end;
  lNode1 := TRdcNode(aNode1.Data);
  lNode2 := TRdcNode(aNode2.Data);
  if (lNode1 is TRdcFile) and (lNode2 is TRdcFile) then
    Exit(FFiles.IndexOf(TRdcFile(lNode1)) - FFiles.IndexOf(TRdcFile(lNode2))); // bestanden: volgorde van openen
  if (lNode1 is TRdcGroup) <> (lNode2 is TRdcGroup) then
  begin
    // Groepen vóór servers.
    if lNode1 is TRdcGroup then
      Exit(-1);
    Exit(1);
  end;
  Result := CompareText(lNode1.Caption, lNode2.Caption);
  if Result = 0 then
    Result := CompareStr(lNode1.Caption, lNode2.Caption);
end;

function TfrmMain.NodeMatchesFilter(aNode: TRdcNode): Boolean;
var
  lIndex: Integer;
begin
  // Server: weergavenaam of hostnaam bevat de zoektekst. Groep: naam bevat hem, of een node eronder.
  Result := ContainsText(aNode.Caption, FFilter) or ((aNode is TRdcServer) and ContainsText(aNode.Name, FFilter));
  if not Result and (aNode is TRdcGroup) then
    for lIndex := 0 to TRdcGroup(aNode).Count - 1 do
      if NodeMatchesFilter(TRdcGroup(aNode)[lIndex]) then
        Exit(True);
end;

procedure TfrmMain.ApplyTreeFilter;
var
  lSelected: TRdcNode;
begin
  lSelected := SelectedNode;
  FFilter := Trim(sbSearch.Text);
  BuildTree;
  SelectNode(lSelected);
  if (tvServers.Selected = nil) and (tvServers.Items.Count > 0) then
    tvServers.Items[0].Selected := True;
end;

procedure TfrmMain.FocusSearch;
begin
  sbSearch.SetFocus;
  sbSearch.SelectAll;
end;

function TfrmMain.HandleSearchKey(aKey: Word): Boolean;
var
  lIndex: Integer;
begin
  // Esc: zoeken wissen; pijl omlaag/Enter: naar de eerste gevonden server in de boom; F1: handleiding.
  Result := True;
  case aKey of
    VK_F1:
      ShowManual;
    VK_ESCAPE:
      begin
        sbSearch.Text := '';
        tvServers.SetFocus;
      end;
    VK_DOWN, VK_RETURN:
      begin
        for lIndex := 0 to tvServers.Items.Count - 1 do
          if TObject(tvServers.Items[lIndex].Data) is TRdcServer then
          begin
            tvServers.Items[lIndex].Selected := True;
            Break;
          end;
        tvServers.SetFocus;
      end;
  else
    Result := False;
  end;
end;

{ Favorieten en Recent }

function TfrmMain.NodeOfTreeNode(aTreeNode: TTreeNode): TRdcNode;
begin
  if aTreeNode = nil then
    Result := nil
  else if TObject(aTreeNode.Data) is TRdcNode then
    Result := TRdcNode(aTreeNode.Data)
  else if TObject(aTreeNode.Data) is TRdcTreeShortcut then
    Result := TRdcTreeShortcut(aTreeNode.Data).Server // nil bij een kopje
  else
    Result := nil;
end;

function TfrmMain.ShortcutOf(aTreeNode: TTreeNode): TRdcTreeShortcut;
begin
  if (aTreeNode <> nil) and (TObject(aTreeNode.Data) is TRdcTreeShortcut) then
    Result := TRdcTreeShortcut(aTreeNode.Data)
  else
    Result := nil;
end;

function TfrmMain.SelectedShortcut: TRdcTreeShortcut;
begin
  Result := ShortcutOf(tvServers.Selected);
end;

function TfrmMain.NewShortcutData(aKind: TRdcTreeShortcutKind; aServer: TRdcServer; aOrder: Integer): TRdcTreeShortcut;
begin
  Result := TRdcTreeShortcut.Create;
  Result.Kind := aKind;
  Result.Server := aServer;
  Result.Order := aOrder;
  FShortcutData.Add(Result);
end;

function TfrmMain.ShortcutCaption(aServer: TRdcServer): string;
begin
  // Bij meerdere open bestanden het bestand erachter, anders is niet te zien waar een server bij hoort.
  if (FFiles.Count > 1) and (aServer.RdcFile <> nil) then
    Result := Format('%s  (%s)', [aServer.Caption, aServer.RdcFile.Caption])
  else
    Result := aServer.Caption;
end;

function TfrmMain.AddShortcutSection(aHeaderKind: TRdcTreeShortcutKind; const aCaption: string; aImageIndex: Integer; const aServers: TArray<TRdcServer>; aItemKind: TRdcTreeShortcutKind; aCollapsed: Boolean): TTreeNode;
var
  lIndex: Integer;
  lItem: TTreeNode;
begin
  Result := nil;
  if Length(aServers) = 0 then
    Exit;
  Result := tvServers.Items.AddObjectFirst(nil, aCaption, NewShortcutData(aHeaderKind, nil, 0));
  Result.ImageIndex := aImageIndex;
  Result.SelectedIndex := aImageIndex;
  for lIndex := 0 to High(aServers) do
  begin
    lItem := tvServers.Items.AddChildObject(Result, ShortcutCaption(aServers[lIndex]), NewShortcutData(aItemKind, aServers[lIndex], lIndex));
    lItem.ImageIndex := NodeImageIndex(aServers[lIndex]);
    lItem.SelectedIndex := lItem.ImageIndex;
  end;
  if not aCollapsed then
    Result.Expand(False);
end;

procedure TfrmMain.RebuildShortcutNodes;
begin
  if (FShortcuts = nil) or (FShortcutData = nil) then
    Exit;
  tvServers.Items.BeginUpdate;
  try
    if FFavoritesHeader <> nil then
      FFavoritesHeader.Delete;
    if FRecentHeader <> nil then
      FRecentHeader.Delete;
    FFavoritesHeader := nil;
    FRecentHeader := nil;
    FShortcutData.Clear;
    // Tijdens zoeken niet tonen: dan telt alleen wat overeenkomt in de bestanden.
    if FFilter = '' then
    begin
      FFavoritesHeader := AddShortcutSection(tskFavoritesHeader, _('Favorieten'), ciFavorites, FShortcuts.FavoriteServers, tskFavorite, FFavoritesCollapsed);
      FRecentHeader := AddShortcutSection(tskRecentHeader, _('Recent'), ciRecent, FShortcuts.RecentServers, tskRecent, FRecentCollapsed);
    end;
  finally
    tvServers.Items.EndUpdate;
  end;
  SortTree;
end;

procedure TfrmMain.UpdateShortcutImages(aNode: TRdcNode);
var
  lHeader: TTreeNode;
  lItem: TTreeNode;
begin
  for lHeader in [FFavoritesHeader, FRecentHeader] do
  begin
    if lHeader = nil then
      Continue;
    lItem := lHeader.getFirstChild;
    while lItem <> nil do
    begin
      if NodeOfTreeNode(lItem) = aNode then
      begin
        lItem.ImageIndex := NodeImageIndex(aNode);
        lItem.SelectedIndex := lItem.ImageIndex;
      end;
      lItem := lItem.getNextSibling;
    end;
  end;
end;

procedure TfrmMain.StoreShortcuts;
var
  lFavorites: TArray<TRdcStoredShortcut>;
  lRecent: TArray<TRdcStoredShortcut>;
begin
  if (FShortcuts = nil) or (FAppSettings = nil) then
    Exit;
  FShortcuts.SaveTo(lFavorites, lRecent);
  FAppSettings.Favorites := lFavorites;
  FAppSettings.RecentServers := lRecent;
end;

procedure TfrmMain.ToggleFavoriteSelected;
var
  lServer: TRdcServer;
begin
  lServer := SelectedServer;
  if lServer = nil then
    Exit;
  if FShortcuts.IsFavorite(lServer) then
    FShortcuts.RemoveFavorite(lServer)
  else
    FShortcuts.AddFavorite(lServer);
  StoreShortcuts;
  FAppSettings.Save;
  RebuildShortcutNodes;
end;

procedure TfrmMain.RemoveSelectedShortcut;
var
  lShortcut: TRdcTreeShortcut;
begin
  lShortcut := SelectedShortcut;
  if lShortcut = nil then
    Exit;
  if lShortcut.Kind = tskFavorite then
    FShortcuts.RemoveFavorite(lShortcut.Server)
  else if lShortcut.Kind = tskRecent then
    FShortcuts.RemoveRecent(lShortcut.Server);
  StoreShortcuts;
  FAppSettings.Save;
  RebuildShortcutNodes;
end;

procedure TfrmMain.RefreshAfterRename;
begin
  SortTree;
  RebuildShortcutNodes;
end;

procedure TfrmMain.ShowOptions;
var
  lOldLanguage: TRdcLanguage;
  lOldTheme: TRdcTheme;
  lOptions: TRdcOptions;
begin
  lOptions.Language := RdcLanguageFromName(FAppSettings.Language);
  lOptions.RecentServerCount := FAppSettings.RecentServerCount;
  lOptions.Theme := RdcThemeFromName(FAppSettings.Theme);
  lOptions.AutoSave := FAppSettings.AutoSave;
  lOptions.RememberPasswords := FAppSettings.RememberPasswords;
  lOptions.AutoLockMinutes := FAppSettings.AutoLockMinutes;
  lOptions.PingIntervalSec := FAppSettings.PingIntervalSec;
  lOldTheme := lOptions.Theme;
  lOldLanguage := lOptions.Language;
  if not TfrmOptions.Execute(lOptions, FAppSettings.RememberPasswords and FVault.IsInitialized,
    procedure
    begin
      ChangeMasterPassword;
    end) then
    Exit;
  FAppSettings.Language := cRdcLanguageNames[lOptions.Language];
  FAppSettings.RecentServerCount := lOptions.RecentServerCount;
  FAppSettings.AutoSave := lOptions.AutoSave;
  FAppSettings.AutoLockMinutes := lOptions.AutoLockMinutes;
  FAppSettings.PingIntervalSec := lOptions.PingIntervalSec;
  FPinger.SetInterval(lOptions.PingIntervalSec * 1000);
  lOptions.RememberPasswords := ApplyRememberPasswordsOption(lOptions.RememberPasswords);
  FAppSettings.RememberPasswords := lOptions.RememberPasswords;
  FShortcuts.MaxRecent := lOptions.RecentServerCount;
  // Net aangezet: wat nu al gewijzigd is meteen opslaan.
  if lOptions.AutoSave then
    ScheduleAutoSave;
  StoreShortcuts;
  FAppSettings.Save;
  RebuildShortcutNodes;
  if lOptions.Theme <> lOldTheme then
    SetTheme(lOptions.Theme);
  if lOptions.Language <> lOldLanguage then
    AnnounceLanguageChange(lOptions.Language);
end;

procedure TfrmMain.AnnounceLanguageChange(aLanguage: TRdcLanguage);
begin
  // The language is applied at startup only (forms translate while loading), like a theme with open sessions.
  if ResolveLanguageCode(aLanguage) <> UiLanguageCode then
    MessageDlg(_('De nieuwe taal wordt gebruikt vanaf de volgende start van RDCManagerX.'), mtInformation, [mbOK], 0);
end;

function TfrmMain.ApplyRememberPasswordsOption(aWanted: Boolean): Boolean;
begin
  // Uitzetten: kluis wissen na bevestiging (annuleren laat de optie aan).
  if FAppSettings.RememberPasswords and not aWanted then
    Exit(not ConfirmForgetAllPasswords);
  // Aanzetten zonder kluis: eerst een hoofdwachtwoord instellen; annuleren laat de optie uit.
  if aWanted and not FVault.IsInitialized then
  begin
    Result := CreateVault;
    UpdateVaultStatus;
    Exit;
  end;
  Result := aWanted;
end;

procedure TfrmMain.SortTree;
begin
  tvServers.AlphaSort(True);
end;

procedure TfrmMain.SetGroupExpanded(aTreeNode: TTreeNode; aExpanded: Boolean);
begin
  // Uitklapstand bijhouden (RDCMan bewaart die ook), zonder het bestand als gewijzigd te markeren.
  // Niet tijdens zoeken: dan staat alles open zonder dat de gebruiker dat koos.
  if FFilter <> '' then
    Exit;
  if ShortcutOf(aTreeNode) <> nil then
  begin
    // Kopjes Favorieten/Recent: alleen in het geheugen onthouden (zolang het programma draait).
    if ShortcutOf(aTreeNode).Kind = tskFavoritesHeader then
      FFavoritesCollapsed := not aExpanded
    else if ShortcutOf(aTreeNode).Kind = tskRecentHeader then
      FRecentCollapsed := not aExpanded;
    Exit;
  end;
  if TObject(aTreeNode.Data) is TRdcFile then
  begin
    // Hoofdknoop van een bestand: alleen in het geheugen (komt niet in het bestand).
    if aExpanded then
      FCollapsedFiles.Remove(TRdcFile(aTreeNode.Data))
    else if not FCollapsedFiles.Contains(TRdcFile(aTreeNode.Data)) then
      FCollapsedFiles.Add(TRdcFile(aTreeNode.Data));
  end
  else if TObject(aTreeNode.Data) is TRdcGroup then
    TRdcGroup(aTreeNode.Data).Expanded := aExpanded;
end;

function TfrmMain.HandleTreeKey(aKey: Word; aShift: TShiftState): Boolean;
begin
  Result := False;
  if tvServers.IsEditing then
    Exit;
  Result := True;
  if (aKey = VK_RETURN) and (aShift = [ssAlt]) then
    actProperties.Execute
  else if (aKey = VK_RETURN) and (aShift = []) then
    ConnectSelectedServer
  else if (aKey = VK_DELETE) and (aShift = []) then
    actDelete.Execute
  else if (aKey = VK_F2) and (aShift = []) then
    actRename.Execute
  else if (aKey = Ord('N')) and (aShift = [ssCtrl]) then
    actNewServer.Execute
  else if (aKey = Ord('G')) and (aShift = [ssCtrl]) then
    actNewGroup.Execute
  else if (aKey = Ord('D')) and (aShift = [ssCtrl]) then
    actDisconnect.Execute
  else if (aKey = Ord('S')) and (aShift = [ssCtrl]) then
    actSave.Execute
  else if (aKey = Ord('O')) and (aShift = [ssCtrl]) then
    actOpen.Execute
  else if (aKey = VK_F1) and (aShift = []) then
  begin
    ShowManual;
    Result := True;
  end
  else if (aKey = Ord('F')) and (aShift = [ssCtrl]) then
    FocusSearch
  else
    Result := False;
end;

procedure TfrmMain.RemoveTreeMapping(aNode: TRdcNode);
var
  lIndex: Integer;
begin
  FTreeNodes.Remove(aNode);
  if aNode is TRdcGroup then
    for lIndex := 0 to TRdcGroup(aNode).Count - 1 do
      RemoveTreeMapping(TRdcGroup(aNode)[lIndex]);
end;

function TfrmMain.NodeImageIndex(aNode: TRdcNode): Integer;
var
  lServer: TRdcServer;
begin
  if not (aNode is TRdcServer) then
    Exit(ciGroup);
  lServer := TRdcServer(aNode);
  case FSessions.StateOf(lServer) of
    rssConnecting, rssConnected, rssDisconnecting:
      Result := ciServerConnecting;
    rssLoggedIn:
      Result := ciServerConnected;
  else
    if FSessions.HasError(lServer) then
      Result := ciServerError
    else
      case PingStateOf(lServer) of
        psOnline:
          Result := ciServerOnline;
        psOffline:
          Result := ciServerOffline;
        psWrongHost:
          Result := ciServerWrongHost;
      else
        Result := ciServer; // geen ping, of nog geen resultaat
      end;
  end;
end;

procedure TfrmMain.UpdateNodeImage(aNode: TRdcNode);
var
  lTreeNode: TTreeNode;
begin
  if FTreeNodes.TryGetValue(aNode, lTreeNode) then
  begin
    lTreeNode.ImageIndex := NodeImageIndex(aNode);
    lTreeNode.SelectedIndex := lTreeNode.ImageIndex;
  end;
  UpdateShortcutImages(aNode);
end;

procedure TfrmMain.UpdateNodeCaption(aNode: TRdcNode);
begin
  if aNode is TRdcFile then
    UpdateFileNodeText(TRdcFile(aNode))
  else if FTreeNodes.ContainsKey(aNode) then
    FTreeNodes[aNode].Text := aNode.Caption;
  if aNode is TRdcServer then
  begin
    FPanes.UpdateCaption(TRdcServer(aNode));
    if SessionWindowOf(TRdcServer(aNode)) <> nil then
      SessionWindowOf(TRdcServer(aNode)).UpdateCaption;
  end;
  RebuildShortcutNodes;
end;

function TfrmMain.SelectedNode: TRdcNode;
begin
  // Een favoriet of recente server staat voor de echte server (verbinden, eigenschappen, WOL werken gewoon).
  Result := NodeOfTreeNode(tvServers.Selected);
end;

function TfrmMain.SelectedServer: TRdcServer;
var
  lNode: TRdcNode;
begin
  lNode := SelectedNode;
  if lNode is TRdcServer then
    Result := TRdcServer(lNode)
  else
    Result := nil;
end;

procedure TfrmMain.SelectNode(aNode: TRdcNode);
var
  lTreeNode: TTreeNode;
begin
  if (aNode <> nil) and FTreeNodes.TryGetValue(aNode, lTreeNode) then
  begin
    lTreeNode.MakeVisible;
    lTreeNode.Selected := True;
  end;
end;

function TfrmMain.TargetGroup: TRdcGroup;
var
  lNode: TRdcNode;
begin
  lNode := SelectedNode;
  if lNode is TRdcGroup then
    Result := TRdcGroup(lNode)
  else if lNode <> nil then
    Result := lNode.Parent
  else if FFiles.Count > 0 then
    Result := FFiles[0]
  else
    Result := nil;
end;

{ Boom: bewerken }

procedure TfrmMain.AddNodeToTree(aGroup: TRdcGroup; aNode: TRdcNode);
begin
  aGroup.Add(aNode);
  AddTreeNode(FTreeNodes[aGroup], aNode);
  FTreeNodes[aGroup].Expand(False);
  MarkModified(aNode);
  SortTree;
  SelectNode(aNode);
end;

procedure TfrmMain.AddNewServer;
var
  lGroup: TRdcGroup;
  lServer: TRdcServer;
begin
  lGroup := TargetGroup;
  if lGroup = nil then
    Exit;
  lServer := TRdcServer.Create('');
  if TfrmProperties.Execute(lServer, lGroup) then
    AddNodeToTree(lGroup, lServer)
  else
    lServer.Free;
end;

procedure TfrmMain.AddNewGroup;
var
  lGroup: TRdcGroup;
  lNewGroup: TRdcGroup;
begin
  lGroup := TargetGroup;
  if lGroup = nil then
    Exit;
  lNewGroup := TRdcGroup.Create(_('Nieuwe groep'));
  if TfrmProperties.Execute(lNewGroup, lGroup) then
    AddNodeToTree(lGroup, lNewGroup)
  else
    lNewGroup.Free;
end;

procedure TfrmMain.StartRenameSelected;
begin
  if tvServers.Selected = nil then
    Exit;
  FRenaming := True;
  tvServers.SetFocus;
  tvServers.Selected.EditText;
end;

function TfrmMain.ApplyRename(aTreeNode: TTreeNode; const aText: string): string;
var
  lNode: TRdcNode;
begin
  FRenaming := False;
  Result := Trim(aText);
  if Result = '' then
    Exit(aTreeNode.Text);
  lNode := TRdcNode(aTreeNode.Data);
  if lNode is TRdcServer then
  begin
    // Server: de weergavenaam wijzigt, de hostnaam (Name) niet.
    TRdcServer(lNode).DisplayName := Result;
    FPanes.UpdateCaption(TRdcServer(lNode));
  end
  else
    lNode.Name := Result;
  MarkModified(lNode);
  if lNode is TRdcFile then
    Result := FileDisplayText(TRdcFile(lNode));
  // De nieuwe tekst staat pas na het Edited-event in de boom; daarna opnieuw sorteren (en favorieten/recent bijwerken).
  TThread.ForceQueue(nil, RefreshAfterRename);
end;

procedure TfrmMain.DeleteSelectedNode;
var
  lMessage: string;
  lNode: TRdcNode;
  lServer: TRdcNode;
  lServers: TList<TRdcNode>;
  lTreeNode: TTreeNode;
begin
  // Favoriet/recent item: alleen uit die lijst halen, nooit de server zelf verwijderen.
  if (SelectedShortcut <> nil) and (SelectedShortcut.Kind in [tskFavorite, tskRecent]) then
  begin
    RemoveSelectedShortcut;
    Exit;
  end;
  lNode := SelectedNode;
  if (lNode = nil) or (lNode is TRdcFile) then
    Exit;
  lServers := TList<TRdcNode>.Create;
  try
    if lNode is TRdcGroup then
    begin
      TRdcGroup(lNode).CollectServers(lServers);
      lMessage := Format(_('Groep "%s" met %d server(s) verwijderen?'), [lNode.Caption, lServers.Count]);
    end
    else
    begin
      lServers.Add(lNode);
      lMessage := Format(_('Server "%s" verwijderen?'), [lNode.Caption]);
    end;
    if MessageDlg(lMessage, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
    for lServer in lServers do
      CloseServerTab(TRdcServer(lServer));
  finally
    lServers.Free;
  end;
  FShortcuts.NodeRemoved(lNode);
  lTreeNode := FTreeNodes[lNode];
  RemoveTreeMapping(lNode);
  lTreeNode.Delete;
  MarkModified(lNode.Parent);
  lNode.Parent.Delete(lNode);
  StoreShortcuts;
  RebuildShortcutNodes;
end;

procedure TfrmMain.EditProfilesOfSelectedFile;
var
  lFile: TRdcFile;
begin
  lFile := SelectedFile;
  if (lFile <> nil) and TfrmProfiles.Execute(lFile) then
    MarkModified(lFile);
end;

function TfrmMain.IdInOtherFile(aFile: TRdcFile; const aId: string): Boolean;
var
  lFile: TRdcFile;
begin
  // Zelfde netwerk/gateway (id) in een ander open bestand (bijv. een kopie): dan de geheimen laten staan.
  for lFile in FFiles do
    if (lFile <> aFile) and ((lFile.FindTailnet(aId) <> nil) or (lFile.FindGateway(aId) <> nil)) then
      Exit(True);
  Result := False;
end;

procedure TfrmMain.EditTailnetsOfSelectedFile;
var
  lFile: TRdcFile;
begin
  lFile := SelectedFile;
  if lFile = nil then
    Exit;
  if TfrmTailnets.Execute(lFile, Self, FTailnetManager, FAppSettings,
    function(aId: string): Boolean
    begin
      Result := IdInOtherFile(lFile, aId);
    end) then
    MarkModified(lFile);
  UpdateVaultStatus;
end;

procedure TfrmMain.EditGatewaysOfSelectedFile;
var
  lFile: TRdcFile;
begin
  lFile := SelectedFile;
  if lFile = nil then
    Exit;
  if TfrmGateways.Execute(lFile, Self,
    function(aId: string): Boolean
    begin
      Result := IdInOtherFile(lFile, aId);
    end) then
    MarkModified(lFile);
  UpdateVaultStatus;
end;

function TfrmMain.CanStoreSecrets: Boolean;
begin
  Result := FAppSettings.RememberPasswords and FVault.IsInitialized;
end;

function TfrmMain.HasSecret(const aTarget: string): Boolean;
begin
  Result := FVault.HasPassword(aTarget);
end;

function TfrmMain.LoadSecret(const aTarget, aReason: string; out aSecret: string): Boolean;
begin
  aSecret := '';
  Result := FVault.HasPassword(aTarget) and EnsureVaultUnlocked(aReason) and FVault.TryLoad(aTarget, aSecret);
end;

function TfrmMain.SaveSecret(const aTarget, aAccount, aSecret, aReason: string): Boolean;
begin
  Result := CanStoreSecrets and EnsureVaultUnlocked(aReason) and FVault.Save(aTarget, aAccount, aSecret);
  if Result then
    TRdcLog.Write('Geheim opgeslagen in de kluis: ' + aTarget);
end;

procedure TfrmMain.DeleteSecret(const aTarget: string);
begin
  if FVault.HasPassword(aTarget) then
  begin
    FVault.Delete(aTarget);
    TRdcLog.Write('Geheim verwijderd uit de kluis: ' + aTarget);
  end;
end;

procedure TfrmMain.DeleteSecretsWithPrefix(const aPrefix: string);
begin
  FVault.DeleteByPrefix(aPrefix);
  TRdcLog.Write('Geheimen verwijderd uit de kluis: ' + aPrefix + '*');
end;

procedure TfrmMain.WakeSelectedServer;
var
  lServer: TRdcServer;
begin
  lServer := SelectedServer;
  if (lServer = nil) or lServer.Settings.Host.Inherit then
    Exit;
  try
    TRdcWakeOnLan.Send(lServer.Settings.Host.MacAddress, lServer.Settings.Host.WolBroadcast, lServer.Settings.Host.WolPort);
    sbStatus.Panels[0].Text := Format(_('Wake-on-LAN verstuurd naar %s (%s via %s)'), [lServer.Caption, lServer.Settings.Host.MacAddress, lServer.Settings.Host.WolBroadcast]);
  except
    on E: Exception do
      MessageDlg(Format(_('Wake-on-LAN naar %s mislukt: %s'), [lServer.Caption, E.Message]), mtError, [mbOK], 0);
  end;
end;

procedure TfrmMain.ApplyScaleToOpenSessions(aNode: TRdcNode);
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  // De schaal kan zonder opnieuw verbinden worden aangepast: geldt meteen voor open sessies onder deze node.
  lNodes := TList<TRdcNode>.Create;
  try
    if aNode is TRdcGroup then
      TRdcGroup(aNode).CollectServers(lNodes)
    else
      lNodes.Add(aNode);
    for lNode in lNodes do
      if (lNode is TRdcServer) and (FSessions.DesktopScaleOf(TRdcServer(lNode)) >= 0) and (FSessions.DesktopScaleOf(TRdcServer(lNode)) <> lNode.EffectiveExtras.DesktopScale) then
        FSessions.SetDesktopScale(TRdcServer(lNode), Cardinal(lNode.EffectiveExtras.DesktopScale));
  finally
    lNodes.Free;
  end;
  UpdateStatusBar;
end;

procedure TfrmMain.EditSelectedProperties;
var
  lNode: TRdcNode;
begin
  lNode := SelectedNode;
  if (lNode = nil) or not TfrmProperties.Execute(lNode, lNode.Parent) then
    Exit;
  MarkModified(lNode);
  UpdateNodeCaption(lNode);
  SortTree;
  ApplyScaleToOpenSessions(lNode);
end;

{ Boom: slepen }

procedure TfrmMain.SelectNodeForContextMenu(const aMousePos: TPoint);
var
  lHit: TTreeNode;
begin
  // Echt selecteren: met RightClickSelect markeert de VCL de node maar tijdelijk en voert het menu de actie
  // daarna uit op de vorige selectie (bijv. nieuwe server in de verkeerde groep, of de verkeerde node verwijderen).
  // MousePos (-1,-1) = contextmenu via het toetsenbord: dan geldt de huidige selectie.
  if (aMousePos.X = -1) and (aMousePos.Y = -1) then
    Exit;
  lHit := tvServers.GetNodeAt(aMousePos.X, aMousePos.Y);
  if lHit <> nil then
    tvServers.Selected := lHit;
end;

procedure TfrmMain.StartTreeDrag(aButton: TMouseButton; aShift: TShiftState; X, Y: Integer);
var
  lHit: TTreeNode;
begin
  // Handmatig slepen met drempel, zodat gewone klikken en dubbelklikken niet als slepen beginnen.
  if (aButton <> mbLeft) or (ssDouble in aShift) then
    Exit;
  lHit := tvServers.GetNodeAt(X, Y);
  // Bestanden en de items onder Favorieten/Recent worden niet gesleept.
  if (lHit <> nil) and (TObject(lHit.Data) is TRdcNode) and not (TObject(lHit.Data) is TRdcFile) then
    tvServers.BeginDrag(False, Mouse.DragThreshold);
end;

function TfrmMain.DropTarget(aDragged: TRdcNode; X, Y: Integer; out aTargetGroup: TRdcGroup; out aBefore: TRdcNode): Boolean;
var
  lHit: TTreeNode;
  lHitNode: TRdcNode;
begin
  Result := False;
  aTargetGroup := nil;
  aBefore := nil;
  lHit := tvServers.GetNodeAt(X, Y);
  if (lHit = nil) or (aDragged = nil) or (aDragged is TRdcFile) or not (TObject(lHit.Data) is TRdcNode) then
    Exit;
  lHitNode := TRdcNode(lHit.Data);
  if lHitNode = aDragged then
    Exit;
  if lHitNode is TRdcGroup then
    aTargetGroup := TRdcGroup(lHitNode)
  else
  begin
    // Neerzetten op een server: in dezelfde groep (in het bestand vóór die server).
    aTargetGroup := lHitNode.Parent;
    aBefore := lHitNode;
  end;
  if aTargetGroup = nil then
    Exit;
  if (aDragged is TRdcGroup) and ((aTargetGroup = aDragged) or aTargetGroup.IsDescendantOf(TRdcGroup(aDragged))) then
    Exit;
  Result := True;
end;

function TfrmMain.CanDropAt(aSource: TObject; X, Y: Integer): Boolean;
var
  lBefore: TRdcNode;
  lGroup: TRdcGroup;
begin
  Result := (aSource = tvServers) and DropTarget(SelectedNode, X, Y, lGroup, lBefore);
end;

procedure TfrmMain.DropSelectedNodeAt(X, Y: Integer);
var
  lBefore: TRdcNode;
  lDragged: TRdcNode;
  lDraggedTree: TTreeNode;
  lGroup: TRdcGroup;
  lTargetTree: TTreeNode;
begin
  lDragged := SelectedNode;
  if not DropTarget(lDragged, X, Y, lGroup, lBefore) then
    Exit;
  lDraggedTree := FTreeNodes[lDragged];
  MarkModified(lDragged); // bronbestand

  // Model: eerst uit de oude groep halen, dan de index in de doelgroep bepalen.
  lDragged.Parent.Extract(lDragged);
  if lBefore <> nil then
  begin
    lGroup.Insert(lGroup.IndexOf(lBefore), lDragged);
    lTargetTree := FTreeNodes[lBefore];
    lDraggedTree.MoveTo(lTargetTree, naInsert);
  end
  else
  begin
    lGroup.Add(lDragged);
    lTargetTree := FTreeNodes[lGroup];
    lDraggedTree.MoveTo(lTargetTree, naAddChild);
    lTargetTree.Expand(False);
  end;
  MarkModified(lDragged); // doelbestand
  SortTree;
  RebuildShortcutNodes;
  lDraggedTree.Selected := True;
end;

{ Bestanden }

function TfrmMain.FileDisplayText(aFile: TRdcFile): string;
begin
  Result := aFile.Caption;
  if aFile.Modified then
    Result := Result + ' *';
end;

procedure TfrmMain.UpdateFileNodeText(aFile: TRdcFile);
var
  lTreeNode: TTreeNode;
begin
  if FTreeNodes.TryGetValue(aFile, lTreeNode) then
    lTreeNode.Text := FileDisplayText(aFile);
end;

procedure TfrmMain.MarkModified(aNode: TRdcNode);
var
  lFile: TRdcFile;
begin
  if aNode = nil then
    Exit;
  lFile := aNode.RdcFile;
  if lFile = nil then
    Exit;
  lFile.Modified := True;
  UpdateFileNodeText(lFile);
  ScheduleAutoSave;
  UpdatePingTargets; // instelling, hostnaam of route kan gewijzigd zijn
end;

procedure TfrmMain.AutoSaveTimerFired(Sender: TObject);
begin
  AutoSaveModifiedFiles;
end;

procedure TfrmMain.ScheduleAutoSave;
begin
  // Na een korte rustpauze opslaan, zodat een reeks wijzigingen (slepen, hernoemen) één keer wordt weggeschreven.
  if not FAppSettings.AutoSave then
    Exit;
  FAutoSaveTimer.Enabled := False;
  FAutoSaveTimer.Enabled := True;
end;

procedure TfrmMain.AutoSaveModifiedFiles;
var
  lFile: TRdcFile;
begin
  FAutoSaveTimer.Enabled := False;
  // Niet tijdens het hernoemen in de boom (de wijziging is dan nog niet compleet); straks opnieuw.
  if tvServers.IsEditing then
  begin
    ScheduleAutoSave;
    Exit;
  end;
  // Alleen bestanden met een naam: een nieuw bestand krijgt pas bij "Opslaan als" (of bij sluiten) een naam.
  for lFile in FFiles.ToArray do
    if lFile.Modified and (lFile.FileName <> '') then
      SaveFile(lFile, False);
end;

function TfrmMain.SelectedFile: TRdcFile;
begin
  if SelectedNode <> nil then
    Result := SelectedNode.RdcFile
  else if FFiles.Count = 1 then
    Result := FFiles[0]
  else
    Result := nil;
end;

procedure TfrmMain.AddFile(aFile: TRdcFile);
begin
  FFiles.Add(aFile);
  FShortcuts.FileOpened(aFile);
  AddTreeNode(nil, aFile);
  RebuildShortcutNodes;
  SelectNode(aFile);
  UpdatePingTargets;
end;

procedure TfrmMain.NewFile;
begin
  AddFile(TRdcFile.Create(_('Nieuw bestand')));
end;

procedure TfrmMain.CloseUntouchedNewFiles;
var
  lIndex: Integer;
begin
  // Een leeg, nooit gewijzigd en nooit opgeslagen "Nieuw bestand" heeft geen waarde meer zodra er een echt bestand opengaat.
  for lIndex := FFiles.Count - 1 downto 0 do
    if (FFiles[lIndex].FileName = '') and not FFiles[lIndex].Modified and (FFiles[lIndex].Count = 0) and (FFiles[lIndex].Profiles.Count = 0) then
      CloseFile(FFiles[lIndex], False);
end;

function TfrmMain.OpenFile(const aFileName: string; aQuiet: Boolean): TRdcFile;
var
  lFile: TRdcFile;
begin
  Result := nil;
  for lFile in FFiles do
    if SameFileName(lFile.FileName, aFileName) then
    begin
      SelectNode(lFile);
      Exit(lFile);
    end;
  if not FileExists(aFileName) then
  begin
    if not aQuiet then
      MessageDlg(Format(_('Het bestand "%s" bestaat niet (meer).'), [aFileName]), mtWarning, [mbOK], 0);
    Exit;
  end;
  try
    Result := TRdcStorage.Load(aFileName);
  except
    on E: Exception do
    begin
      MessageDlg(Format(_('Kan "%s" niet openen:'#13#10#13#10'%s'), [aFileName, E.Message]), mtError, [mbOK], 0);
      Exit(nil);
    end;
  end;
  CloseUntouchedNewFiles;
  AddFile(Result);
  FAppSettings.AddRecent(aFileName);
  UpdateRecentMenu;
  ShowLoadWarnings(Result);
end;

procedure TfrmMain.ShowLoadWarnings(aFile: TRdcFile);
const
  cMaxShown = 15;
var
  lWarnings: string;
begin
  if aFile.Warnings.Count = 0 then
    Exit;
  lWarnings := aFile.Warnings.Text;
  if aFile.Warnings.Count > cMaxShown then
    lWarnings := string.Join(sLineBreak, Copy(aFile.Warnings.ToStringArray, 0, cMaxShown)) + sLineBreak + Format(_('... en nog %d melding(en).'), [aFile.Warnings.Count - cMaxShown]);
  MessageDlg(Format(_('Meldingen bij het openen van "%s":'#13#10#13#10'%s'), [ExtractFileName(aFile.FileName), lWarnings]), mtInformation, [mbOK], 0);
end;

procedure TfrmMain.OpenFilesWithDialog;
var
  lFileName: string;
begin
  if not dlgOpen.Execute(Handle) then
    Exit;
  for lFileName in dlgOpen.Files do
    OpenFile(lFileName);
end;

procedure TfrmMain.OpenRecentFile(aIndex: Integer);
begin
  if (aIndex >= 0) and (aIndex < FAppSettings.RecentFiles.Count) then
    OpenFile(FAppSettings.RecentFiles[aIndex]);
end;

function TfrmMain.ExternalChangePrompt(aFile: TRdcFile): TRdcExternalChangeAction;
const
  cReload = 100;
  cOverwrite = 101;
var
  lButton: TTaskDialogBaseButtonItem;
  lDialog: TTaskDialog;
begin
  lDialog := TTaskDialog.Create(nil);
  try
    lDialog.Caption := _('Bestand gewijzigd');
    lDialog.Title := _('Het bestand is buiten RDCManX gewijzigd');
    lDialog.Text := Format(_('"%s" is gewijzigd sinds het werd geopend (bijvoorbeeld in RDCMan).'), [aFile.FileName]);
    lDialog.MainIcon := tdiWarning;
    lDialog.CommonButtons := [];
    lDialog.Flags := [tfAllowDialogCancellation];
    lButton := lDialog.Buttons.Add;
    lButton.Caption := _('Herladen (mijn wijzigingen vervallen)');
    lButton.ModalResult := cReload;
    lButton := lDialog.Buttons.Add;
    lButton.Caption := _('Overschrijven');
    lButton.ModalResult := cOverwrite;
    lButton := lDialog.Buttons.Add;
    lButton.Caption := _('Annuleren');
    lButton.ModalResult := mrCancel;
    if not lDialog.Execute(Handle) then
      Exit(ecaCancel);
    case lDialog.ModalResult of
      cReload:
        Result := ecaReload;
      cOverwrite:
        Result := ecaOverwrite;
    else
      Result := ecaCancel;
    end;
  finally
    lDialog.Free;
  end;
end;

function TfrmMain.SaveFile(aFile: TRdcFile; aSaveAs: Boolean): Boolean;
var
  lFileName: string;
  lResult: TRdcSaveResult;
begin
  Result := False;
  lFileName := aFile.FileName;
  if aSaveAs or (lFileName = '') then
  begin
    if lFileName <> '' then
      dlgSave.FileName := ChangeFileExt(ExtractFileName(lFileName), '')
    else
      dlgSave.FileName := aFile.Caption;
    // Nieuw bestand: standaard .rdcx (gebruikerswens); een bestaand bestand houdt zijn eigen formaat.
    if (lFileName = '') or (aFile.Format = ffRdcx) then
    begin
      dlgSave.FilterIndex := 2;
      dlgSave.DefaultExt := 'rdcx';
    end
    else
    begin
      dlgSave.FilterIndex := 1;
      dlgSave.DefaultExt := 'rdg';
    end;
    if not dlgSave.Execute(Handle) then
      Exit;
    lFileName := dlgSave.FileName;
    if ExtractFileExt(lFileName) = '' then
    begin
      if dlgSave.FilterIndex = 2 then
        lFileName := lFileName + '.rdcx'
      else
        lFileName := lFileName + '.rdg';
    end;
  end;
  try
    lResult := TRdcStorage.Save(aFile, lFileName, ExternalChangePrompt);
  except
    on E: Exception do
    begin
      MessageDlg(Format(_('Opslaan van "%s" mislukt:'#13#10#13#10'%s'), [lFileName, E.Message]), mtError, [mbOK], 0);
      Exit;
    end;
  end;
  case lResult of
    srSaved:
      begin
        UpdateFileNodeText(aFile);
        FAppSettings.AddRecent(aFile.FileName);
        UpdateRecentMenu;
        Result := True;
      end;
    srReloadRequested:
      ReloadFile(aFile);
  end;
end;

procedure TfrmMain.SaveSelectedFile(aSaveAs: Boolean);
begin
  if SelectedFile <> nil then
    SaveFile(SelectedFile, aSaveAs);
end;

procedure TfrmMain.SaveAllFiles;
var
  lFile: TRdcFile;
  lFiles: TArray<TRdcFile>;
begin
  lFiles := FFiles.ToArray;
  for lFile in lFiles do
    if lFile.Modified and not SaveFile(lFile, False) then
      Exit;
end;

function TfrmMain.ConfirmSaveFile(aFile: TRdcFile): Boolean;
begin
  Result := True;
  if not aFile.Modified then
    Exit;
  case MessageDlg(Format(_('Wijzigingen in "%s" opslaan?'), [aFile.Caption]), mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      Result := SaveFile(aFile, False);
    mrNo:
      Result := True;
  else
    Result := False;
  end;
end;

function TfrmMain.CloseFile(aFile: TRdcFile; aAskSave: Boolean): Boolean;
var
  lServer: TRdcNode;
  lServers: TList<TRdcNode>;
  lTreeNode: TTreeNode;
begin
  Result := False;
  if aAskSave and not ConfirmSaveFile(aFile) then
    Exit;
  // Open sessies van dit bestand sluiten (verbreken + tab weg).
  lServers := TList<TRdcNode>.Create;
  try
    aFile.CollectServers(lServers);
    for lServer in lServers do
      CloseServerTab(TRdcServer(lServer));
  finally
    lServers.Free;
  end;
  FShortcuts.FileClosing(aFile);
  StoreShortcuts;
  if FTreeNodes.TryGetValue(aFile, lTreeNode) then
  begin
    RemoveTreeMapping(aFile);
    lTreeNode.Delete;
  end;
  FCollapsedFiles.Remove(aFile);
  FFiles.Remove(aFile);
  RebuildShortcutNodes;
  UpdatePingTargets;
  Result := True;
end;

procedure TfrmMain.CloseSelectedFile;
begin
  if SelectedFile <> nil then
    CloseFile(SelectedFile, True);
end;

procedure TfrmMain.ReloadFile(aFile: TRdcFile);
var
  lFileName: string;
begin
  lFileName := aFile.FileName;
  if CloseFile(aFile, False) then
    OpenFile(lFileName);
end;

procedure TfrmMain.UpdateRecentMenu;
var
  lFileName: string;
  lIndex: Integer;
  lItem: TMenuItem;
begin
  miRecent.Clear;
  lIndex := 0;
  for lFileName in FAppSettings.RecentFiles do
  begin
    lItem := TMenuItem.Create(miRecent);
    Inc(lIndex);
    lItem.Caption := Format('&%d  %s', [lIndex mod 10, lFileName]);
    lItem.Tag := lIndex - 1;
    lItem.OnClick := RecentFileClick;
    miRecent.Add(lItem);
  end;
  miRecent.Enabled := miRecent.Count > 0;
end;

{ Sessies en tabs }

function TfrmMain.ActiveServer: TRdcServer;
begin
  Result := FPanes.ActiveServer;
end;

procedure TfrmMain.ActivateServerTab(aServer: TRdcServer);
begin
  FPanes.Activate(aServer);
  ShowActiveSession;
end;

procedure TfrmMain.ActiveTabChanged;
begin
  if (ActiveServer <> nil) and FSessions.IsDetached(ActiveServer) and not FSelectingFromTree then
    FocusDetachedSession(ActiveServer);
  ShowActiveSession;
  if not FSelectingFromTree then
    SelectNode(ActiveServer);
end;

procedure TfrmMain.CloseServerTab(aServer: TRdcServer);
begin
  DockServer(aServer);
  // Release verbreekt (indien nodig) en geeft de sessie daarna uitgesteld vrij.
  FSessions.Release(aServer);
  FPanes.Remove(aServer);
  UpdateNodeImage(aServer);
  ShowActiveSession;
end;

procedure TfrmMain.ShowActiveSession;
var
  lPane: Integer;
  lRects: TArray<TRect>;
  lServers: TArray<TRdcServer>;
begin
  // Per vak de geselecteerde sessie op de plek van dat vak; alle andere sessies verborgen.
  // Een losgemaakte sessie staat in zijn eigen venster; het vak toont dan alleen een melding.
  SetLength(lServers, FPanes.PaneCount);
  SetLength(lRects, FPanes.PaneCount);
  for lPane := 0 to FPanes.PaneCount - 1 do
  begin
    lServers[lPane] := FPanes.ServerOf(lPane);
    lRects[lPane] := FPanes.HostRect(lPane);
    if (lServers[lPane] <> nil) and FSessions.IsDetached(lServers[lPane]) then
    begin
      FPanes.SetPaneNote(lPane, Format(_('%s staat in een eigen venster.'#13#10#13#10'Klik op de tab om het venster te tonen, of kies "Terugzetten in hoofdvenster" in het tab-menu.'), [lServers[lPane].Caption]));
      lServers[lPane] := nil;
    end
    else
      FPanes.SetPaneNote(lPane, '');
  end;
  FSessions.ShowServers(lServers, lRects);
  UpdateStatusBar;
end;

procedure TfrmMain.UpdateTabImages;
begin
  FPanes.UpdateImages;
end;

function TfrmMain.TabImageFor(aServer: TRdcServer): Integer;
begin
  Result := NodeImageIndex(aServer);
end;

function TfrmMain.TabMenuServer: TRdcServer;
begin
  if (FPanes.MenuServer <> nil) and FPanes.Contains(FPanes.MenuServer) then
    Result := FPanes.MenuServer
  else
    Result := ActiveServer;
end;

procedure TfrmMain.MoveTabServerToOtherPane;
begin
  if TabMenuServer <> nil then
    FPanes.MoveToNextPane(TabMenuServer);
end;

procedure TfrmMain.PanesActiveChanged(aSender: TObject);
begin
  ActiveTabChanged;
end;

procedure TfrmMain.PanesCloseRequest(aSender: TObject; aServer: TRdcServer);
begin
  CloseServerTab(aServer);
end;

procedure TfrmMain.PanesLayoutChanged(aSender: TObject);
begin
  ShowActiveSession;
end;

procedure TfrmMain.SessionsActivated(aSender: TObject; aServer: TRdcServer);
begin
  FPanes.ActivatePaneOf(aServer);
end;

procedure TfrmMain.PlaceNewHost(aServer: TRdcServer; aHost: TControl);
var
  lPane: Integer;
begin
  // Een nieuwe sessie opent in het actieve vak (of in het vak waar zijn tab al staat): daar de beginresolutie op afstemmen.
  lPane := FPanes.PaneOf(aServer);
  if lPane < 0 then
    lPane := FPanes.ActivePane;
  aHost.BoundsRect := FPanes.HostRect(lPane);
end;

procedure TfrmMain.SetGrid(aColumns, aRows: Integer);
begin
  FPanes.SetGrid(aColumns, aRows);
  StoreGrid;
end;

procedure TfrmMain.ApplyGridPreset(aPresetTag: Integer);
begin
  // Tag van een indelingsactie = kolommen * 10 + rijen.
  SetGrid(aPresetTag div 10, aPresetTag mod 10);
end;

procedure TfrmMain.ChooseCustomGrid;
var
  lColumns: Integer;
  lRows: Integer;
  lValues: array of string;
begin
  lValues := [IntToStr(FPanes.Columns), IntToStr(FPanes.Rows)];
  if not InputQuery(_('Indeling sessievakken'), [Format(_('Kolommen (1-%d)'), [cRdcMaxColumns]), Format(_('Rijen (1-%d)'), [cRdcMaxRows])], lValues) then
    Exit;
  if not TryStrToInt(Trim(lValues[0]), lColumns) or not TryStrToInt(Trim(lValues[1]), lRows) or not InRange(lColumns, 1, cRdcMaxColumns) or not InRange(lRows, 1, cRdcMaxRows) then
  begin
    MessageDlg(Format(_('Kies 1 tot %d kolommen en 1 tot %d rijen.'), [cRdcMaxColumns, cRdcMaxRows]), mtWarning, [mbOK], 0);
    Exit;
  end;
  SetGrid(lColumns, lRows);
end;

procedure TfrmMain.EqualizeGrid;
begin
  FPanes.Equalize;
  StoreGrid;
end;

procedure TfrmMain.StoreGrid;
begin
  if (FPanes = nil) or (FAppSettings = nil) then
    Exit;
  FAppSettings.GridColumns := FPanes.Columns;
  FAppSettings.GridRows := FPanes.Rows;
  FAppSettings.ColumnRatios := FPanes.ColumnRatios;
  FAppSettings.RowRatios := FPanes.RowRatios;
end;

procedure TfrmMain.UpdateGridActions;
var
  lAction: TAction;
  lMatched: Boolean;
begin
  lMatched := False;
  for lAction in [actGrid11, actGrid21, actGrid31, actGrid41, actGrid12, actGrid22, actGrid32, actGrid42] do
  begin
    lAction.Checked := lAction.Tag = FPanes.Columns * 10 + FPanes.Rows;
    lMatched := lMatched or lAction.Checked;
  end;
  actGridCustom.Checked := not lMatched;
  actGridEqualize.Enabled := FPanes.IsSplit;
end;

procedure TfrmMain.SetTheme(aTheme: TRdcTheme);
begin
  FAppSettings.Theme := cRdcThemeNames[aTheme];
  FAppSettings.Save;
  SwitchThemeNowOrLater(aTheme, True);
end;

procedure TfrmMain.SystemThemeChanged;
begin
  // Windows wisselde tussen licht en donker; alleen relevant bij thema "Systeem".
  if RdcThemeFromName(FAppSettings.Theme) = rtSystem then
    SwitchThemeNowOrLater(rtSystem, False);
end;

procedure TfrmMain.SwitchThemeNowOrLater(aTheme: TRdcTheme; aAnnounce: Boolean);
begin
  // Een stijlwissel maakt alle vensters opnieuw aan; dat zou open RDP-sessies verbreken (zie RdcmX.UI.Theme).
  if FPanes.TabCount > 0 then
  begin
    if aAnnounce then
      MessageDlg(_('Het thema wordt toegepast bij de volgende start van het programma.'#13#10#13#10'Nu omschakelen zou de open sessies verbreken.'), mtInformation, [mbOK], 0);
    Exit;
  end;
  if ApplyTheme(aTheme) then
  begin
    FPanes.ApplyColors(RdcActiveStyleIsDark);
    RebuildImages;
    LayoutStatusBar;
  end;
end;

procedure TfrmMain.RestoreGrid;
begin
  FPanes.SetGrid(FAppSettings.GridColumns, FAppSettings.GridRows);
  FPanes.ColumnRatios := FAppSettings.ColumnRatios;
  FPanes.RowRatios := FAppSettings.RowRatios;
  FPanes.Layout;
end;

procedure TfrmMain.ReconnectTabServer;
begin
  if TabMenuServer <> nil then
    ConnectServer(TabMenuServer);
end;

procedure TfrmMain.DisconnectTabServer;
begin
  if TabMenuServer <> nil then
    FSessions.Disconnect(TabMenuServer);
end;

procedure TfrmMain.CloseTabServer;
begin
  if TabMenuServer <> nil then
    CloseServerTab(TabMenuServer);
end;

procedure TfrmMain.ConnectServer(aServer: TRdcServer);
begin
  // Al open: alleen de tab activeren.
  if FSessions.StateOf(aServer) <> rssDisconnected then
  begin
    ActivateServerTab(aServer);
    Exit;
  end;
  if FSessions.Connect(aServer) then
  begin
    ActivateServerTab(aServer);
    // Een hele groep verbinden vult de lijst Recent niet.
    if not FBatchActive then
    begin
      FShortcuts.AddRecent(aServer);
      StoreShortcuts;
      RebuildShortcutNodes;
    end;
    UpdateNodeImage(aServer);
  end;
end;

procedure TfrmMain.ConnectSelectedServer;
begin
  if SelectedServer <> nil then
    ConnectServer(SelectedServer);
end;

procedure TfrmMain.ConnectNodeAtCursor;
var
  lHit: TTreeNode;
  lPoint: TPoint;
begin
  lPoint := tvServers.ScreenToClient(Mouse.CursorPos);
  lHit := tvServers.GetNodeAt(lPoint.X, lPoint.Y);
  if NodeOfTreeNode(lHit) is TRdcServer then
    ConnectServer(TRdcServer(NodeOfTreeNode(lHit)));
end;

procedure TfrmMain.ShowTabOfSelectedServer;
var
  lServer: TRdcServer;
begin
  // Server met een open tab geselecteerd: die tab tonen (zonder de toetsenbordfocus uit de boom te halen).
  if (FPanes = nil) or (FSessions = nil) then
    Exit; // tijdens opbouwen/afbreken van het venster
  lServer := SelectedServer;
  if (lServer = nil) or not FPanes.Contains(lServer) or (lServer = ActiveServer) then
    Exit;
  FSelectingFromTree := True;
  try
    FPanes.Activate(lServer);
    ShowActiveSession;
  finally
    FSelectingFromTree := False;
  end;
end;

procedure TfrmMain.CloseTabAfterDisconnect(aServer: TRdcServer);
begin
  // Opnieuw controleren: intussen kan de tab al gesloten of de server opnieuw verbonden zijn.
  if FClosing or not FPanes.Contains(aServer) or not FSessions.EndedNormally(aServer) then
    Exit;
  sbStatus.Panels[0].Text := Format(_('Verbinding met %s verbroken (reden %d)%s'), [aServer.Caption, FSessions.LastDisconnectReasonOf(aServer), IfThen(FSessions.LastDisconnectTextOf(aServer) <> '', ': ' + FSessions.LastDisconnectTextOf(aServer), '.')]);
  CloseServerTab(aServer);
end;

procedure TfrmMain.DisconnectSelectedServer;
begin
  if SelectedServer <> nil then
    FSessions.Disconnect(SelectedServer);
end;

function TfrmMain.CredentialRequest(aServer: TRdcServer; const aContext: TRdcCredentialContext; var aUserName, aDomain: string; out aPassword: string; out aFromVault: Boolean): Boolean;
var
  lRemember: Boolean;
begin
  aFromVault := False;
  if FBatchActive then
  begin
    // Groep verbinden: de eenmalig gevraagde gegevens voor alle servers.
    aUserName := FBatchUserName;
    aDomain := FBatchDomain;
    aPassword := FBatchPassword;
    if FBatchRemember then
      RememberPassword(aServer, aContext, aUserName, aDomain, aPassword);
    Exit(True);
  end;
  // Remembered password for this account: without a prompt, but only for hosts approved for it (asked once per new
  // host). Declined: the normal prompt below.
  if FAppSettings.RememberPasswords and (LoadRememberedPassword(aServer, aContext, aUserName, aDomain, aPassword) = rlrLoaded) then
  begin
    aFromVault := True;
    Exit(True);
  end;
  // "Wachtwoord onthouden" staat nooit standaard aan: alleen onthouden als de gebruiker het zelf aanvinkt.
  lRemember := False;
  Result := TfrmCredentialPrompt.Execute(Format('%s (%s)', [aServer.Caption, aContext.HostText]), aUserName, aDomain, aPassword, FAppSettings.RememberPasswords, lRemember);
  if Result and lRemember then
    RememberPassword(aServer, aContext, aUserName, aDomain, aPassword);
end;

procedure TfrmMain.TailnetOptions(aDef: TRdcTailnetDef; out aMatchHostName, aAllowShared: Boolean);
var
  lKey: string;
begin
  // Client-side opt-ins (Tailscale networks dialog), bound to id + control URL like the tailnet's secrets.
  lKey := TRdcPasswordVault.TailnetBindingKey(aDef.Id, aDef.ControlUrl);
  aMatchHostName := FAppSettings.TailnetHostNameMatch.IndexOf(lKey) >= 0;
  aAllowShared := FAppSettings.TailnetAllowShared.IndexOf(lKey) >= 0;
end;

function TfrmMain.CredentialTargetFor(aServer: TRdcServer; const aUserName, aDomain: string): string;
var
  lDomain: string;
  lUserName: string;
begin
  // Zelfde splitsing als bij verbinden (DOMEIN\gebruiker, .\gebruiker, UPN), zodat de sleutel overeenkomt.
  TRdcCredentialsSettings.SplitLogon(aUserName, aDomain, lDomain, lUserName);
  Result := TRdcPasswordVault.TargetFor(aServer.Name, lDomain, lUserName);
end;

function TfrmMain.AccountText(const aUserName, aDomain: string): string;
var
  lDomain: string;
  lUserName: string;
begin
  TRdcCredentialsSettings.SplitLogon(aUserName, aDomain, lDomain, lUserName);
  if lDomain <> '' then
    Result := lDomain + '\' + lUserName
  else
    Result := lUserName;
end;

function TfrmMain.HasRememberedPassword(aServer: TRdcServer; const aUserName, aDomain: string): Boolean;
begin
  Result := FAppSettings.RememberPasswords and (Trim(aUserName) <> '') and FVault.HasPassword(CredentialTargetFor(aServer, aUserName, aDomain));
end;

function TfrmMain.LoadRememberedPassword(aServer: TRdcServer; const aContext: TRdcCredentialContext; const aUserName, aDomain: string; out aPassword: string): TRdcLoadResult;
var
  lAccount: string;
  lTarget: string;
begin
  aPassword := '';
  Result := rlrNone;
  if not HasRememberedPassword(aServer, aUserName, aDomain) then
    Exit;
  // The real host next to the caption: the caption comes from the file and can say anything.
  if not EnsureVaultUnlocked(Format(_('Ontgrendel de wachtwoordkluis om met %s (%s) te verbinden.'), [aServer.Caption, aContext.HostText])) then
    Exit;
  lTarget := CredentialTargetFor(aServer, aUserName, aDomain);
  lAccount := AccountText(aUserName, aDomain);
  Result := FVault.LoadApproved(lTarget, lAccount, aContext.Hosts,
    function(const aMissing: TArray<TRdcHostRef>): Boolean
    begin
      Result := ConfirmHostApproval(lAccount, aMissing);
    end, aPassword);
  if Result = rlrDeclined then
    TRdcLog.Write(Format('%s: onthouden wachtwoord niet gebruikt, host niet goedgekeurd (%s)', [aServer.Caption, lTarget]));
  if Result = rlrLoaded then
  begin
    FStoredPasswordUsed.AddOrSetValue(aServer, lTarget);
    TRdcLog.Write(Format('%s: onthouden wachtwoord gebruikt (%s)', [aServer.Caption, lTarget])); // doelnaam, nooit het wachtwoord
  end;
end;

procedure TfrmMain.RememberPassword(aServer: TRdcServer; const aContext: TRdcCredentialContext; const aUserName, aDomain, aPassword: string);
var
  lTarget: string;
begin
  if not FAppSettings.RememberPasswords or (Trim(aUserName) = '') or (aPassword = '') then
    Exit;
  if not EnsureVaultUnlocked(_('Ontgrendel de wachtwoordkluis om het wachtwoord te onthouden.')) then
  begin
    sbStatus.Panels[0].Text := _('Wachtwoord niet onthouden (kluis niet ontgrendeld).');
    Exit;
  end;
  lTarget := CredentialTargetFor(aServer, aUserName, aDomain);
  // The hosts of this connection are approved: the user typed the password for them.
  if FVault.SaveAccount(lTarget, AccountText(aUserName, aDomain), aPassword, aContext.Hosts) then
  begin
    FStoredPasswordUsed.AddOrSetValue(aServer, lTarget);
    TRdcLog.Write(Format('%s: wachtwoord onthouden (%s)', [aServer.Caption, lTarget]));
  end;
end;

function TfrmMain.ConfirmHostApproval(const aAccount: string; const aMissing: TArray<TRdcHostRef>): Boolean;
var
  lHost: TRdcHostRef;
  lList: string;
begin
  lList := '';
  for lHost in aMissing do
    lList := lList + #13#10'  - ' + lHost.Display;
  // Default No: a file can name any host for a remembered account.
  Result := MessageDlg(Format(_('Onthouden wachtwoord voor %s gebruiken op:%s'#13#10#13#10'Dit wachtwoord is nog niet voor deze host(s) gebruikt. Kies alleen Ja als u ze vertrouwt; het antwoord wordt onthouden. Bij Nee typt u het wachtwoord zelf in.'), [aAccount, lList]), mtConfirmation, [mbYes, mbNo], 0, mbNo) = mrYes;
end;

function TfrmMain.ApproveGroupHosts(const aServers: TArray<TRdcServer>; const aUserName, aDomain: string): Boolean;
var
  lAccount: string;
  lHost: TRdcHostRef;
  lMissing: TArray<TRdcHostRef>;
  lServer: TRdcServer;
  lTarget: string;

  function Listed(const aKey: string): Boolean;
  var
    lItem: TRdcHostRef;
  begin
    for lItem in lMissing do
      if SameText(lItem.Key, aKey) then
        Exit(True);
    Result := False;
  end;

begin
  // Group connect with a remembered password: one question for all hosts of this account that are not approved yet,
  // instead of one per server. Servers with another account ask for themselves.
  Result := False;
  lTarget := CredentialTargetFor(aServers[0], aUserName, aDomain);
  lAccount := AccountText(aUserName, aDomain);
  if not EnsureVaultUnlocked(Format(_('Ontgrendel de wachtwoordkluis om met %d servers te verbinden.'), [Length(aServers)])) then
    Exit;
  lMissing := [];
  for lServer in aServers do
    if SameText(CredentialTargetFor(lServer, aUserName, aDomain), lTarget) then
      for lHost in FVault.MissingHosts(lTarget, FSessions.CredentialContextFor(lServer).Hosts) do
        if not Listed(lHost.Key) then
          lMissing := lMissing + [lHost];
  if Length(lMissing) = 0 then
    Exit(True);
  Result := ConfirmHostApproval(lAccount, lMissing) and FVault.ApproveHosts(lTarget, lAccount, lMissing);
end;

procedure TfrmMain.ForgetSelectedPassword;
var
  lDomain: string;
  lUserName: string;
begin
  if (SelectedServer = nil) or not SelectedServer.ResolveLogon(lDomain, lUserName) then
    Exit;
  FVault.Delete(CredentialTargetFor(SelectedServer, lUserName, lDomain));
  sbStatus.Panels[0].Text := Format(_('Onthouden wachtwoord vergeten voor %s'), [AccountText(lUserName, lDomain)]);
end;

procedure TfrmMain.HandleRejectedPassword(aServer: TRdcServer);
const
  // discReason bij geweigerde aanmeldgegevens. ONZEKER: 2055 = aanmelding mislukt, 2567 = gebruiker onbekend
  // (de meest voorkomende); andere codes laten het onthouden wachtwoord staan.
  cRejectedReasons: array[0..1] of Integer = (2055, 2567);
var
  lReason: Integer;
  lRejected: Boolean;
  lTarget: string;
begin
  if not FStoredPasswordUsed.TryGetValue(aServer, lTarget) then
    Exit;
  case FSessions.StateOf(aServer) of
    rssLoggedIn:
      FStoredPasswordUsed.Remove(aServer); // werkte: niets meer te doen
    rssDisconnected:
      begin
        lRejected := False;
        for lReason in cRejectedReasons do
          lRejected := lRejected or (FSessions.LastDisconnectReasonOf(aServer) = lReason);
        FStoredPasswordUsed.Remove(aServer);
        if lRejected then
        begin
          FVault.Delete(lTarget);
          TRdcLog.Write(Format('%s: onthouden wachtwoord geweigerd en vergeten (%s)', [aServer.Caption, lTarget]));
          sbStatus.Panels[0].Text := Format(_('%s: aanmelding geweigerd; het onthouden wachtwoord is vergeten.'), [aServer.Caption]);
        end;
      end;
  end;
end;

function TfrmMain.ConfirmForgetAllPasswords: Boolean;
var
  lCount: Integer;
begin
  // Uitzetten = kluis en alle onthouden wachtwoorden wissen (na bevestiging); annuleren laat de optie aan.
  lCount := FVault.Count;
  if (lCount = 0) and not FVault.IsInitialized then
    Exit(True);
  Result := MessageDlg(Format(_('Onthouden van wachtwoorden uitzetten?'#13#10#13#10'De wachtwoordkluis en %d onthouden wachtwoord(en) worden verwijderd.'), [lCount]), mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  if Result then
    FVault.Reset;
end;

function TfrmMain.CreateVault: Boolean;
var
  lOld: string;
  lPassword: string;
begin
  Result := False;
  if TfrmMasterPassword.Execute(mpmCreate, _('Stel een hoofdwachtwoord in voor de wachtwoordkluis. Onthouden wachtwoorden worden daarmee versleuteld.'), lPassword, lOld) = mprOk then
    Result := FVault.Initialize(lPassword);
  WipeString(lPassword);
  WipeString(lOld);
end;

function TfrmMain.EnsureVaultUnlocked(const aReason: string): Boolean;
var
  lOld: string;
  lOk: Boolean;
  lPassword: string;
begin
  Result := False;
  if not FAppSettings.RememberPasswords or not FVault.IsInitialized then
    Exit;
  if FVault.IsUnlocked then
    Exit(True);
  repeat
    case TfrmMasterPassword.Execute(mpmUnlock, aReason, lPassword, lOld) of
      mprOk:
        begin
          lOk := FVault.Unlock(lPassword);
          WipeString(lPassword);
          if lOk then
          begin
            UpdateVaultStatus;
            Exit(True);
          end;
          MessageDlg(_('Onjuist hoofdwachtwoord.'), mtWarning, [mbOK], 0);
        end;
      mprForgot:
        begin
          ResetVaultAfterForgotten;
          Exit(False);
        end;
    else
      Exit(False);
    end;
  until False;
end;

procedure TfrmMain.ResetVaultAfterForgotten;
begin
  // Het hoofdwachtwoord is niet te herstellen: alleen leegmaken en opnieuw beginnen.
  if MessageDlg(Format(_('Hoofdwachtwoord vergeten?'#13#10#13#10'De kluis kan niet geopend worden zonder het hoofdwachtwoord. De %d onthouden wachtwoord(en) worden verwijderd; daarna stelt u een nieuw hoofdwachtwoord in.'), [FVault.Count]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  FVault.Reset;
  if not CreateVault then
  begin
    // Geen nieuwe kluis: onthouden uitzetten, anders staat de optie aan zonder kluis.
    FAppSettings.RememberPasswords := False;
    FAppSettings.Save;
  end;
  UpdateVaultStatus;
end;

procedure TfrmMain.LockVault;
begin
  FVault.Lock;
  UpdateVaultStatus;
  sbStatus.Panels[0].Text := _('Wachtwoordkluis vergrendeld.');
end;

procedure TfrmMain.ChangeMasterPassword;
var
  lNew: string;
  lOld: string;
begin
  if TfrmMasterPassword.Execute(mpmChange, _('Wijzig het hoofdwachtwoord van de wachtwoordkluis.'), lNew, lOld) <> mprOk then
    Exit;
  try
    if FVault.ChangeMasterPassword(lOld, lNew) then
      sbStatus.Panels[0].Text := _('Hoofdwachtwoord gewijzigd; alle onthouden wachtwoorden zijn opnieuw versleuteld.')
    else
      MessageDlg(_('Het huidige hoofdwachtwoord is onjuist; er is niets gewijzigd.'), mtWarning, [mbOK], 0);
  finally
    WipeString(lNew);
    WipeString(lOld);
  end;
  UpdateVaultStatus;
end;

procedure TfrmMain.VaultTimerFired(Sender: TObject);
begin
  AutoLockVault;
end;

procedure TfrmMain.AutoLockVault;
begin
  // Automatisch vergrendelen na de ingestelde tijd zonder gebruik (0 = nooit).
  if FVault.IsUnlocked and (FAppSettings.AutoLockMinutes > 0) and (MinutesBetween(Now, FVault.LastUse) >= FAppSettings.AutoLockMinutes) then
  begin
    FVault.Lock;
    UpdateVaultStatus;
    TRdcLog.Write('Wachtwoordkluis automatisch vergrendeld');
  end;
end;

procedure TfrmMain.DropLegacyPasswords;
begin
  // Optie aan maar nog geen kluis (onthouden van voor de hoofdwachtwoord-kluis): die items wissen en de optie
  // uitzetten; de gebruiker zet hem bewust weer aan en stelt dan een hoofdwachtwoord in.
  if FAppSettings.RememberPasswords and not FVault.IsInitialized then
  begin
    FVault.Reset;
    FAppSettings.RememberPasswords := False;
    FAppSettings.Save;
    TRdcLog.Write('Onthouden wachtwoorden zonder kluis gewist; optie uitgezet');
  end
  else if not FAppSettings.RememberPasswords and FVault.IsInitialized then
  begin
    // Optie uit maar de kluis bestaat nog: dat kan alleen doordat een andere (oudere) sessie de instelling
    // overschreef, want uitzetten wist de kluis altijd. Optie weer aanzetten, anders zijn de geheimen onbereikbaar.
    FAppSettings.RememberPasswords := True;
    FAppSettings.Save;
    TRdcLog.Write('Kluis aanwezig terwijl "Wachtwoorden onthouden" uit stond: optie hersteld');
  end;
end;

procedure TfrmMain.UpdateVaultStatus;
begin
  actLockVault.Enabled := FVault.IsUnlocked;
end;

function TfrmMain.SelectedGroupServers: TArray<TRdcServer>;
var
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
begin
  Result := [];
  if not (SelectedNode is TRdcGroup) then
    Exit;
  lNodes := TList<TRdcNode>.Create;
  try
    TRdcGroup(SelectedNode).CollectServers(lNodes);
    for lNode in lNodes do
      Result := Result + [TRdcServer(lNode)];
  finally
    lNodes.Free;
  end;
end;

procedure TfrmMain.ConnectSelectedGroup;
const
  cConfirmAbove = 10;
var
  lDomain: string;
  lGroup: TRdcNode;
  lIndex: Integer;
  lPane: Integer;
  lServers: TArray<TRdcServer>;
  lUserName: string;
begin
  lGroup := SelectedNode;
  lServers := SelectedGroupServers;
  if Length(lServers) = 0 then
    Exit;
  if (Length(lServers) > cConfirmAbove) and (MessageDlg(Format(_('%d servers in "%s" verbinden?'), [Length(lServers), lGroup.Caption]), mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then
    Exit;
  // Eén keer vragen, met de aanmeldnaam van de eerste server als voorstel. Is er een onthouden wachtwoord voor dat
  // account, dan niet vragen: elke server haalt dan zelf zijn onthouden wachtwoord op (of vraagt het).
  lServers[0].ResolveLogon(lDomain, lUserName);
  FBatchUserName := lUserName;
  FBatchDomain := lDomain;
  FBatchRemember := False; // nooit standaard onthouden
  // Declined hosts: the normal group prompt below (one typed password for all).
  if HasRememberedPassword(lServers[0], lUserName, lDomain) and ApproveGroupHosts(lServers, lUserName, lDomain) then
  begin
    for lIndex := 0 to High(lServers) do
      ConnectServer(lServers[lIndex]);
    ShowActiveSession;
    Exit;
  end;
  if not TfrmCredentialPrompt.Execute(Format(_('%d servers in "%s"'), [Length(lServers), lGroup.Caption]), FBatchUserName, FBatchDomain, FBatchPassword, FAppSettings.RememberPasswords, FBatchRemember) then
    Exit;
  FBatchActive := True;
  try
    // Verdelen over de vakken, te beginnen bij het actieve vak; open sessies alleen tonen.
    lPane := FPanes.ActivePane;
    for lIndex := 0 to High(lServers) do
    begin
      if FSessions.StateOf(lServers[lIndex]) = rssDisconnected then
      begin
        FPanes.SelectPane(lPane);
        lPane := (lPane + 1) mod FPanes.PaneCount;
      end;
      ConnectServer(lServers[lIndex]);
    end;
  finally
    FBatchActive := False;
    FBatchRemember := False;
    WipeString(FBatchPassword);
  end;
  ShowActiveSession;
end;

{ Schaal }

procedure TfrmMain.SetTabServerScale(aPercent: Integer);
begin
  // Alleen voor deze open sessie; blijvend instellen kan per server/groep in Eigenschappen > Dynamische resolutie.
  if TabMenuServer = nil then
    Exit;
  FSessions.SetDesktopScale(TabMenuServer, Cardinal(aPercent));
  UpdateStatusBar;
end;

procedure TfrmMain.UpdateScaleMenu;
var
  lCurrent: Integer;
  lIndex: Integer;
begin
  lCurrent := FSessions.DesktopScaleOf(TabMenuServer);
  pmtScale.Enabled := lCurrent >= 0;
  for lIndex := 0 to pmtScale.Count - 1 do
    pmtScale.Items[lIndex].Checked := pmtScale.Items[lIndex].Tag = lCurrent;
end;

{ Losmaken }

function TfrmMain.SessionWindowOf(aServer: TRdcServer): TfrmSessionWindow;
begin
  if (aServer = nil) or not FSessionWindows.TryGetValue(aServer, Result) then
    Result := nil;
end;

procedure TfrmMain.DetachServer(aServer: TRdcServer; aFullScreen: Boolean);
var
  lArea: TRect;
  lNew: TfrmSessionWindow;
  lOld: TfrmSessionWindow;
begin
  if (aServer = nil) or (FSessions.Find(aServer) = nil) then
    Exit;
  lOld := SessionWindowOf(aServer);
  if (lOld <> nil) and (lOld.FullScreen = aFullScreen) then
  begin
    FocusDetachedSession(aServer);
    Exit;
  end;
  // Venster/volledig scherm op de monitor waar de sessie nu staat.
  if lOld <> nil then
  begin
    if aFullScreen then
      lArea := lOld.Monitor.BoundsRect
    else
      lArea := lOld.Monitor.WorkareaRect;
  end
  else if aFullScreen then
    lArea := Monitor.BoundsRect
  else
    lArea := Monitor.WorkareaRect;
  TRdcLog.Write(Format('%s: losmaken naar %s', [aServer.Caption, IfThen(aFullScreen, 'volledig scherm', 'eigen venster')]));
  lNew := TfrmSessionWindow.CreateFor(aServer, aFullScreen, lArea);
  lNew.OnActivated := SessionWindowActivated;
  lNew.OnDockRequest := SessionWindowDockRequest;
  lNew.OnFullScreenToggle := SessionWindowFullScreenToggle;
  lNew.OnHostAreaResized := SessionWindowHostResized;
  // Eerst de sessie in het (nog onzichtbare) venster zetten en op maat brengen, dan pas tonen: geen leeg
  // venster dat daarna nog verspringt.
  lNew.HandleNeeded;
  FSessions.Detach(aServer, lNew.HostParentHandle);
  FSessions.PlaceDetached(aServer, lNew.HostRect);
  FSessionWindows.AddOrSetValue(aServer, lNew);
  lNew.Show;
  // Het oude venster pas opruimen nu de host eruit is (en niet binnen zijn eigen event: Release).
  if lOld <> nil then
    lOld.Release;
  ShowActiveSession;
  FocusDetachedSession(aServer);
end;

procedure TfrmMain.DockServer(aServer: TRdcServer);
var
  lWindow: TfrmSessionWindow;
begin
  lWindow := SessionWindowOf(aServer);
  if lWindow = nil then
    Exit;
  TRdcLog.Write(Format('%s: terugzetten in het hoofdvenster', [aServer.Caption]));
  FSessions.Reattach(aServer);
  FSessionWindows.Remove(aServer);
  lWindow.OnActivated := nil;
  lWindow.OnDockRequest := nil;
  lWindow.OnFullScreenToggle := nil;
  lWindow.OnHostAreaResized := nil;
  lWindow.Release;
  ShowActiveSession;
end;

procedure TfrmMain.DockAllServers;
var
  lServer: TRdcServer;
begin
  if (FSessionWindows = nil) or (FSessions = nil) then
    Exit;
  for lServer in FSessionWindows.Keys.ToArray do
  begin
    FSessions.Reattach(lServer);
    FSessionWindows[lServer].Free;
    FSessionWindows.Remove(lServer);
  end;
end;

procedure TfrmMain.FocusDetachedSession(aServer: TRdcServer);
var
  lControl: HWND;
  lWindow: TfrmSessionWindow;
begin
  lWindow := SessionWindowOf(aServer);
  if lWindow = nil then
    Exit;
  if lWindow.WindowState = wsMinimized then
    lWindow.WindowState := wsNormal;
  lWindow.Show;
  SetForegroundWindow(lWindow.Handle);
  lControl := FSessions.ControlHandle(aServer);
  if lControl <> 0 then
    Winapi.Windows.SetFocus(lControl);
end;

procedure TfrmMain.SessionWindowActivated(aSender: TObject; aServer: TRdcServer);
var
  lControl: HWND;
begin
  // Toetsenbord naar de sessie, zodat typen direct in de remote sessie terechtkomt.
  lControl := FSessions.ControlHandle(aServer);
  if lControl <> 0 then
    Winapi.Windows.SetFocus(lControl);
end;

procedure TfrmMain.SessionWindowDockRequest(aSender: TObject; aServer: TRdcServer);
begin
  TRdcLog.Write(Format('%s: sessievenster vraagt terugzetten', [aServer.Caption]));
  DockServer(aServer);
end;

procedure TfrmMain.SessionWindowFullScreenToggle(aSender: TObject; aServer: TRdcServer);
begin
  TRdcLog.Write(Format('%s: sessievenster vraagt wissel venster/volledig scherm', [aServer.Caption]));
  DetachServer(aServer, not TfrmSessionWindow(aSender).FullScreen);
end;

procedure TfrmMain.SessionWindowHostResized(aSender: TObject; aServer: TRdcServer);
begin
  FSessions.PlaceDetached(aServer, TfrmSessionWindow(aSender).HostRect);
end;

procedure TfrmMain.DisconnectSelectedGroup;
var
  lServer: TRdcServer;
begin
  for lServer in SelectedGroupServers do
    FSessions.Disconnect(lServer);
end;

procedure TfrmMain.SessionsStateChanged(aSender: TObject; aServer: TRdcServer);
begin
  HandleRejectedPassword(aServer);
  UpdateNodeImage(aServer);
  UpdateTabImages;
  UpdateStatusBar;
  // Normaal verbroken (gebruiker, afgemeld, server): tab sluiten. Bij een fout blijft de tab staan met de melding.
  // Niet vanuit het RDP-event zelf sluiten (de sessie wordt dan vrijgegeven); via de message queue.
  if not FClosing and FSessions.EndedNormally(aServer) and FPanes.Contains(aServer) then
    TThread.ForceQueue(nil,
      procedure
      begin
        CloseTabAfterDisconnect(aServer);
      end);
  if FClosing and (FSessions.ActiveCount = 0) then
  begin
    FForceClose := True;
    // Niet sluiten vanuit een RDP-event; via de message queue.
    TThread.ForceQueue(nil, Close);
  end;
end;

procedure TfrmMain.SessionsDisplayChanged(aSender: TObject; aServer: TRdcServer);
begin
  if aServer = ActiveServer then
    UpdateStatusBar;
end;

procedure TfrmMain.UpdateActionStates;
var
  lNode: TRdcNode;
  lServer: TRdcServer;
  lState: TRdpSessionState;
  lTabServer: TRdcServer;
  lTabState: TRdpSessionState;
begin
  lNode := SelectedNode;
  lServer := SelectedServer;
  lState := FSessions.StateOf(lServer);
  actConnect.Enabled := lServer <> nil;
  if (lServer <> nil) and (lState <> rssDisconnected) then
    actConnect.Caption := _('Tonen'#9'Enter')
  else
    actConnect.Caption := _('Verbinden'#9'Enter');
  actDisconnect.Enabled := (lServer <> nil) and (lState in [rssConnecting, rssConnected, rssLoggedIn]);
  actNewServer.Enabled := TargetGroup <> nil;
  actNewGroup.Enabled := TargetGroup <> nil;
  actRename.Enabled := (lNode <> nil) and (SelectedShortcut = nil);
  actFavorite.Enabled := lServer <> nil;
  actForgetPassword.Visible := FAppSettings.RememberPasswords;
  actForgetPassword.Enabled := FAppSettings.RememberPasswords and (lServer <> nil);
  actLockVault.Visible := FAppSettings.RememberPasswords;
  actLockVault.Enabled := FVault.IsUnlocked;
  actChangeMasterPassword.Visible := FAppSettings.RememberPasswords;
  actChangeMasterPassword.Enabled := FAppSettings.RememberPasswords and FVault.IsInitialized;
  actConnectGroup.Enabled := lNode is TRdcGroup;
  actDisconnectGroup.Enabled := lNode is TRdcGroup;
  if FShortcuts.IsFavorite(lServer) then
    actFavorite.Caption := _('Uit favorieten verwijderen')
  else
    actFavorite.Caption := _('Aan favorieten toevoegen');
  actDelete.Enabled := (lNode <> nil) and not (lNode is TRdcFile);
  if (SelectedShortcut <> nil) and (SelectedShortcut.Kind = tskFavorite) then
    actDelete.Caption := _('Uit favorieten verwijderen'#9'Del')
  else if (SelectedShortcut <> nil) and (SelectedShortcut.Kind = tskRecent) then
    actDelete.Caption := _('Uit recent verwijderen'#9'Del')
  else
    actDelete.Caption := _('Verwijderen'#9'Del');
  actProperties.Enabled := lNode <> nil;
  actSave.Enabled := SelectedFile <> nil;
  actSaveAs.Enabled := SelectedFile <> nil;
  actCloseFile.Enabled := SelectedFile <> nil;
  actProfiles.Enabled := SelectedFile <> nil;
  actTailnets.Enabled := SelectedFile <> nil;
  actGateways.Enabled := SelectedFile <> nil;
  actWakeOnLan.Enabled := (lServer <> nil) and not lServer.Settings.Host.Inherit;
  actSaveAll.Enabled := FFiles.Count > 0;

  lTabServer := TabMenuServer;
  lTabState := FSessions.StateOf(lTabServer);
  actTabReconnect.Enabled := (lTabServer <> nil) and (lTabState = rssDisconnected);
  actTabDisconnect.Enabled := (lTabServer <> nil) and (lTabState in [rssConnecting, rssConnected, rssLoggedIn]);
  actTabClose.Enabled := lTabServer <> nil;
  actTabMoveToOtherPane.Enabled := (lTabServer <> nil) and FPanes.IsSplit;
  actTabDetach.Enabled := (lTabServer <> nil) and (FSessions.Find(lTabServer) <> nil) and ((SessionWindowOf(lTabServer) = nil) or SessionWindowOf(lTabServer).FullScreen);
  actTabFullScreen.Enabled := (lTabServer <> nil) and (FSessions.Find(lTabServer) <> nil) and ((SessionWindowOf(lTabServer) = nil) or not SessionWindowOf(lTabServer).FullScreen);
  actTabDock.Enabled := SessionWindowOf(lTabServer) <> nil;
  UpdateGridActions;
  actThemeSystem.Checked := RdcThemeFromName(FAppSettings.Theme) = rtSystem;
  actThemeLight.Checked := RdcThemeFromName(FAppSettings.Theme) = rtLight;
  actThemeDark.Checked := RdcThemeFromName(FAppSettings.Theme) = rtDark;
end;

function TfrmMain.AppVersionText: string;
var
  lHandle: DWORD;
  lInfo: Pointer;
  lFixed: PVSFixedFileInfo;
  lFixedSize: UINT;
  lSize: DWORD;
begin
  // Versie uit de versie-informatie van de exe (Project > Options > Version Info).
  Result := '';
  lSize := GetFileVersionInfoSize(PChar(ParamStr(0)), lHandle);
  if lSize = 0 then
    Exit;
  GetMem(lInfo, lSize);
  try
    if GetFileVersionInfo(PChar(ParamStr(0)), 0, lSize, lInfo) and VerQueryValue(lInfo, '\', Pointer(lFixed), lFixedSize) then
      // Versieschema yyyy.mm.dd.xxx (xxx = buildnummer van die dag), zie Tools\NextVersion.ps1.
      Result := Format(_('versie %d.%.2d.%.2d.%.3d'), [HiWord(lFixed.dwFileVersionMS), LoWord(lFixed.dwFileVersionMS), HiWord(lFixed.dwFileVersionLS), LoWord(lFixed.dwFileVersionLS)]);
  finally
    FreeMem(lInfo);
  end;
end;

procedure TfrmMain.LayoutStatusBar;
var
  lFixed: Integer;
  lIndex: Integer;
begin
  // Versie helemaal rechts: het paneel met de schermgegevens vult de ruimte ertussen.
  if sbStatus.Panels.Count < 4 then
    Exit;
  // Ruim meten: de statusbalk tekent met het systeemlettertype, dat vóór het tonen nog niet op de monitor-DPI staat.
  sbStatus.Canvas.Font := sbStatus.Font;
  sbStatus.Panels[3].Width := Max(Round(sbStatus.Canvas.TextWidth(sbStatus.Panels[3].Text) * 1.25), MulDiv(90, CurrentPPI, 96)) + MulDiv(32, CurrentPPI, 96);
  lFixed := 0;
  for lIndex := 0 to sbStatus.Panels.Count - 1 do
    if lIndex <> 1 then
      Inc(lFixed, sbStatus.Panels[lIndex].Width);
  sbStatus.Panels[1].Width := Max(MulDiv(100, CurrentPPI, 96), sbStatus.ClientWidth - lFixed);
end;

procedure TfrmMain.UpdateStatusBar;
var
  lDynamic: string;
  lInfo: TRdpDisplayInfo;
  lServer: TRdcServer;
  lSession: TRdpSession;
begin
  lServer := ActiveServer;
  lSession := FSessions.Find(lServer);
  if lSession <> nil then
  begin
    lInfo := lSession.DisplayInfo;
    sbStatus.Panels[0].Text := Format('%s: %s', [lServer.Caption, RdpSessionStateText(lSession.State)]);
    // Dynamische resolutie alleen tonen in de modus "dynamisch"; anders de gekozen weergavemodus.
    if lInfo.SizeMode = rsmDynamic then
      lDynamic := Format(_('dynamisch: %s'), [RdpDynamicSupportText(lInfo.DynamicSupport)])
    else
      lDynamic := Format(_('weergave: %s'), [RdpSizeModeText(lInfo.SizeMode)]);
    sbStatus.Panels[1].Text := Format(_('Paneel %dx%d · Remote %dx%d · schaal %d%% · %s'), [lInfo.HostWidth, lInfo.HostHeight, lInfo.RemoteWidth, lInfo.RemoteHeight, lInfo.SentDesktopScale, lDynamic]);
  end
  else
  begin
    sbStatus.Panels[0].Text := '';
    sbStatus.Panels[1].Text := '';
  end;
  sbStatus.Panels[2].Text := Format(_('%d actieve verbinding(en)'), [FSessions.ActiveCount]);
end;

end.
