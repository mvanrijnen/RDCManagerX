unit RdcmX.Storage.Rdg;

{
  RDCMan .rdg lezen en schrijven (alleen bytes <-> model; bestands-I/O zit in RdcmX.Storage).

  XML-keuze: inlezen met Xml.XMLDoc (MSXML-DOM, robuust en standaard aanwezig), daarna omzetten naar de
  lichtgewicht TRdcXmlNode-boom. Schrijven met TRdcXmlWriter, omdat MSXML niet dezelfde bytes produceert als
  RDCMan (.NET XmlWriter: `<x />` met spatie, CRLF, BOM, geen regeleinde aan het eind).

  Round-trip:
  - Properties en secties worden als element bewaard; onbekende kind-elementen gaan dus vanzelf mee.
  - Onbekende elementen op node-niveau (bijv. smartGroup) en direct onder <RDCMan> worden met hun anker
    (het voorgaande bekende element) bewaard en direct daarna teruggeschreven.
  - programVersion/schemaVersion en opmaak (BOM, regeleinde, inspringing, declaratie) blijven behouden.
  - Volgorde bij schrijven: credentialsProfiles, properties, secties (TRdcNodeSettings-volgorde), kinderen.

  Wachtwoorden: de inhoud van <password> wordt bij inlezen verwijderd (met melding in Warnings) en altijd leeg
  geschreven. RDCManX slaat nooit wachtwoorden op.

  RDCManX-extra's (TRdcxSettings) worden NIET in de .rdg geschreven, maar in een sidecar (RdcmX.Storage.Sidecar).

  Niet ondersteund: schemaVersion < 3 (oudere RDCMan-indeling), XML-commentaar (wordt niet bewaard).
}

interface

uses
  System.Classes, System.SysUtils,
  RdcmX.Model, RdcmX.XmlTree;

type
  ERdcFormatError = class(Exception);

  TRdcRdgFormat = class abstract
  public
    /// <summary>Leest een .rdg; aFileName is alleen voor meldingen.</summary>
    class function Read(const aBytes: TBytes; const aFileName: string = ''): TRdcFile; static;
    class function Write(aFile: TRdcFile): TBytes; static;
    /// <summary>Bouwt de XML-boom die Write wegschrijft (voor tests en conversie).</summary>
    class function BuildXml(aFile: TRdcFile): TRdcXmlNode; static;
    /// <summary>XML-bytes naar elementboom; aFormat krijgt de gedetecteerde opmaak.</summary>
    class function ParseXml(const aBytes: TBytes; out aFormat: TRdcXmlFormat): TRdcXmlNode; static;
    class function ParseXmlText(const aText: string): TRdcXmlNode; static;
  end;

implementation

uses
  Winapi.ActiveX, Winapi.Windows,
  System.Generics.Collections, System.Variants,
  Xml.Win.msxmldom, Xml.XMLDoc, Xml.XMLIntf,
  RdcmX.Lang;

const
  cPasswordElement = 'password';

{ XML inlezen }

function ConvertElement(const aNode: IXMLNode): TRdcXmlNode;
var
  lChild: IXMLNode;
  lHasElements: Boolean;
  lIndex: Integer;
  lText: string;
begin
  Result := TRdcXmlNode.Create(aNode.NodeName);
  try
    for lIndex := 0 to aNode.AttributeNodes.Count - 1 do
      Result.SetAttribute(aNode.AttributeNodes[lIndex].NodeName, VarToStr(aNode.AttributeNodes[lIndex].NodeValue));
    lText := '';
    lHasElements := False;
    for lIndex := 0 to aNode.ChildNodes.Count - 1 do
    begin
      lChild := aNode.ChildNodes[lIndex];
      case lChild.NodeType of
        ntElement:
          begin
            Result.AddChild(ConvertElement(lChild));
            lHasElements := True;
          end;
        ntText, ntCData:
          lText := lText + VarToStr(lChild.NodeValue);
      end;
    end;
    // Witruimte tussen kind-elementen is opmaak, geen inhoud.
    if not lHasElements then
      Result.Text := lText
    else if Trim(lText) <> '' then
      Result.Text := Trim(lText);
  except
    Result.Free;
    raise;
  end;
