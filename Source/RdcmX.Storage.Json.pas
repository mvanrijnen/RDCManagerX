unit RdcmX.Storage.Json;

(*
  Eigen formaat .rdcx (JSON, System.JSON), alleen bytes <-> model.

  Opbouw (vaste volgorde van keys, ingesprongen met 2 spaties):
    {
      "formatVersion": 1,
      "rdcman": { "programVersion": "2.90", "schemaVersion": "3" },     // voor conversie terug naar .rdg
      "rdgFormat": { "bom": true, "lineBreak": "CRLF", "indent": "  ", "trailingLineBreak": false, "declaration": "..." },
      "credentialsProfiles": { "attributes": {...}, "profiles": [ {...} ] },   // alleen als aanwezig
      "root": { node },
      "connected": [ "pad", ... ], "favorites": [...], "recentlyUsed": [...],   // alleen als aanwezig
      "rootUnknownXml": [ { "anchor": "...", "xml": "<...>" } ],
      "sidecarOrphans": { "pad": {...} },
      "tailnets": [ { "id": "{GUID}", "name": "Thuis", "nodeHostName": "", "ephemeral": true, "controlUrl": "",
                      "localAddress": "" } ],                                   // alleen als aanwezig
      "gateways": [ { "id": "{GUID}", "name": "Werk", "hostName": "rdg.example.com", "port": 0, "usage": "Always",
                      "credsMode": "Session", "authMethod": "NTLM", "userName": "", "domain": "", "tailnetId": "" } ]
    }
  tailnets/gateways (ook in de sidecar): definities per bestand. Geheimen (auth key, state-sleutel,
  gateway-wachtwoord) staan NOOIT hier, maar in de wachtwoordkluis van de pc (op id).
  Node:
    { "type": "file|group|server", "attributes": {...}, "properties": {...}, "settings": { "<sectie>": {...} },
      "children": [ ... ], "unknownXml": [ { "anchor": "properties" | "child:3" | "", "xml": "<...>" } ] }
  Sectie: { "inherit": false, "<element>": "waarde", ... }. Alleen niet-overgeërfde secties worden geschreven.
  Element met attributen of kind-elementen: object met "@attr", "#text" en kind-keys (meerdere gelijknamige
  kinderen als array).

  Afwijking van de opdracht (bewust): velden met de default-waarde worden WEL geschreven als ze in het
  bestand stonden. Anders is .rdg -> .rdcx -> .rdg niet meer byte-identiek (RDCMan schrijft op bestandsniveau
  alle velden, ook defaults).

  Wachtwoorden: nooit. "password" is altijd een lege string.
  formatVersion: hoger dan cRdcxFormatVersion wordt geweigerd; lager wordt gemigreerd (er bestaat nog geen oudere).
*)

interface

uses
  System.Classes, System.JSON, System.SysUtils,
  RdcmX.Model, RdcmX.XmlTree;

const
  cRdcxFormatVersion = 1;

type
  TRdcJsonFormat = class abstract
  public
    class function Read(const aBytes: TBytes; const aFileName: string = ''): TRdcFile; static;
    class function Write(aFile: TRdcFile): TBytes; static;
    // Gedeelde hulpfuncties (ook voor de sidecar)
    class function SectionToJson(aSection: TRdcSettingsGroup): TJSONObject; static;
    class procedure JsonToSection(aObject: TJSONObject; aSection: TRdcSettingsGroup); static;
    class function FormatJson(aValue: TJSONValue): string; static;
    /// <summary>"tailnets"/"gateways" van aFile aan aRoot toevoegen (alleen als er definities zijn).</summary>
    class procedure DefinitionsToJson(aFile: TRdcFile; aRoot: TJSONObject); static;
    /// <summary>"tailnets"/"gateways" uit aRoot in aFile lezen (bestaande worden vervangen).</summary>
    class procedure JsonToDefinitions(aRoot: TJSONObject; aFile: TRdcFile); static;
  end;

implementation

uses
  System.Generics.Collections,
  RdcmX.Lang, RdcmX.Storage.Rdg;

const
  cAttributePrefix = '@';
  cTextKey = '#text';

{ XML-element <-> JSON }

procedure AddAttributesTo(aObject: TJSONObject; aNode: TRdcXmlNode; const aSkip: string = '');
var
  lAttribute: TRdcXmlAttribute;
