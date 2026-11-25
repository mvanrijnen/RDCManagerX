unit RdcmX.Storage.Sidecar;

(*
  Sidecar <bestand>.rdg.rdcx.json: RDCManX-secties (InRdg = False: rdcmx, rdcmxHost) die niet in de .rdg
  mogen, omdat RDCMan over onbekende elementen kan struikelen.

    {
      "formatVersion": 1,
      "nodes": {
        "CONTOSO\\100 - Servers\\210 - appserver01 (appserver)": { "rdcmx": { "inherit": false, "displayMode": "Fixed" } },
        "CONTOSO\\...\\naam#2": { ... }      // #2, #3 ... bij dubbele captions op hetzelfde niveau
      }
    }

  Per node een object met de eigen (niet-overgeërfde) RDCManX-secties, bijv. ook
  "rdcmxHost": { "inherit": false, "macAddress": "00-11-22-33-44-55" } en
  "rdcmxRoute": { "inherit": false, "route": "Tailscale", "tailnetId": "{GUID}" }.
  Daarnaast op het hoogste niveau "tailnets" en "gateways" (definities per bestand, zie RdcmX.Storage.Json; zonder
  geheimen). Nodes zonder eigen sectie ontbreken. Een entry zonder bijbehorende node
  geeft een waarschuwing en wordt bewaard (TRdcFile.SidecarOrphans) en weer teruggeschreven.
*)

interface

uses
  System.SysUtils,
  RdcmX.Model;

type
  TRdcSidecar = class abstract
  public
    class function FileNameFor(const aRdgFileName: string): string; static;
    /// <summary>JSON-tekst voor de sidecar, of '' als er niets te bewaren is.</summary>
    class function Build(aFile: TRdcFile): string; static;
    /// <summary>Past de sidecar toe op een net ingelezen .rdg-model.</summary>
    class procedure Apply(aFile: TRdcFile; const aJson: string); static;
  end;

implementation

uses
  System.Classes, System.Generics.Collections, System.JSON,
  RdcmX.Lang, RdcmX.Storage.Json;

const
  cSidecarExtension = '.rdcx.json';
  cSidecarFormatVersion = 1;

class function TRdcSidecar.FileNameFor(const aRdgFileName: string): string;
begin
  Result := aRdgFileName + cSidecarExtension;
end;

class function TRdcSidecar.Build(aFile: TRdcFile): string;
var
  lEntry: TJSONObject;
  lNode: TRdcNode;
  lNodes: TList<TRdcNode>;
  lSection: TRdcSettingsGroup;
  lNodesObject: TJSONObject;
  lOrphan: TPair<string, string>;
  lRoot: TJSONObject;
begin
  lRoot := TJSONObject.Create;
  lNodes := TList<TRdcNode>.Create;
  try
    lRoot.AddPair('formatVersion', TJSONNumber.Create(cSidecarFormatVersion));
    lNodesObject := TJSONObject.Create;
    lRoot.AddPair('nodes', lNodesObject);
    lNodes.Add(aFile);
    aFile.CollectNodes(lNodes);
    for lNode in lNodes do
    begin
      lEntry := nil;
      for lSection in lNode.Settings.Groups do
        if not lSection.InRdg and not lSection.Inherit then
        begin
          if lEntry = nil then
          begin
            lEntry := TJSONObject.Create;
            lNodesObject.AddPair(lNode.Path(True), lEntry);
          end;
          lEntry.AddPair(lSection.XmlName, TRdcJsonFormat.SectionToJson(lSection));
        end;
    end;
    for lOrphan in aFile.SidecarOrphans do
      if lNodesObject.GetValue(lOrphan.Key) = nil then
        lNodesObject.AddPair(lOrphan.Key, TJSONObject.ParseJSONValue(lOrphan.Value));
    TRdcJsonFormat.DefinitionsToJson(aFile, lRoot);
    if (lNodesObject.Count = 0) and (aFile.Tailnets.Count = 0) and (aFile.Gateways.Count = 0) then
      Result := ''
    else
      Result := TRdcJsonFormat.FormatJson(lRoot);
  finally
    lNodes.Free;
    lRoot.Free;
  end;
end;

class procedure TRdcSidecar.Apply(aFile: TRdcFile; const aJson: string);
var
  lNode: TRdcNode;
  lNodes: TJSONValue;
  lPair: TJSONPair;
  lRoot: TJSONValue;
  lSection: TRdcSettingsGroup;
  lSectionPair: TJSONPair;
  lUsable: Boolean;
begin
  lRoot := TJSONObject.ParseJSONValue(aJson);
  try
    if not (lRoot is TJSONObject) then
    begin
      aFile.Warnings.Add(_('Sidecar-bestand is geen geldige JSON en is genegeerd.'));
      Exit;
    end;
    if TJSONObject(lRoot).GetValue<Integer>('formatVersion', 0) > cSidecarFormatVersion then
    begin
      aFile.Warnings.Add(_('Sidecar-bestand heeft een nieuwere formatVersion en is genegeerd.'));
      Exit;
    end;
    TRdcJsonFormat.JsonToDefinitions(TJSONObject(lRoot), aFile);
    lNodes := TJSONObject(lRoot).GetValue('nodes');
    if not (lNodes is TJSONObject) then
      Exit;
    for lPair in TJSONObject(lNodes) do
    begin
      lNode := aFile.FindByPath(lPair.JsonString.Value);
      // Bruikbaar: bestaande node met alleen bekende RDCManX-secties; anders ongewijzigd bewaren.
      lUsable := (lNode <> nil) and (lPair.JsonValue is TJSONObject) and (TJSONObject(lPair.JsonValue).Count > 0);
      if lUsable then
        for lSectionPair in TJSONObject(lPair.JsonValue) do
        begin
          lSection := lNode.Settings.FindByXmlName(lSectionPair.JsonString.Value);
          if (lSection = nil) or lSection.InRdg or not (lSectionPair.JsonValue is TJSONObject) then
            lUsable := False;
        end;
      if not lUsable then
      begin
        aFile.Warnings.Add(Format(_('Sidecar-entry "%s" hoort bij geen bestaande node; wordt bewaard.'), [lPair.JsonString.Value]));
        aFile.SidecarOrphans.AddOrSetValue(lPair.JsonString.Value, lPair.JsonValue.ToJSON);
        Continue;
      end;
      for lSectionPair in TJSONObject(lPair.JsonValue) do
        TRdcJsonFormat.JsonToSection(TJSONObject(lSectionPair.JsonValue), lNode.Settings.FindByXmlName(lSectionPair.JsonString.Value));
    end;
  finally
    lRoot.Free;
  end;
end;

end.
