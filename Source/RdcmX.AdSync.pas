unit RdcmX.AdSync;

{
  Synchronises a group linked to an Active Directory OU (TRdcxAdSettings) with the result of an LDAP query
  (RdcmX.AdLdap): computers become servers, sub-OUs become subgroups (or everything flat in the group).

  - Nodes created here carry their distinguished name (TRdcxAdItemSettings) and are matched on it at the next
    refresh: renamed/moved in AD = updated/moved here, gone from AD = removed, unless a session is open on it (it
    stays until a later refresh). Manually added nodes in such a group are never touched; a removed OU whose group
    still holds manual nodes (or open sessions) stays.
  - Servers keep their own settings, favorites and the inherited settings of the AD group, because they are normal
    servers in the file (also in the .rdg, so RDCMan can open it).
  - A subgroup that has its own AD link is a separate AD group and is skipped.
  - Only OUs that contain (directly or deeper) at least one computer that passes the filters become groups (user
    request): empty OUs, or OUs with only disabled/filtered computers, are not shown; an OU group that becomes empty
    is removed at the next refresh like any other node that is gone.
  No VCL dependency (tested in the console test project).
}

interface

uses
  System.Generics.Collections, System.SysUtils,
  RdcmX.Model;

type
  TRdcAdEntryKind = (aekOu, aekComputer);

  TRdcAdEntry = record
    Kind: TRdcAdEntryKind;
    Dn: string;
    /// <summary>OU name or computer name (sAMAccountName without $ / cn).</summary>
    Name: string;
    DnsHostName: string;
    Disabled: Boolean;
    class function Ou(const aDn, aName: string): TRdcAdEntry; static;
    class function Computer(const aDn, aName, aDnsHostName: string; aDisabled: Boolean = False): TRdcAdEntry; static;
  end;

  TRdcAdSyncResult = record
    Added: Integer;
    Updated: Integer;
    Removed: Integer;
    /// <summary>Gone from AD but kept (open session, or a group that still holds other nodes).</summary>
    Kept: Integer;
    /// <summary>The name filter is not a valid mask: nothing was changed (no computer removed).</summary>
    InvalidFilter: Boolean;
  end;

/// <summary>Is aFilter usable as name filter (empty, or a valid wildcard mask; e.g. "[a" is not)?</summary>
function RdcAdIsValidNameFilter(const aFilter: string): Boolean;

/// <summary>DN without its first RDN ("OU=a,OU=b,DC=x" -> "OU=b,DC=x"); escaped commas (\,) are respected.</summary>
function RdcAdParentDn(const aDn: string): string;
/// <summary>DN for comparisons: lower case, no spaces around unescaped commas and equals signs.</summary>
function RdcAdNormalizeDn(const aDn: string): string;
/// <summary>Applies the entries to aGroup (which must have its own AD link). aIsBusy: servers that must not be
/// removed (open session). aBeforeRemove: called before a node is removed (favorites, tree).</summary>
function RdcAdSync(aGroup: TRdcGroup; const aEntries: TArray<TRdcAdEntry>; const aIsBusy: TFunc<TRdcServer, Boolean>; const aBeforeRemove: TProc<TRdcNode>): TRdcAdSyncResult;

implementation

uses
  System.Generics.Defaults, System.Masks;

{ TRdcAdEntry }

class function TRdcAdEntry.Ou(const aDn, aName: string): TRdcAdEntry;
begin
  Result := Default(TRdcAdEntry);
  Result.Kind := aekOu;
  Result.Dn := aDn;
  Result.Name := aName;
end;

class function TRdcAdEntry.Computer(const aDn, aName, aDnsHostName: string; aDisabled: Boolean): TRdcAdEntry;
begin
  Result := Default(TRdcAdEntry);
  Result.Kind := aekComputer;
  Result.Dn := aDn;
  Result.Name := aName;
  Result.DnsHostName := aDnsHostName;
  Result.Disabled := aDisabled;
end;

function FirstUnescapedComma(const aDn: string): Integer;
var
  lIndex: Integer;
begin
  lIndex := 1;
  while lIndex <= Length(aDn) do
  begin
    if aDn[lIndex] = '\' then
      Inc(lIndex) // skip the escaped character
    else if aDn[lIndex] = ',' then
      Exit(lIndex);
    Inc(lIndex);
  end;
  Result := 0;
end;

function RdcAdParentDn(const aDn: string): string;
var
  lComma: Integer;
begin
  lComma := FirstUnescapedComma(aDn);
  if lComma = 0 then
    Result := ''
  else
    Result := Trim(Copy(aDn, lComma + 1, MaxInt));
end;

function RdcAdNormalizeDn(const aDn: string): string;
var
  lBuilder: TStringBuilder;
  lChar: Char;
  lIndex: Integer;