begin
  for lAttribute in aNode.Attributes do
    if lAttribute.Name <> aSkip then
      aObject.AddPair(cAttributePrefix + lAttribute.Name, lAttribute.Value);
end;

function ElementToJson(aNode: TRdcXmlNode): TJSONValue; forward;

procedure AddChildrenTo(aObject: TJSONObject; aNode: TRdcXmlNode);
var
  lArray: TJSONArray;
  lChild: TRdcXmlNode;
  lCount: Integer;
  lDone: TList<string>;
  lOther: TRdcXmlNode;
begin
  lDone := TList<string>.Create;
  try
    for lChild in aNode.Children do
    begin
      if lDone.Contains(lChild.Name) then
        Continue;
      lDone.Add(lChild.Name);
      lCount := 0;
      for lOther in aNode.Children do
        if lOther.Name = lChild.Name then
          Inc(lCount);
      if lCount = 1 then
        aObject.AddPair(lChild.Name, ElementToJson(lChild))
      else
      begin
        lArray := TJSONArray.Create;
        for lOther in aNode.Children do
          if lOther.Name = lChild.Name then
            lArray.AddElement(ElementToJson(lOther));
        aObject.AddPair(lChild.Name, lArray);
      end;
    end;
  finally
    lDone.Free;
  end;
end;

function ElementToJson(aNode: TRdcXmlNode): TJSONValue;
var
  lObject: TJSONObject;
begin
  if (aNode.Attributes.Count = 0) and (aNode.Children.Count = 0) then
    Exit(TJSONString.Create(aNode.Text));
  lObject := TJSONObject.Create;
  AddAttributesTo(lObject, aNode);
  if aNode.Text <> '' then
    lObject.AddPair(cTextKey, aNode.Text);
  AddChildrenTo(lObject, aNode);
  Result := lObject;
end;

procedure JsonInto(aNode: TRdcXmlNode; aObject: TJSONObject; const aSkip: array of string);
var
  lItem: TJSONValue;
  lPair: TJSONPair;
  lSkip: Boolean;
  lSkipName: string;

  function JsonToElement(const aName: string; aValue: TJSONValue): TRdcXmlNode;
  begin
    Result := TRdcXmlNode.Create(aName);
    if aValue is TJSONObject then
      JsonInto(Result, TJSONObject(aValue), [])
    else if aValue is TJSONString then
      Result.Text := TJSONString(aValue).Value
    else if not (aValue is TJSONNull) then
      Result.Text := aValue.Value;
  end;

begin
  for lPair in aObject do
  begin
    lSkip := False;
    for lSkipName in aSkip do
      if lPair.JsonString.Value = lSkipName then
        lSkip := True;
    if lSkip then
      Continue;
    if lPair.JsonString.Value.StartsWith(cAttributePrefix) then
      aNode.SetAttribute(Copy(lPair.JsonString.Value, 2, MaxInt), lPair.JsonValue.Value)
    else if lPair.JsonString.Value = cTextKey then
      aNode.Text := lPair.JsonValue.Value
    else if lPair.JsonValue is TJSONArray then
    begin
      for lItem in TJSONArray(lPair.JsonValue) do
        aNode.AddChild(JsonToElement(lPair.JsonString.Value, lItem));
    end
    else
      aNode.AddChild(JsonToElement(lPair.JsonString.Value, lPair.JsonValue));
  end;
end;

procedure ClearPasswordElement(aNode: TRdcXmlNode);
var
  lPassword: TRdcXmlNode;
begin
  lPassword := aNode.FindChild('password');
  if lPassword <> nil then
    lPassword.Text := '';
end;

class function TRdcJsonFormat.SectionToJson(aSection: TRdcSettingsGroup): TJSONObject;
var
  lNode: TRdcXmlNode;
begin
  Result := TJSONObject.Create;
  Result.AddPair('inherit', TJSONBool.Create(aSection.Inherit));
  lNode := aSection.Node.Clone;
  try
    ClearPasswordElement(lNode);
    AddAttributesTo(Result, lNode, 'inherit');
    AddChildrenTo(Result, lNode);
  finally
    lNode.Free;
  end;
end;

class procedure TRdcJsonFormat.JsonToSection(aObject: TJSONObject; aSection: TRdcSettingsGroup);
var
  lInherit: TJSONValue;
  lNode: TRdcXmlNode;
