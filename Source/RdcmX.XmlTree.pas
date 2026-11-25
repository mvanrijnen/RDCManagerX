unit RdcmX.XmlTree;

{
  Lichtgewicht XML-elementboom + writer in RDCMan-stijl.

  Waarom een eigen boom en writer (en niet direct de MSXML-DOM)?
  - Round-trip: het model bewaart properties en instellingssecties als elementen, zodat onbekende elementen,
    onbekende enum-waarden en onvolledige secties ongewijzigd terug geschreven worden, zonder dat het model
    alle RDCMan-varianten hoeft te kennen.
  - Byte-identieke uitvoer: RDCMan schrijft met de .NET XmlWriter (2 spaties, CRLF, `<x />` met spatie,
    UTF-8 met BOM, geen regeleinde na het root-element). MSXML schrijft `<x/>` en formatteert anders.
  - Geen COM-levensduur in het model; inlezen via MSXML gebeurt alleen in RdcmX.Storage.Rdg.

  Niet ondersteund (komt in RDCMan-bestanden niet voor): gemengde inhoud (tekst én kind-elementen door elkaar),
  commentaar, processing instructions en CDATA (CDATA wordt als gewone tekst gelezen en ge-escaped geschreven).
}

interface

uses
  System.Classes, System.Generics.Collections, System.SysUtils;

type
  TRdcXmlAttribute = record
    Name: string;
    Value: string;
  end;

  TRdcXmlNode = class
  private
    FName: string;
    FText: string;
    FAttributes: TList<TRdcXmlAttribute>;
    FChildren: TObjectList<TRdcXmlNode>;
  public
    constructor Create(const aName: string; const aText: string = '');
    destructor Destroy; override;
    function Clone: TRdcXmlNode;
    function AddChild(const aName: string; const aText: string = ''): TRdcXmlNode; overload;
    function AddChild(aNode: TRdcXmlNode): TRdcXmlNode; overload;
    function InsertChild(aIndex: Integer; aNode: TRdcXmlNode): TRdcXmlNode;
    function FindChild(const aName: string): TRdcXmlNode;
    function IndexOfChild(const aName: string): Integer;
    procedure RemoveChild(const aName: string);
    function ChildText(const aName: string; const aDefault: string = ''): string;
    function HasAttribute(const aName: string): Boolean;
    function GetAttribute(const aName: string; const aDefault: string = ''): string;
    procedure SetAttribute(const aName, aValue: string);
    procedure RemoveAttribute(const aName: string);
    /// <summary>Diepe vergelijking (naam, attributen in volgorde, tekst, kinderen in volgorde).</summary>
    function IsEqual(aOther: TRdcXmlNode): Boolean;
    property Attributes: TList<TRdcXmlAttribute> read FAttributes;
    property Children: TObjectList<TRdcXmlNode> read FChildren;
    property Name: string read FName write FName;
    property Text: string read FText write FText;
  end;

  /// <summary>Opmaak van een XML-bestand, zodat opslaan dezelfde bytes oplevert als het origineel.</summary>
  TRdcXmlFormat = record
    HasBom: Boolean;
    LineBreak: string;
    Indent: string;
    TrailingLineBreak: Boolean;
    Declaration: string;
    /// <summary>Wat RDCMan 2.90 schrijft.</summary>
    class function RdcmanDefault: TRdcXmlFormat; static;
  end;

  TRdcXmlWriter = class abstract
  public
    class function EscapeText(const aValue: string): string; static;
    class function EscapeAttribute(const aValue: string): string; static;
    /// <summary>Volledig document: declaratie + root, ingesprongen volgens aFormat (zonder BOM; die is voor de bytes).</summary>
    class function DocumentText(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat): string; static;
    /// <summary>Eén element zonder inspringing of regeleinden (voor opslag als tekst, bijv. in JSON).</summary>
    class function CompactText(aNode: TRdcXmlNode): string; static;
    /// <summary>Bytes voor het bestand, inclusief BOM indien aFormat.HasBom.</summary>
    class function DocumentBytes(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat): TBytes; static;
  end;

/// <summary>Zet aValue als tekst van kind-element aName; ontbreekt dat, dan wordt het ingevoegd op de plek die aOrder voorschrijft.</summary>
procedure SetChildTextOrdered(aParent: TRdcXmlNode; const aName, aValue: string; const aOrder: array of string);

implementation

{ TRdcXmlNode }

constructor TRdcXmlNode.Create(const aName: string; const aText: string);
begin
  inherited Create;
  FName := aName;
  FText := aText;
  FAttributes := TList<TRdcXmlAttribute>.Create;
  FChildren := TObjectList<TRdcXmlNode>.Create(True);
end;

destructor TRdcXmlNode.Destroy;
begin
  FChildren.Free;
  FAttributes.Free;
  inherited Destroy;