begin
  lBuilder := TStringBuilder.Create;
  try
    lIndex := 1;
    while lIndex <= Length(aDn) do
    begin
      lChar := aDn[lIndex];
      if (lChar = '\') and (lIndex < Length(aDn)) then
      begin
        lBuilder.Append(lChar).Append(aDn[lIndex + 1]);
        Inc(lIndex, 2);
        Continue;
      end;
      if CharInSet(lChar, [',', '=']) then
      begin
        // drop spaces before and after the separator
        while (lBuilder.Length > 0) and (lBuilder.Chars[lBuilder.Length - 1] = ' ') do
          lBuilder.Length := lBuilder.Length - 1;
        lBuilder.Append(lChar);
        Inc(lIndex);
        while (lIndex <= Length(aDn)) and (aDn[lIndex] = ' ') do
          Inc(lIndex);
        Continue;
      end;
      lBuilder.Append(lChar);
      Inc(lIndex);
    end;
    Result := LowerCase(Trim(lBuilder.ToString));
  finally
    lBuilder.Free;
  end;
end;

function DnDepth(const aDn: string): Integer;
var
  lRest: string;
begin
  Result := 0;
  lRest := aDn;
  while lRest <> '' do
  begin
    Inc(Result);
    lRest := RdcAdParentDn(lRest);
  end;
end;

procedure CollectSynced(aGroup: TRdcGroup; aMap: TDictionary<string, TRdcNode>);
var
  lChild: TRdcNode;
  lIndex: Integer;
begin
  for lIndex := 0 to aGroup.Count - 1 do
  begin
    lChild := aGroup[lIndex];
    // Another AD group inside: its own refresh owns everything below it.
    if (lChild is TRdcGroup) and lChild.Settings.Ad.IsLinked then
      Continue;
    if lChild.Settings.AdItem.Dn <> '' then
      aMap.AddOrSetValue(RdcAdNormalizeDn(lChild.Settings.AdItem.Dn), lChild);
    if lChild is TRdcGroup then
      CollectSynced(TRdcGroup(lChild), aMap);
  end;
end;

function RdcAdIsValidNameFilter(const aFilter: string): Boolean;
var
  lMask: TMask;
begin
  if Trim(aFilter) = '' then
    Exit(True);
  try
    lMask := TMask.Create(aFilter);
    try
      lMask.Matches('test'); // the pattern is parsed here
    finally
      lMask.Free;
    end;
    Result := True;
  except
    on EMaskException do
      Result := False;
  end;
end;

function IncludedComputer(const aEntry: TRdcAdEntry; aConfig: TRdcxAdSettings): Boolean;
begin
  Result := (aEntry.Kind = aekComputer) and not (aConfig.SkipDisabled and aEntry.Disabled)
    and ((aConfig.NameFilter = '') or MatchesMask(aEntry.Name, aConfig.NameFilter))
    and ((Trim(aEntry.DnsHostName) <> '') or (aEntry.Name <> ''));
end;

function RdcAdSync(aGroup: TRdcGroup; const aEntries: TArray<TRdcAdEntry>; const aIsBusy: TFunc<TRdcServer, Boolean>; const aBeforeRemove: TProc<TRdcNode>): TRdcAdSyncResult;
var
  lBase: string;
  lConfig: TRdcxAdSettings;
  lEntry: TRdcAdEntry;
  lExisting: TDictionary<string, TRdcNode>;
  lGroup: TRdcGroup;
  lGroups: TList<TRdcGroup>;
  lHost: string;
  lKey: string;
  lNode: TRdcNode;
  lOuGroups: TDictionary<string, TRdcGroup>;
  lOus: TList<TRdcAdEntry>;
  lParent: TRdcGroup;
  lParentDn: string;
  lFilled: TDictionary<string, Boolean>;
  lSeen: TDictionary<TRdcNode, Boolean>;
  lServer: TRdcServer;

  function ParentGroupFor(const aDn: string): TRdcGroup;
  var
    lParentKey: string;
  begin
    Result := aGroup;
    if not lConfig.SubOus then
      Exit;
    lParentKey := RdcAdNormalizeDn(RdcAdParentDn(aDn));
    if lParentKey <> lBase then
      lOuGroups.TryGetValue(lParentKey, Result);
    if Result = nil then
      Result := aGroup;
  end;

  procedure PlaceIn(aNode: TRdcNode; aTarget: TRdcGroup);
  begin
    if aNode.Parent <> aTarget then
    begin
      aTarget.MoveHere(aNode);
      Inc(Result.Updated);
    end;
  end;

begin
  Result := Default(TRdcAdSyncResult);
  lConfig := aGroup.Settings.Ad;
  // A filter from the file that is not a valid mask would raise on the main thread, and matching nothing would
  // remove every synced server: change nothing.
  if not RdcAdIsValidNameFilter(lConfig.NameFilter) then
  begin
    Result.InvalidFilter := True;
    Exit;
  end;
  lBase := RdcAdNormalizeDn(lConfig.OuDn);
  lExisting := TDictionary<string, TRdcNode>.Create;
  lOuGroups := TDictionary<string, TRdcGroup>.Create;
  lSeen := TDictionary<TRdcNode, Boolean>.Create;
  lOus := TList<TRdcAdEntry>.Create;
  lGroups := TList<TRdcGroup>.Create;
  lFilled := TDictionary<string, Boolean>.Create;
  try
    CollectSynced(aGroup, lExisting);

    // OUs that hold an included computer, directly or deeper: only those become groups.
    for lEntry in aEntries do
      if IncludedComputer(lEntry, lConfig) then
      begin
        lParentDn := RdcAdParentDn(lEntry.Dn);
        while (lParentDn <> '') and (RdcAdNormalizeDn(lParentDn) <> lBase) do
        begin
          lFilled.AddOrSetValue(RdcAdNormalizeDn(lParentDn), True);
          lParentDn := RdcAdParentDn(lParentDn);
        end;
      end;

    // OUs first, parents before children.
    if lConfig.SubOus then
    begin
      for lEntry in aEntries do
        if (lEntry.Kind = aekOu) and (RdcAdNormalizeDn(lEntry.Dn) <> lBase) and lFilled.ContainsKey(RdcAdNormalizeDn(lEntry.Dn)) then
          lOus.Add(lEntry);
      lOus.Sort(TComparer<TRdcAdEntry>.Construct(
        function(const aLeft, aRight: TRdcAdEntry): Integer
        begin
          Result := DnDepth(aLeft.Dn) - DnDepth(aRight.Dn);
        end));
      for lEntry in lOus do
      begin
        lKey := RdcAdNormalizeDn(lEntry.Dn);
        lParent := ParentGroupFor(lEntry.Dn);
        if lExisting.TryGetValue(lKey, lNode) and (lNode is TRdcGroup) then
        begin
          lGroup := TRdcGroup(lNode);
          if lGroup.Name <> lEntry.Name then
          begin
            lGroup.Name := lEntry.Name;
            Inc(Result.Updated);
          end;
          PlaceIn(lGroup, lParent);
        end
        else
        begin
          lGroup := TRdcGroup(lParent.Add(TRdcGroup.Create(lEntry.Name)));
          lGroup.Settings.AdItem.Dn := lEntry.Dn;
          Inc(Result.Added);
        end;
        lSeen.AddOrSetValue(lGroup, True);
        lOuGroups.AddOrSetValue(lKey, lGroup);
      end;
    end;

    for lEntry in aEntries do
    begin
      if not IncludedComputer(lEntry, lConfig) then
        Continue;
      lHost := Trim(lEntry.DnsHostName);
      if lHost = '' then
        lHost := lEntry.Name;
      lParent := ParentGroupFor(lEntry.Dn);
      if lExisting.TryGetValue(RdcAdNormalizeDn(lEntry.Dn), lNode) and (lNode is TRdcServer) then
      begin
        lServer := TRdcServer(lNode);
        if not SameText(lServer.Name, lHost) then
        begin
          lServer.Name := lHost;
          Inc(Result.Updated);
        end;
        PlaceIn(lServer, lParent);
      end
      else
      begin
        lServer := TRdcServer(lParent.Add(TRdcServer.Create(lHost)));
        // Short computer name in the tree, the DNS name to connect to.
        if not SameText(lEntry.Name, lHost) then
          lServer.DisplayName := lEntry.Name;
        lServer.Settings.AdItem.Dn := lEntry.Dn;
        Inc(Result.Added);
      end;
      lSeen.AddOrSetValue(lServer, True);
    end;

    // Gone from AD: servers first (unless busy), then groups that became empty, deepest first.
    for lNode in lExisting.Values do
      if not lSeen.ContainsKey(lNode) then
      begin
        if lNode is TRdcServer then
        begin
          if Assigned(aIsBusy) and aIsBusy(TRdcServer(lNode)) then
            Inc(Result.Kept)
          else
          begin
            if Assigned(aBeforeRemove) then
              aBeforeRemove(lNode);
            lNode.Parent.Delete(lNode);
            Inc(Result.Removed);
          end;
        end
        else if lNode is TRdcGroup then
          lGroups.Add(TRdcGroup(lNode));
      end;
    lGroups.Sort(TComparer<TRdcGroup>.Construct(
      function(const aLeft, aRight: TRdcGroup): Integer
      begin
        Result := DnDepth(aRight.Settings.AdItem.Dn) - DnDepth(aLeft.Settings.AdItem.Dn);
      end));
    for lGroup in lGroups do
      if lGroup.Count = 0 then
      begin
        if Assigned(aBeforeRemove) then
          aBeforeRemove(lGroup);
        lGroup.Parent.Delete(lGroup);
        Inc(Result.Removed);
      end
      else
        Inc(Result.Kept);
  finally
    lFilled.Free;
    lGroups.Free;
    lOus.Free;
    lSeen.Free;
    lOuGroups.Free;
    lExisting.Free;
  end;
end;

end.