begin
  lNode := TRdcXmlNode.Create(aSection.XmlName);
  try
    lInherit := aObject.GetValue('inherit');
    aSection.Inherit := (lInherit is TJSONBool) and TJSONBool(lInherit).AsBoolean;
    if not aSection.Inherit then
      lNode.SetAttribute('inherit', cRdcInheritNone);
    JsonInto(lNode, aObject, ['inherit']);
    ClearPasswordElement(lNode);
  except
    lNode.Free;
    raise;
  end;
  aSection.ReplaceNode(lNode);
end;

class function TRdcJsonFormat.FormatJson(aValue: TJSONValue): string;
begin
  Result := aValue.Format(2);
end;

{ Schrijven }

class procedure TRdcJsonFormat.DefinitionsToJson(aFile: TRdcFile; aRoot: TJSONObject);
var
  lArray: TJSONArray;
  lGateway: TRdcGatewayDef;
  lObject: TJSONObject;
  lTailnet: TRdcTailnetDef;
begin
  if aFile.Tailnets.Count > 0 then
  begin
    lArray := TJSONArray.Create;
    for lTailnet in aFile.Tailnets do
    begin
      lObject := TJSONObject.Create;
      lObject.AddPair('id', lTailnet.Id);
      lObject.AddPair('name', lTailnet.Name);
      lObject.AddPair('nodeHostName', lTailnet.NodeHostName);
      lObject.AddPair('ephemeral', TJSONBool.Create(lTailnet.Ephemeral));
      lObject.AddPair('controlUrl', lTailnet.ControlUrl);
      lObject.AddPair('localAddress', lTailnet.LocalAddress);
      lArray.AddElement(lObject);
    end;
    aRoot.AddPair('tailnets', lArray);
  end;
  if aFile.Gateways.Count > 0 then
  begin
    lArray := TJSONArray.Create;
    for lGateway in aFile.Gateways do
    begin
      lObject := TJSONObject.Create;
      lObject.AddPair('id', lGateway.Id);
      lObject.AddPair('name', lGateway.Name);
      lObject.AddPair('hostName', lGateway.HostName);
      lObject.AddPair('port', TJSONNumber.Create(lGateway.Port));
      lObject.AddPair('usage', cRdcGatewayUsageNames[lGateway.Usage]);
      lObject.AddPair('credsMode', cRdcGatewayCredsModeNames[lGateway.CredsMode]);
      lObject.AddPair('authMethod', cRdcGatewayLogonMethodNames[lGateway.AuthMethod]);
      lObject.AddPair('userName', lGateway.UserName);
      lObject.AddPair('domain', lGateway.Domain);
      lObject.AddPair('tailnetId', lGateway.TailnetId);
      lArray.AddElement(lObject);
    end;
    aRoot.AddPair('gateways', lArray);
  end;
end;

class procedure TRdcJsonFormat.JsonToDefinitions(aRoot: TJSONObject; aFile: TRdcFile);
var
  lGateway: TRdcGatewayDef;
  lItem: TJSONValue;
  lTailnet: TRdcTailnetDef;
  lValue: TJSONValue;
begin
  aFile.Tailnets.Clear;
  aFile.Gateways.Clear;
  lValue := aRoot.GetValue('tailnets');
  if lValue is TJSONArray then
    for lItem in TJSONArray(lValue) do
      if (lItem is TJSONObject) and (lItem.GetValue<string>('id', '') <> '') then
      begin
        lTailnet := TRdcTailnetDef.Create;
        lTailnet.Id := lItem.GetValue<string>('id', '');
        lTailnet.Name := lItem.GetValue<string>('name', '');
        lTailnet.NodeHostName := lItem.GetValue<string>('nodeHostName', '');
        lTailnet.Ephemeral := lItem.GetValue<Boolean>('ephemeral', True);
        lTailnet.ControlUrl := lItem.GetValue<string>('controlUrl', '');
        lTailnet.LocalAddress := lItem.GetValue<string>('localAddress', '');
        aFile.Tailnets.Add(lTailnet);
      end;
  lValue := aRoot.GetValue('gateways');
  if lValue is TJSONArray then
    for lItem in TJSONArray(lValue) do
      if (lItem is TJSONObject) and (lItem.GetValue<string>('id', '') <> '') then
      begin
        lGateway := TRdcGatewayDef.Create;
        lGateway.Id := lItem.GetValue<string>('id', '');
        lGateway.Name := lItem.GetValue<string>('name', '');
        lGateway.HostName := lItem.GetValue<string>('hostName', '');
        lGateway.Port := lItem.GetValue<Integer>('port', 0);
        lGateway.Usage := TRdcGatewayUsage(RdcTextToEnum(lItem.GetValue<string>('usage', ''), cRdcGatewayUsageNames, Ord(guAlways)));
        lGateway.CredsMode := TRdcGatewayCredsMode(RdcTextToEnum(lItem.GetValue<string>('credsMode', ''), cRdcGatewayCredsModeNames, Ord(gcmSession)));
        lGateway.AuthMethod := TRdcGatewayLogonMethod(RdcTextToEnum(lItem.GetValue<string>('authMethod', ''), cRdcGatewayLogonMethodNames, Ord(glmNTLM)));
        lGateway.UserName := lItem.GetValue<string>('userName', '');
        lGateway.Domain := lItem.GetValue<string>('domain', '');
        lGateway.TailnetId := lItem.GetValue<string>('tailnetId', '');
        aFile.Gateways.Add(lGateway);
      end;