end;

function TRdcXmlNode.Clone: TRdcXmlNode;
var
  lChild: TRdcXmlNode;
begin
  Result := TRdcXmlNode.Create(FName, FText);
  Result.FAttributes.AddRange(FAttributes);
  for lChild in FChildren do
    Result.FChildren.Add(lChild.Clone);
end;

function TRdcXmlNode.AddChild(const aName: string; const aText: string): TRdcXmlNode;
begin
  Result := AddChild(TRdcXmlNode.Create(aName, aText));
end;

function TRdcXmlNode.AddChild(aNode: TRdcXmlNode): TRdcXmlNode;
begin
  FChildren.Add(aNode);
  Result := aNode;
end;

function TRdcXmlNode.InsertChild(aIndex: Integer; aNode: TRdcXmlNode): TRdcXmlNode;
begin
  FChildren.Insert(aIndex, aNode);
  Result := aNode;
end;

function TRdcXmlNode.IndexOfChild(const aName: string): Integer;
begin
  for Result := 0 to FChildren.Count - 1 do
    if FChildren[Result].FName = aName then
      Exit;
  Result := -1;
end;

function TRdcXmlNode.FindChild(const aName: string): TRdcXmlNode;
var
  lIndex: Integer;
begin
  lIndex := IndexOfChild(aName);
  if lIndex >= 0 then
    Result := FChildren[lIndex]
  else
    Result := nil;
end;

procedure TRdcXmlNode.RemoveChild(const aName: string);
var
  lIndex: Integer;
begin
  lIndex := IndexOfChild(aName);
  if lIndex >= 0 then
    FChildren.Delete(lIndex);
end;

function TRdcXmlNode.ChildText(const aName: string; const aDefault: string): string;
var
  lChild: TRdcXmlNode;
begin
  lChild := FindChild(aName);
  if lChild <> nil then
    Result := lChild.FText
  else
    Result := aDefault;
end;

function TRdcXmlNode.HasAttribute(const aName: string): Boolean;
var
  lAttribute: TRdcXmlAttribute;
begin
  for lAttribute in FAttributes do
    if lAttribute.Name = aName then
      Exit(True);
  Result := False;
end;

function TRdcXmlNode.GetAttribute(const aName: string; const aDefault: string): string;
var
  lAttribute: TRdcXmlAttribute;
begin
  for lAttribute in FAttributes do
    if lAttribute.Name = aName then
      Exit(lAttribute.Value);
  Result := aDefault;
end;

procedure TRdcXmlNode.SetAttribute(const aName, aValue: string);
var
  lAttribute: TRdcXmlAttribute;
  lIndex: Integer;
begin
  for lIndex := 0 to FAttributes.Count - 1 do
    if FAttributes[lIndex].Name = aName then
    begin
      lAttribute := FAttributes[lIndex];
      lAttribute.Value := aValue;
      FAttributes[lIndex] := lAttribute;
      Exit;
    end;
  lAttribute.Name := aName;
  lAttribute.Value := aValue;
  FAttributes.Add(lAttribute);
end;

procedure TRdcXmlNode.RemoveAttribute(const aName: string);
var
  lIndex: Integer;
begin
  for lIndex := FAttributes.Count - 1 downto 0 do
    if FAttributes[lIndex].Name = aName then
      FAttributes.Delete(lIndex);
end;

function TRdcXmlNode.IsEqual(aOther: TRdcXmlNode): Boolean;
var
  lIndex: Integer;
begin
  Result := (aOther <> nil) and (FName = aOther.FName) and (FText = aOther.FText) and (FAttributes.Count = aOther.FAttributes.Count) and (FChildren.Count = aOther.FChildren.Count);
  if not Result then
    Exit;
  for lIndex := 0 to FAttributes.Count - 1 do
    if (FAttributes[lIndex].Name <> aOther.FAttributes[lIndex].Name) or (FAttributes[lIndex].Value <> aOther.FAttributes[lIndex].Value) then
      Exit(False);
  for lIndex := 0 to FChildren.Count - 1 do
    if not FChildren[lIndex].IsEqual(aOther.FChildren[lIndex]) then
      Exit(False);
end;

{ TRdcXmlFormat }

class function TRdcXmlFormat.RdcmanDefault: TRdcXmlFormat;
begin
  Result.HasBom := True;
  Result.LineBreak := #13#10;
  Result.Indent := '  ';
  Result.TrailingLineBreak := False;
  Result.Declaration := '<?xml version="1.0" encoding="utf-8"?>';
end;

{ TRdcXmlWriter }

class function TRdcXmlWriter.EscapeText(const aValue: string): string;
var
  lBuilder: TStringBuilder;
  lChar: Char;