end;

function DetectFormat(const aBytes: TBytes; out aText: string): TRdcXmlFormat;
var
  lBomLength: Integer;
  lDeclarationEnd: Integer;
  lLineStart: Integer;
  lPos: Integer;
begin
  Result := TRdcXmlFormat.RdcmanDefault;
  lBomLength := 0;
  Result.HasBom := (Length(aBytes) >= 3) and (aBytes[0] = $EF) and (aBytes[1] = $BB) and (aBytes[2] = $BF);
  if Result.HasBom then
    lBomLength := 3;
  aText := TEncoding.UTF8.GetString(aBytes, lBomLength, Length(aBytes) - lBomLength);

  if Pos(#13#10, aText) > 0 then
    Result.LineBreak := #13#10
  else if Pos(#10, aText) > 0 then
    Result.LineBreak := #10;
  Result.TrailingLineBreak := aText.EndsWith(#10);

  Result.Declaration := '';
  if aText.StartsWith('<?xml') then
  begin
    lDeclarationEnd := Pos('?>', aText);
    if lDeclarationEnd > 0 then
      Result.Declaration := Copy(aText, 1, lDeclarationEnd + 1);
  end;

  // Inspringing: witruimte vóór het eerste kind-element van de root (derde regel bij een declaratie).
  lPos := Pos(Result.LineBreak + '<', aText);
  if lPos > 0 then
  begin
    lLineStart := Pos(Result.LineBreak, aText, lPos + Length(Result.LineBreak));
    if lLineStart > 0 then
    begin
      lPos := lLineStart + Length(Result.LineBreak);
      Result.Indent := '';
      while (lPos <= Length(aText)) and CharInSet(aText[lPos], [' ', #9]) do
      begin
        Result.Indent := Result.Indent + aText[lPos];
        Inc(lPos);
      end;
      if Result.Indent = '' then
        Result.Indent := '  ';
    end;
  end;
end;

function ParseDocument(const aText: string): TRdcXmlNode;
var
  lComInitialized: Boolean;
  lDocument: IXMLDocument;
begin
  lComInitialized := Succeeded(CoInitializeEx(nil, COINIT_APARTMENTTHREADED));
  try
    lDocument := TXMLDocument.Create(nil);
    lDocument.ParseOptions := [poPreserveWhiteSpace];
    lDocument.LoadFromXML(aText);
    lDocument.Active := True;
    if lDocument.DocumentElement = nil then
      raise ERdcFormatError.Create(_('Leeg XML-document.'));
    Result := ConvertElement(lDocument.DocumentElement);
    lDocument := nil;
  finally
    if lComInitialized then
      CoUninitialize;
  end;
end;

class function TRdcRdgFormat.ParseXml(const aBytes: TBytes; out aFormat: TRdcXmlFormat): TRdcXmlNode;
var
  lText: string;
begin
  aFormat := DetectFormat(aBytes, lText);
  // De declaratie noemt encoding="utf-8"; LoadFromXML krijgt al gedecodeerde tekst, dus declaratie weglaten.
  if aFormat.Declaration <> '' then
    lText := Copy(lText, Length(aFormat.Declaration) + 1, MaxInt);
  Result := ParseDocument(lText);
end;

class function TRdcRdgFormat.ParseXmlText(const aText: string): TRdcXmlNode;
begin
  Result := ParseDocument(aText);
end;

{ Model opbouwen }

type
  TRdgReader = class
  private
    FFile: TRdcFile;
    FFileName: string;
    procedure CopyElementInto(aTarget, aSource: TRdcXmlNode);
    procedure ReadList(aList: TRdcNodeRefList; aElement: TRdcXmlNode; aPaths: TList<TPair<TRdcNodeRefList, string>>);
    procedure ReadNodeContent(aNode: TRdcNode; aElement: TRdcXmlNode);
    procedure ReadProfiles(aElement: TRdcXmlNode);
    procedure StripPasswords(aElement: TRdcXmlNode; const aContext: string);
  public
    function Read(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat; const aFileName: string): TRdcFile;
  end;

procedure TRdgReader.CopyElementInto(aTarget, aSource: TRdcXmlNode);
var
  lChild: TRdcXmlNode;
begin
  aTarget.Attributes.Clear;
  aTarget.Attributes.AddRange(aSource.Attributes);
  aTarget.Children.Clear;
  for lChild in aSource.Children do
    aTarget.AddChild(lChild.Clone);
  aTarget.Text := aSource.Text;
end;

procedure TRdgReader.StripPasswords(aElement: TRdcXmlNode; const aContext: string);
var
  lPassword: TRdcXmlNode;
begin
  lPassword := aElement.FindChild(cPasswordElement);
  if (lPassword <> nil) and (lPassword.Text <> '') then
  begin
    lPassword.Text := '';
    FFile.Warnings.Add(Format(_('Opgeslagen wachtwoord genegeerd bij %s; RDCManX slaat geen wachtwoorden op en schrijft het niet terug.'), [aContext]));
  end;
end;

procedure TRdgReader.ReadProfiles(aElement: TRdcXmlNode);
var
  lChild: TRdcXmlNode;
  lElement: TRdcXmlNode;
  lProfile: TRdcCredentialProfile;
begin
  lElement := TRdcXmlNode.Create(aElement.Name);
  lElement.Attributes.AddRange(aElement.Attributes);
  FFile.ProfilesElement := lElement;
  for lChild in aElement.Children do
  begin
    if lChild.Name <> TRdcCredentialProfile.XmlName then
    begin
      FFile.Warnings.Add(Format(_('Onbekend element <%s> in credentialsProfiles genegeerd.'), [lChild.Name]));
      Continue;
    end;
    lProfile := TRdcCredentialProfile.Create;
    lProfile.ReplaceNode(lChild.Clone);
    lProfile.Inherit := False;
    StripPasswords(lProfile.Node, 'credential-profiel "' + lProfile.ProfileName + '"');
    FFile.Profiles.Add(lProfile);
  end;
end;

procedure TRdgReader.ReadNodeContent(aNode: TRdcNode; aElement: TRdcXmlNode);
var
  lAnchorName: string;
  lAnchorNode: TRdcNode;
  lChild: TRdcXmlNode;
  lChildNode: TRdcNode;
  lSection: TRdcSettingsGroup;
  lUnknown: TRdcUnknownElement;
begin
  aNode.ElementAttributes.Attributes.AddRange(aElement.Attributes);
  lAnchorName := '';
  lAnchorNode := nil;
  for lChild in aElement.Children do
  begin
    if (aNode is TRdcFile) and (lChild.Name = 'credentialsProfiles') then
    begin
      ReadProfiles(lChild);
      lAnchorName := lChild.Name;
      lAnchorNode := nil;
      Continue;
    end;
    if lChild.Name = 'properties' then
    begin
      CopyElementInto(aNode.Properties, lChild);
      lAnchorName := lChild.Name;
      lAnchorNode := nil;
      Continue;
    end;
    lSection := aNode.Settings.FindByXmlName(lChild.Name);
    if (lSection <> nil) and lSection.InRdg then
    begin
      lSection.ReplaceNode(lChild.Clone);
      // Ontbrekende sectie = overerven; aanwezig met inherit="None" (of zonder attribuut) = eigen waarden.
      lSection.Inherit := lChild.HasAttribute('inherit') and not SameText(lChild.GetAttribute('inherit'), cRdcInheritNone);
      if (lSection is TRdcLogonCredentials) or (lSection is TRdcGatewaySettings) then
        StripPasswords(lSection.Node, '"' + aNode.Caption + '" (' + lChild.Name + ')');
      lAnchorName := lChild.Name;
      lAnchorNode := nil;
      Continue;
    end;
    if (aNode is TRdcGroup) and ((lChild.Name = 'group') or (lChild.Name = 'server')) then
    begin
      if lChild.Name = 'group' then
        lChildNode := TRdcGroup.Create('')
      else
        lChildNode := TRdcServer.Create('');
      TRdcGroup(aNode).Add(lChildNode);
      ReadNodeContent(lChildNode, lChild);
      lAnchorName := '';
      lAnchorNode := lChildNode;
      Continue;
    end;
    // Onbekend element: ongewijzigd bewaren, verankerd aan het voorgaande element.
    lUnknown := TRdcUnknownElement.Create;
    lUnknown.Element := lChild.Clone;
    lUnknown.AnchorName := lAnchorName;
    lUnknown.AnchorNode := lAnchorNode;
    aNode.Unknown.Add(lUnknown);
  end;
end;

procedure TRdgReader.ReadList(aList: TRdcNodeRefList; aElement: TRdcXmlNode; aPaths: TList<TPair<TRdcNodeRefList, string>>);
var
  lChild: TRdcXmlNode;
begin
  aList.Present := True;
  for lChild in aElement.Children do
    aPaths.Add(TPair<TRdcNodeRefList, string>.Create(aList, lChild.Text));
end;

function TRdgReader.Read(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat; const aFileName: string): TRdcFile;
var
  lAnchorName: string;
  lChild: TRdcXmlNode;
  lFileFound: Boolean;
  lNode: TRdcNode;
  lPair: TPair<TRdcNodeRefList, string>;
  lPaths: TList<TPair<TRdcNodeRefList, string>>;
  lSchemaVersion: Integer;
  lUnknown: TRdcUnknownElement;
begin
  FFileName := aFileName;
  if aRoot.Name <> 'RDCMan' then
    raise ERdcFormatError.CreateFmt(_('%s is geen RDCMan-bestand (root-element <%s>).'), [aFileName, aRoot.Name]);
  lSchemaVersion := StrToIntDef(aRoot.GetAttribute('schemaVersion'), 0);
  if lSchemaVersion < 3 then
    raise ERdcFormatError.CreateFmt(_('%s heeft schemaVersion %s; alleen schemaVersion 3 (RDCMan 2.7 en nieuwer) wordt ondersteund.'), [aFileName, aRoot.GetAttribute('schemaVersion')]);

  FFile := TRdcFile.Create('');
  lPaths := TList<TPair<TRdcNodeRefList, string>>.Create;
  try
    try
      FFile.XmlFormat := aFormat;
      FFile.Format := ffRdg;
      FFile.RootElement.Attributes.Clear;
      FFile.RootElement.Attributes.AddRange(aRoot.Attributes);
      // Lijsten die niet in het bestand staan, ook niet terugschrijven.
      FFile.Connected.Present := False;
      FFile.Favorites.Present := False;
      FFile.RecentlyUsed.Present := False;

      lFileFound := False;
      lAnchorName := '';
      for lChild in aRoot.Children do
      begin
        if (lChild.Name = 'file') and not lFileFound then
        begin
          lFileFound := True;
          ReadNodeContent(FFile, lChild);
        end
        else if lChild.Name = 'connected' then
          ReadList(FFile.Connected, lChild, lPaths)
        else if lChild.Name = 'favorites' then
          ReadList(FFile.Favorites, lChild, lPaths)
        else if lChild.Name = 'recentlyUsed' then
          ReadList(FFile.RecentlyUsed, lChild, lPaths)
        else
        begin
          lUnknown := TRdcUnknownElement.Create;
          lUnknown.Element := lChild.Clone;
          lUnknown.AnchorName := lAnchorName;
          FFile.RootUnknown.Add(lUnknown);
        end;
        lAnchorName := lChild.Name;
      end;
      if not lFileFound then
        raise ERdcFormatError.CreateFmt(_('%s bevat geen <file>-element.'), [aFileName]);

      // Paden pas herleiden als de hele boom staat.
      for lPair in lPaths do
      begin
        lNode := FFile.FindByPath(lPair.Value);
        if lNode = nil then
          FFile.Warnings.Add(Format(_('Pad "%s" verwijst niet naar een bestaande node; wordt ongewijzigd bewaard.'), [lPair.Value]));
        lPair.Key.AddPath(lPair.Value, lNode);
      end;
      FFile.Modified := False;
      Result := FFile;
    except
      FFile.Free;
      raise;
    end;
  finally
    lPaths.Free;
  end;
end;

class function TRdcRdgFormat.Read(const aBytes: TBytes; const aFileName: string): TRdcFile;
var
  lFormat: TRdcXmlFormat;
  lReader: TRdgReader;
  lRoot: TRdcXmlNode;
begin
  lRoot := ParseXml(aBytes, lFormat);
  lReader := TRdgReader.Create;
  try
    Result := lReader.Read(lRoot, lFormat, aFileName);
  finally
    lReader.Free;
    lRoot.Free;
  end;
end;

{ Schrijven }

type
  TRdgWriter = class
  private
    procedure EmitUnknown(aTarget: TRdcXmlNode; aUnknown: TObjectList<TRdcUnknownElement>; const aAnchorName: string; aAnchorNode: TRdcNode; aEmitted: TList<TRdcUnknownElement>);
    function BuildNode(aNode: TRdcNode; const aElementName: string): TRdcXmlNode;
    function BuildList(const aName: string; aList: TRdcNodeRefList): TRdcXmlNode;
    procedure ClearPassword(aElement: TRdcXmlNode);
  public
    function Build(aFile: TRdcFile): TRdcXmlNode;
  end;

procedure TRdgWriter.ClearPassword(aElement: TRdcXmlNode);
var
  lPassword: TRdcXmlNode;
begin
  lPassword := aElement.FindChild(cPasswordElement);
  if lPassword <> nil then
    lPassword.Text := '';
end;

procedure TRdgWriter.EmitUnknown(aTarget: TRdcXmlNode; aUnknown: TObjectList<TRdcUnknownElement>; const aAnchorName: string; aAnchorNode: TRdcNode; aEmitted: TList<TRdcUnknownElement>);
var
  lUnknown: TRdcUnknownElement;
begin
  for lUnknown in aUnknown do
    if not aEmitted.Contains(lUnknown) and (lUnknown.AnchorNode = aAnchorNode) and ((aAnchorNode <> nil) or (lUnknown.AnchorName = aAnchorName)) then
    begin
      aTarget.AddChild(lUnknown.Element.Clone);
      aEmitted.Add(lUnknown);
    end;
end;

function TRdgWriter.BuildNode(aNode: TRdcNode; const aElementName: string): TRdcXmlNode;
var
  lChild: TRdcNode;
  lEmitted: TList<TRdcUnknownElement>;
  lFile: TRdcFile;
  lIndex: Integer;
  lProfile: TRdcCredentialProfile;
  lProfiles: TRdcXmlNode;
  lSection: TRdcSettingsGroup;
  lSectionElement: TRdcXmlNode;
  lUnknown: TRdcUnknownElement;
begin
  Result := TRdcXmlNode.Create(aElementName);
  Result.Attributes.AddRange(aNode.ElementAttributes.Attributes);
  lEmitted := TList<TRdcUnknownElement>.Create;
  try
    EmitUnknown(Result, aNode.Unknown, '', nil, lEmitted);

    if aNode is TRdcFile then
    begin
      lFile := TRdcFile(aNode);
      if (lFile.ProfilesElement <> nil) or (lFile.Profiles.Count > 0) then
      begin
        lProfiles := Result.AddChild('credentialsProfiles');
        if lFile.ProfilesElement <> nil then
          lProfiles.Attributes.AddRange(lFile.ProfilesElement.Attributes);
        for lProfile in lFile.Profiles do
        begin
          lSectionElement := lProfiles.AddChild(lProfile.Node.Clone);
          ClearPassword(lSectionElement);
        end;
        EmitUnknown(Result, aNode.Unknown, 'credentialsProfiles', nil, lEmitted);
      end;
    end;

    Result.AddChild(aNode.Properties.Clone);
    EmitUnknown(Result, aNode.Unknown, 'properties', nil, lEmitted);

    for lSection in aNode.Settings.Groups do
    begin
      if not lSection.InRdg or lSection.Inherit then
        Continue;
      lSectionElement := lSection.Node.Clone;
      lSectionElement.Name := lSection.XmlName;
      if lSectionElement.HasAttribute('inherit') then
        lSectionElement.SetAttribute('inherit', cRdcInheritNone)
      else
      begin
        lSectionElement.SetAttribute('inherit', cRdcInheritNone);
        // inherit als eerste attribuut, zoals RDCMan.
        lSectionElement.Attributes.Move(lSectionElement.Attributes.Count - 1, 0);
      end;
      ClearPassword(lSectionElement);
      Result.AddChild(lSectionElement);
      EmitUnknown(Result, aNode.Unknown, lSection.XmlName, nil, lEmitted);
    end;

    if aNode is TRdcGroup then
      for lIndex := 0 to TRdcGroup(aNode).Count - 1 do
      begin
        lChild := TRdcGroup(aNode)[lIndex];
        if lChild is TRdcGroup then
          Result.AddChild(BuildNode(lChild, 'group'))
        else
          Result.AddChild(BuildNode(lChild, 'server'));
        EmitUnknown(Result, aNode.Unknown, '', lChild, lEmitted);
      end;

    // Onbekende elementen waarvan het anker niet meer bestaat (bijv. sectie nu overgeërfd): achteraan.
    for lUnknown in aNode.Unknown do
      if not lEmitted.Contains(lUnknown) then
        Result.AddChild(lUnknown.Element.Clone);
  finally
    lEmitted.Free;
  end;
end;

function TRdgWriter.BuildList(const aName: string; aList: TRdcNodeRefList): TRdcXmlNode;
var
  lIndex: Integer;
begin
  Result := TRdcXmlNode.Create(aName);
  for lIndex := 0 to aList.Count - 1 do
    Result.AddChild('server', aList.CurrentPath(lIndex));
end;

function TRdgWriter.Build(aFile: TRdcFile): TRdcXmlNode;
var
  lEmitted: TList<TRdcUnknownElement>;
  lUnknown: TRdcUnknownElement;

  procedure EmitRoot(const aAnchor: string);
  var
    lItem: TRdcUnknownElement;
  begin
    for lItem in aFile.RootUnknown do
      if not lEmitted.Contains(lItem) and (lItem.AnchorName = aAnchor) then
      begin
        Result.AddChild(lItem.Element.Clone);
        lEmitted.Add(lItem);
      end;
  end;

begin
  Result := TRdcXmlNode.Create('RDCMan');
  lEmitted := TList<TRdcUnknownElement>.Create;
  try
    Result.Attributes.AddRange(aFile.RootElement.Attributes);
    EmitRoot('');
    Result.AddChild(BuildNode(aFile, 'file'));
    EmitRoot('file');
    if aFile.Connected.Present or (aFile.Connected.Count > 0) then
    begin
      Result.AddChild(BuildList('connected', aFile.Connected));
      EmitRoot('connected');
    end;
    if aFile.Favorites.Present or (aFile.Favorites.Count > 0) then
    begin
      Result.AddChild(BuildList('favorites', aFile.Favorites));
      EmitRoot('favorites');
    end;
    if aFile.RecentlyUsed.Present or (aFile.RecentlyUsed.Count > 0) then
    begin
      Result.AddChild(BuildList('recentlyUsed', aFile.RecentlyUsed));
      EmitRoot('recentlyUsed');
    end;
    for lUnknown in aFile.RootUnknown do
      if not lEmitted.Contains(lUnknown) then
        Result.AddChild(lUnknown.Element.Clone);
  finally
    lEmitted.Free;
  end;
end;

class function TRdcRdgFormat.BuildXml(aFile: TRdcFile): TRdcXmlNode;
var
  lWriter: TRdgWriter;
begin
  lWriter := TRdgWriter.Create;
  try
    Result := lWriter.Build(aFile);
  finally
    lWriter.Free;
  end;
end;

class function TRdcRdgFormat.Write(aFile: TRdcFile): TBytes;
var
  lRoot: TRdcXmlNode;
begin
  lRoot := BuildXml(aFile);
  try
    Result := TRdcXmlWriter.DocumentBytes(lRoot, aFile.XmlFormat);
  finally
    lRoot.Free;
  end;
end;

end.