end;

function UnknownToJson(aUnknown: TObjectList<TRdcUnknownElement>; aParent: TRdcNode): TJSONArray;
var
  lAnchor: string;
  lItem: TJSONObject;
  lUnknown: TRdcUnknownElement;
begin
  Result := TJSONArray.Create;
  for lUnknown in aUnknown do
  begin
    if (lUnknown.AnchorNode <> nil) and (aParent is TRdcGroup) then
      lAnchor := 'child:' + IntToStr(TRdcGroup(aParent).IndexOf(lUnknown.AnchorNode))
    else
      lAnchor := lUnknown.AnchorName;
    lItem := TJSONObject.Create;
    lItem.AddPair('anchor', lAnchor);
    lItem.AddPair('xml', TRdcXmlWriter.CompactText(lUnknown.Element));
    Result.AddElement(lItem);
  end;
end;

function NodeToJson(aNode: TRdcNode): TJSONObject;
var
  lAttributes: TJSONObject;
  lChildren: TJSONArray;
  lIndex: Integer;
  lProperties: TJSONObject;
  lSection: TRdcSettingsGroup;
  lSettings: TJSONObject;
begin
  Result := TJSONObject.Create;
  if aNode is TRdcFile then
    Result.AddPair('type', 'file')
  else if aNode is TRdcGroup then
    Result.AddPair('type', 'group')
  else
    Result.AddPair('type', 'server');

  if aNode.ElementAttributes.Attributes.Count > 0 then
  begin
    lAttributes := TJSONObject.Create;
    AddAttributesTo(lAttributes, aNode.ElementAttributes);
    Result.AddPair('attributes', lAttributes);
  end;

  lProperties := TJSONObject.Create;
  AddAttributesTo(lProperties, aNode.Properties);
  AddChildrenTo(lProperties, aNode.Properties);
  Result.AddPair('properties', lProperties);

  lSettings := TJSONObject.Create;
  for lSection in aNode.Settings.Groups do
    if not lSection.Inherit then
      lSettings.AddPair(lSection.XmlName, TRdcJsonFormat.SectionToJson(lSection));
  Result.AddPair('settings', lSettings);

  if aNode is TRdcGroup then
  begin
    lChildren := TJSONArray.Create;
    for lIndex := 0 to TRdcGroup(aNode).Count - 1 do
      lChildren.AddElement(NodeToJson(TRdcGroup(aNode)[lIndex]));
    Result.AddPair('children', lChildren);
  end;

  if aNode.Unknown.Count > 0 then
    Result.AddPair('unknownXml', UnknownToJson(aNode.Unknown, aNode));
end;

function RefListToJson(aList: TRdcNodeRefList): TJSONArray;
var
  lIndex: Integer;
begin
  Result := TJSONArray.Create;
  for lIndex := 0 to aList.Count - 1 do
    Result.Add(aList.CurrentPath(lIndex));
end;

function LineBreakName(const aLineBreak: string): string;
begin
  if aLineBreak = #10 then
    Result := 'LF'
  else
    Result := 'CRLF';
end;