begin
  // Zoals de .NET XmlWriter: &, < en > in tekst.
  lBuilder := TStringBuilder.Create(Length(aValue) + 8);
  try
    for lChar in aValue do
      case lChar of
        '&': lBuilder.Append('&amp;');
        '<': lBuilder.Append('&lt;');
        '>': lBuilder.Append('&gt;');
      else
        lBuilder.Append(lChar);
      end;
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

class function TRdcXmlWriter.EscapeAttribute(const aValue: string): string;
begin
  Result := StringReplace(EscapeText(aValue), '"', '&quot;', [rfReplaceAll]);
end;

procedure WriteNode(aBuilder: TStringBuilder; aNode: TRdcXmlNode; aLevel: Integer; const aFormat: TRdcXmlFormat; aPretty: Boolean);
var
  lAttribute: TRdcXmlAttribute;
  lChild: TRdcXmlNode;
  lIndent: string;
  lIndex: Integer;
begin
  lIndent := '';
  if aPretty then
    for lIndex := 1 to aLevel do
      lIndent := lIndent + aFormat.Indent;
  aBuilder.Append(lIndent).Append('<').Append(aNode.Name);
  for lAttribute in aNode.Attributes do
    aBuilder.Append(' ').Append(lAttribute.Name).Append('="').Append(TRdcXmlWriter.EscapeAttribute(lAttribute.Value)).Append('"');

  if (aNode.Children.Count = 0) and (aNode.Text = '') then
  begin
    aBuilder.Append(' />');
    Exit;
  end;
  aBuilder.Append('>');
  aBuilder.Append(TRdcXmlWriter.EscapeText(aNode.Text));
  if aNode.Children.Count > 0 then
  begin
    for lChild in aNode.Children do
    begin
      if aPretty then
        aBuilder.Append(aFormat.LineBreak);
      WriteNode(aBuilder, lChild, aLevel + 1, aFormat, aPretty);
    end;
    if aPretty then
      aBuilder.Append(aFormat.LineBreak).Append(lIndent);
  end;
  aBuilder.Append('</').Append(aNode.Name).Append('>');
end;

class function TRdcXmlWriter.DocumentText(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat): string;
var
  lBuilder: TStringBuilder;
begin
  lBuilder := TStringBuilder.Create;
  try
    if aFormat.Declaration <> '' then
      lBuilder.Append(aFormat.Declaration).Append(aFormat.LineBreak);
    WriteNode(lBuilder, aRoot, 0, aFormat, True);
    if aFormat.TrailingLineBreak then
      lBuilder.Append(aFormat.LineBreak);
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

class function TRdcXmlWriter.CompactText(aNode: TRdcXmlNode): string;
var
  lBuilder: TStringBuilder;
begin
  lBuilder := TStringBuilder.Create;
  try
    WriteNode(lBuilder, aNode, 0, TRdcXmlFormat.RdcmanDefault, False);
    Result := lBuilder.ToString;
  finally
    lBuilder.Free;
  end;
end;

class function TRdcXmlWriter.DocumentBytes(aRoot: TRdcXmlNode; const aFormat: TRdcXmlFormat): TBytes;
var
  lBody: TBytes;
  lPreamble: TBytes;
begin
  lBody := TEncoding.UTF8.GetBytes(DocumentText(aRoot, aFormat));
  if aFormat.HasBom then
  begin
    lPreamble := TEncoding.UTF8.GetPreamble;
    Result := lPreamble + lBody;
  end
  else
    Result := lBody;
end;

procedure SetChildTextOrdered(aParent: TRdcXmlNode; const aName, aValue: string; const aOrder: array of string);
var
  lChild: TRdcXmlNode;
  lIndex: Integer;
  lInsertAt: Integer;
  lOrderIndex: Integer;
  lOwnOrder: Integer;

  function OrderOf(const aElementName: string): Integer;
  var
    lI: Integer;
  begin
    for lI := Low(aOrder) to High(aOrder) do
      if aOrder[lI] = aElementName then
        Exit(lI);
    Result := MaxInt;
  end;

begin
  lChild := aParent.FindChild(aName);
  if lChild <> nil then
  begin
    lChild.Text := aValue;
    Exit;
  end;
  // Invoegen vóór het eerste bestaande element dat volgens aOrder later komt.
  lOwnOrder := OrderOf(aName);
  lInsertAt := aParent.Children.Count;
  for lIndex := 0 to aParent.Children.Count - 1 do
  begin
    lOrderIndex := OrderOf(aParent.Children[lIndex].Name);
    if (lOrderIndex <> MaxInt) and (lOrderIndex > lOwnOrder) then
    begin
      lInsertAt := lIndex;
      Break;
    end;
  end;
  aParent.InsertChild(lInsertAt, TRdcXmlNode.Create(aName, aValue));
end;

end.