class function TRdcJsonFormat.Write(aFile: TRdcFile): TBytes;
var
  lFormat: TJSONObject;
  lOrphans: TJSONObject;
  lPair: TPair<string, string>;
  lProfile: TRdcCredentialProfile;
  lProfiles: TJSONArray;
  lProfilesObject: TJSONObject;
  lRdcman: TJSONObject;
  lRoot: TJSONObject;
  lAttributes: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  try
    lRoot.AddPair('formatVersion', TJSONNumber.Create(cRdcxFormatVersion));

    lRdcman := TJSONObject.Create;
    AddAttributesTo(lRdcman, aFile.RootElement);
    lRoot.AddPair('rdcman', lRdcman);

    lFormat := TJSONObject.Create;
    lFormat.AddPair('bom', TJSONBool.Create(aFile.XmlFormat.HasBom));
    lFormat.AddPair('lineBreak', LineBreakName(aFile.XmlFormat.LineBreak));
    lFormat.AddPair('indent', aFile.XmlFormat.Indent);
    lFormat.AddPair('trailingLineBreak', TJSONBool.Create(aFile.XmlFormat.TrailingLineBreak));
    lFormat.AddPair('declaration', aFile.XmlFormat.Declaration);
    lRoot.AddPair('rdgFormat', lFormat);

    if (aFile.ProfilesElement <> nil) or (aFile.Profiles.Count > 0) then
    begin
      lProfilesObject := TJSONObject.Create;
      lAttributes := TJSONObject.Create;
      if aFile.ProfilesElement <> nil then
        AddAttributesTo(lAttributes, aFile.ProfilesElement);
      lProfilesObject.AddPair('attributes', lAttributes);
      lProfiles := TJSONArray.Create;
      for lProfile in aFile.Profiles do
        lProfiles.AddElement(TRdcJsonFormat.SectionToJson(lProfile));
      lProfilesObject.AddPair('profiles', lProfiles);
      lRoot.AddPair('credentialsProfiles', lProfilesObject);
    end;

    lRoot.AddPair('root', NodeToJson(aFile));

    if aFile.Connected.Present or (aFile.Connected.Count > 0) then
      lRoot.AddPair('connected', RefListToJson(aFile.Connected));
    if aFile.Favorites.Present or (aFile.Favorites.Count > 0) then
      lRoot.AddPair('favorites', RefListToJson(aFile.Favorites));
    if aFile.RecentlyUsed.Present or (aFile.RecentlyUsed.Count > 0) then
      lRoot.AddPair('recentlyUsed', RefListToJson(aFile.RecentlyUsed));
    if aFile.RootUnknown.Count > 0 then
      lRoot.AddPair('rootUnknownXml', UnknownToJson(aFile.RootUnknown, nil));

    if aFile.SidecarOrphans.Count > 0 then
    begin
      lOrphans := TJSONObject.Create;
      for lPair in aFile.SidecarOrphans do
        lOrphans.AddPair(lPair.Key, TJSONObject.ParseJSONValue(lPair.Value));
      lRoot.AddPair('sidecarOrphans', lOrphans);
    end;

    TRdcJsonFormat.DefinitionsToJson(aFile, lRoot);

    Result := TEncoding.UTF8.GetBytes(TRdcJsonFormat.FormatJson(lRoot));
  finally
    lRoot.Free;
  end;
end;

{ Lezen }

type
  TJsonReader = class
  private
    FFile: TRdcFile;
    FPending: TList<TPair<TRdcNodeRefList, string>>;
    procedure ReadNode(aNode: TRdcNode; aObject: TJSONObject);
    procedure ReadUnknown(aNode: TRdcNode; aArray: TJSONArray; aTarget: TObjectList<TRdcUnknownElement>);
    procedure ReadRefList(aRoot: TJSONObject; const aKey: string; aList: TRdcNodeRefList);
  public
    function Read(aRoot: TJSONObject; const aFileName: string): TRdcFile;
  end;

procedure TJsonReader.ReadUnknown(aNode: TRdcNode; aArray: TJSONArray; aTarget: TObjectList<TRdcUnknownElement>);
var
  lAnchor: string;
  lChildIndex: Integer;
  lItem: TJSONValue;
  lUnknown: TRdcUnknownElement;
begin
  for lItem in aArray do
  begin
    if not (lItem is TJSONObject) then
      Continue;
    lUnknown := TRdcUnknownElement.Create;
    lUnknown.Element := TRdcRdgFormat.ParseXmlText(TJSONObject(lItem).GetValue<string>('xml'));
    lAnchor := TJSONObject(lItem).GetValue<string>('anchor', '');
    if lAnchor.StartsWith('child:') and (aNode is TRdcGroup) and TryStrToInt(Copy(lAnchor, 7, MaxInt), lChildIndex) and (lChildIndex >= 0) and (lChildIndex < TRdcGroup(aNode).Count) then
      lUnknown.AnchorNode := TRdcGroup(aNode)[lChildIndex]
    else
      lUnknown.AnchorName := lAnchor;
    aTarget.Add(lUnknown);
  end;
end;

procedure TJsonReader.ReadNode(aNode: TRdcNode; aObject: TJSONObject);
var
  lChild: TRdcNode;
  lChildren: TJSONArray;
  lItem: TJSONValue;
  lPair: TJSONPair;
  lSection: TRdcSettingsGroup;
  lSettings: TJSONObject;
  lType: string;
  lValue: TJSONValue;
begin
  lValue := aObject.GetValue('attributes');
  if lValue is TJSONObject then
    for lPair in TJSONObject(lValue) do
      aNode.ElementAttributes.SetAttribute(Copy(lPair.JsonString.Value, 2, MaxInt), lPair.JsonValue.Value);

  aNode.Properties.Children.Clear;
  aNode.Properties.Attributes.Clear;
  lValue := aObject.GetValue('properties');
  if lValue is TJSONObject then
    JsonInto(aNode.Properties, TJSONObject(lValue), []);

  lSettings := aObject.GetValue('settings') as TJSONObject;
  if lSettings <> nil then
    for lPair in lSettings do
    begin
      lSection := aNode.Settings.FindByXmlName(lPair.JsonString.Value);
      if (lSection <> nil) and (lPair.JsonValue is TJSONObject) then
        TRdcJsonFormat.JsonToSection(TJSONObject(lPair.JsonValue), lSection)
      else
        FFile.Warnings.Add(Format(_('Onbekende instellingsgroep "%s" bij "%s" genegeerd.'), [lPair.JsonString.Value, aNode.Caption]));
    end;

  lChildren := aObject.GetValue('children') as TJSONArray;
  if (lChildren <> nil) and (aNode is TRdcGroup) then
    for lItem in lChildren do
    begin
      if not (lItem is TJSONObject) then
        Continue;
      lType := TJSONObject(lItem).GetValue<string>('type', 'server');
      if lType = 'group' then
        lChild := TRdcGroup.Create('')
      else
        lChild := TRdcServer.Create('');
      TRdcGroup(aNode).Add(lChild);
      ReadNode(lChild, TJSONObject(lItem));
    end;

  lValue := aObject.GetValue('unknownXml');
  if lValue is TJSONArray then
    ReadUnknown(aNode, TJSONArray(lValue), aNode.Unknown);
end;

procedure TJsonReader.ReadRefList(aRoot: TJSONObject; const aKey: string; aList: TRdcNodeRefList);
var
  lItem: TJSONValue;
  lValue: TJSONValue;
begin
  lValue := aRoot.GetValue(aKey);
  aList.Present := lValue is TJSONArray;
  if not aList.Present then
    Exit;
  for lItem in TJSONArray(lValue) do
    FPending.Add(TPair<TRdcNodeRefList, string>.Create(aList, lItem.Value));
end;

function TJsonReader.Read(aRoot: TJSONObject; const aFileName: string): TRdcFile;
var
  lFormat: TRdcXmlFormat;
  lItem: TJSONValue;
  lNode: TRdcNode;
  lPair: TJSONPair;
  lPending: TPair<TRdcNodeRefList, string>;
  lProfile: TRdcCredentialProfile;
  lProfilesObject: TJSONObject;
  lValue: TJSONValue;
  lVersion: Integer;
begin
  lVersion := aRoot.GetValue<Integer>('formatVersion', 0);
  if lVersion > cRdcxFormatVersion then
    raise ERdcFormatError.CreateFmt(_('%s is gemaakt met een nieuwere versie van RDCManX (formatVersion %d); deze versie ondersteunt t/m formatVersion %d.'), [aFileName, lVersion, cRdcxFormatVersion]);
  if lVersion < 1 then
    raise ERdcFormatError.CreateFmt(_('%s is geen geldig .rdcx-bestand (formatVersion ontbreekt).'), [aFileName]);
  // Migratie van oudere formatVersions komt hier zodra die er zijn.

  FFile := TRdcFile.Create('');
  FPending := TList<TPair<TRdcNodeRefList, string>>.Create;
  try
    try
      FFile.Format := ffRdcx;
      FFile.RootElement.Attributes.Clear;
      lValue := aRoot.GetValue('rdcman');
      if lValue is TJSONObject then
        for lPair in TJSONObject(lValue) do
          FFile.RootElement.SetAttribute(Copy(lPair.JsonString.Value, 2, MaxInt), lPair.JsonValue.Value);

      lFormat := TRdcXmlFormat.RdcmanDefault;
      lValue := aRoot.GetValue('rdgFormat');
      if lValue is TJSONObject then
      begin
        lFormat.HasBom := TJSONObject(lValue).GetValue<Boolean>('bom', True);
        if TJSONObject(lValue).GetValue<string>('lineBreak', 'CRLF') = 'LF' then
          lFormat.LineBreak := #10;
        lFormat.Indent := TJSONObject(lValue).GetValue<string>('indent', '  ');
        lFormat.TrailingLineBreak := TJSONObject(lValue).GetValue<Boolean>('trailingLineBreak', False);
        lFormat.Declaration := TJSONObject(lValue).GetValue<string>('declaration', lFormat.Declaration);
      end;
      FFile.XmlFormat := lFormat;

      lValue := aRoot.GetValue('credentialsProfiles');
      if lValue is TJSONObject then
      begin
        lProfilesObject := TJSONObject(lValue);
        FFile.ProfilesElement := TRdcXmlNode.Create('credentialsProfiles');
        lValue := lProfilesObject.GetValue('attributes');
        if lValue is TJSONObject then
          for lPair in TJSONObject(lValue) do
            FFile.ProfilesElement.SetAttribute(Copy(lPair.JsonString.Value, 2, MaxInt), lPair.JsonValue.Value);
        lValue := lProfilesObject.GetValue('profiles');
        if lValue is TJSONArray then
          for lItem in TJSONArray(lValue) do
            if lItem is TJSONObject then
            begin
              lProfile := TRdcCredentialProfile.Create;
              TRdcJsonFormat.JsonToSection(TJSONObject(lItem), lProfile);
              FFile.Profiles.Add(lProfile);
            end;
      end;

      lValue := aRoot.GetValue('root');
      if not (lValue is TJSONObject) then
        raise ERdcFormatError.CreateFmt(_('%s bevat geen "root".'), [aFileName]);
      ReadNode(FFile, TJSONObject(lValue));

      ReadRefList(aRoot, 'connected', FFile.Connected);
      ReadRefList(aRoot, 'favorites', FFile.Favorites);
      ReadRefList(aRoot, 'recentlyUsed', FFile.RecentlyUsed);
      for lPending in FPending do
      begin
        lNode := FFile.FindByPath(lPending.Value);
        if lNode = nil then
          FFile.Warnings.Add(Format(_('Pad "%s" verwijst niet naar een bestaande node; wordt ongewijzigd bewaard.'), [lPending.Value]));
        lPending.Key.AddPath(lPending.Value, lNode);
      end;

      lValue := aRoot.GetValue('rootUnknownXml');
      if lValue is TJSONArray then
        ReadUnknown(nil, TJSONArray(lValue), FFile.RootUnknown);

      lValue := aRoot.GetValue('sidecarOrphans');
      if lValue is TJSONObject then
        for lPair in TJSONObject(lValue) do
          FFile.SidecarOrphans.AddOrSetValue(lPair.JsonString.Value, lPair.JsonValue.ToJSON);

      TRdcJsonFormat.JsonToDefinitions(aRoot, FFile);

      FFile.Modified := False;
      Result := FFile;
    except
      FFile.Free;
      raise;
    end;
  finally
    FPending.Free;
  end;
end;

class function TRdcJsonFormat.Read(const aBytes: TBytes; const aFileName: string): TRdcFile;
var
  lReader: TJsonReader;
  lValue: TJSONValue;
begin
  lValue := TJSONObject.ParseJSONValue(aBytes, 0, True);
  if not (lValue is TJSONObject) then
  begin
    lValue.Free;
    raise ERdcFormatError.CreateFmt(_('%s is geen geldig JSON-object.'), [aFileName]);
  end;
  lReader := TJsonReader.Create;
  try
    Result := lReader.Read(TJSONObject(lValue), aFileName);
  finally
    lReader.Free;
    lValue.Free;
  end;
end;

end.
