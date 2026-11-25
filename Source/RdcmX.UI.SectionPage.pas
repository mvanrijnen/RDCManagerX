unit RdcmX.UI.SectionPage;

{
  Generiek tabblad in de eigenschappen-dialoog: een vinkje "Overnemen van ..." plus velden die elk aan één
  kind-element van een instellingssectie gekoppeld zijn (tekst, getal, ja/nee of keuzelijst).

  - Een tabblad kan velden uit meerdere secties bevatten (AddSection; bijv. Weergave = remoteDesktop +
    displaySettings + rdcmx). Het ene vinkje geldt dan voor al die secties samen, zodat er geen tegenstrijdige
    combinaties ontstaan (bijv. schaal geërfd van de groep maar weergavemodus eigen).
  - Vinkje aan: de velden tonen (uitgeschakeld) de geërfde waarden; de eigen waarden blijven in de werkkopie.
  - Vinkje uit: secties die nog leeg zijn krijgen de geërfde waarden als startpunt (zoals RDCMan).
  - Een sectie die bij openen geërfd werd en waarvan de gebruiker niets wijzigde, blijft erven. Zo verandert
    een OK zonder wijzigingen niets aan het bestand.
  - Opslaan schrijft alleen velden waarvan de waarde echt veranderd is. Een onbekende waarde uit het bestand
    (bijv. een enum-waarde die RDCManX niet kent) blijft daardoor staan zolang de gebruiker het veld niet wijzigt.
}

interface

uses
  Winapi.Windows,
  System.Classes, System.Generics.Collections, System.SysUtils,
  Vcl.ComCtrls, Vcl.Controls, Vcl.Graphics, Vcl.StdCtrls,
  RdcmX.Model;

type
  TRdcFieldKind = (fkText, fkInt, fkBool, fkChoice);

  TRdcPageSection = class
  public
    Work: TRdcSettingsGroup;
    InheritedFrom: TRdcSettingsGroup;
    /// <summary>Sectie erfde bij het openen van de dialoog.</summary>
    InitiallyInherited: Boolean;
    /// <summary>Gebruiker wijzigde een veld van deze sectie (of zette het vinkje bewust uit).</summary>
    Touched: Boolean;
  end;

  TRdcFieldBinding = class
  public
    Section: TRdcPageSection;
    Element: string;
    Kind: TRdcFieldKind;
    Caption: string;
    Control: TWinControl;
    LabelControl: TLabel;
    /// <summary>fkChoice: de RDCMan-waarden, in dezelfde volgorde als de items van de keuzelijst.</summary>
    Values: TArray<string>;
    MinValue: Integer;
    MaxValue: Integer;
  end;

  /// <summary>Is het veld (element) nu van toepassing? Bijv. alleen bij een bepaalde keuze in een ander veld.</summary>
  TRdcFieldApplies = reference to function(const aElement: string): Boolean;

  TRdcSectionPage = class
  private
    FSheet: TTabSheet;
    FInheritBox: TCheckBox;
    FSections: TObjectList<TRdcPageSection>;
    FCurrent: TRdcPageSection;
    FFields: TObjectList<TRdcFieldBinding>;
    FTop: Integer;
    FLoading: Boolean;
    FPrepared: Boolean;
    FOnChanged: TNotifyEvent;
    FFieldApplies: TRdcFieldApplies;
    procedure UpdateEnabled;
    procedure InheritClick(Sender: TObject);
    procedure FieldChanged(Sender: TObject);
    function Scale(aValue: Integer): Integer;
    function NewLabel(const aCaption: string): TLabel;
    function AddField(aKind: TRdcFieldKind; const aElement, aCaption: string; aControl: TWinControl; aLabel: TLabel): TRdcFieldBinding;
    function FindField(const aElement: string): TRdcFieldBinding;
    function FieldOfControl(aControl: TObject): TRdcFieldBinding;
    function ChoiceIndex(aField: TRdcFieldBinding; const aStored: string): Integer;
    function ControlText(aField: TRdcFieldBinding): string;
    function NormalizedText(aField: TRdcFieldBinding; const aStored: string): string;
    procedure ShowField(aField: TRdcFieldBinding; const aStored: string);
    procedure ShowValues(aInherited: Boolean);
    procedure StoreInto(aSection: TRdcPageSection);
    procedure UseInheritedAsStart;
    procedure PrepareOnce;
    procedure InheritToggled;
    procedure FieldEdited(aSender: TObject);
    function GetIsOwn: Boolean;
  public
    constructor Create(aPageControl: TPageControl; const aCaption, aInheritCaption: string; aWork, aInherited: TRdcSettingsGroup);
    destructor Destroy; override;
    /// <summary>Nog een sectie op dit tabblad (de volgende Add*-velden horen erbij); valt onder hetzelfde vinkje.</summary>
    procedure AddSection(aWork, aInherited: TRdcSettingsGroup);
    /// <summary>Volgende Add*-velden horen bij deze (eerder toegevoegde) sectie.</summary>
    procedure UseSection(aWork: TRdcSettingsGroup);
    function AddCheck(const aElement, aCaption: string): TCheckBox;
    function AddText(const aElement, aCaption: string; aWidth: Integer = 300): TEdit;
    function AddNumber(const aElement, aCaption: string; aMin, aMax: Integer): TEdit;
    function AddChoice(const aElement, aCaption: string; const aValues, aCaptions: array of string): TComboBox;
    /// <summary>Vrije tekst met suggesties (bijv. de schermgrootte "1920 x 1080").</summary>
    function AddSuggestions(const aElement, aCaption: string; const aItems: array of string): TComboBox;
    procedure AddHint(const aText: string);
    /// <summary>Velden vullen volgens het vinkje (geërfd of eigen) en in-/uitschakelen.</summary>
    procedure Refresh;
    /// <summary>Inherit-vlaggen en gewijzigde waarden naar de werkkopie (bij OK).</summary>
    procedure ApplyToWork;
    function Validate(out aControl: TWinControl; out aMessage: string): Boolean;
    /// <summary>Huidige waarde van een veld als RDCMan-tekst.</summary>
    function FieldValue(const aElement: string): string;
    /// <summary>Veld programmatisch zetten (alleen als het tabblad eigen waarden heeft); geen OnChanged.</summary>
    procedure SetFieldValue(const aElement, aText: string);
    /// <summary>Uitleg (tooltip) bij een veld en zijn label; onbekend veld = niets doen.</summary>
    procedure SetHint(const aElement, aHint: string);
    property IsOwn: Boolean read GetIsOwn;
    property Sheet: TTabSheet read FSheet;
    /// <summary>Na een wijziging door de gebruiker (niet tijdens laden).</summary>
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    /// <summary>Optioneel: velden die nu niet van toepassing zijn worden grijs (ook met eigen waarden).</summary>
    property FieldApplies: TRdcFieldApplies read FFieldApplies write FFieldApplies;
  end;

implementation

uses
  RdcmX.Lang;

const
  cLeft = 12;
  cControlLeft = 230;
  cControlWidth = 280;
  cRowHeight = 30;
  cCheckHeight = 24;

constructor TRdcSectionPage.Create(aPageControl: TPageControl; const aCaption, aInheritCaption: string; aWork, aInherited: TRdcSettingsGroup);
begin
  inherited Create;
  FSections := TObjectList<TRdcPageSection>.Create(True);
  FFields := TObjectList<TRdcFieldBinding>.Create(True);
  FSheet := TTabSheet.Create(aPageControl.Owner);
  FSheet.PageControl := aPageControl;
  FSheet.Caption := aCaption;
  FTop := Scale(14);
  FInheritBox := TCheckBox.Create(FSheet);
  FInheritBox.Parent := FSheet;
  FInheritBox.SetBounds(Scale(cLeft), FTop, Scale(cControlLeft + cControlWidth - cLeft), Scale(17));
  FInheritBox.Hint := _('Aan: deze instellingen komen van de bovenliggende groep (of de standaard). Uit: eigen instellingen voor deze server of groep.');
  FInheritBox.ShowHint := True;
  FInheritBox.Caption := aInheritCaption;
  FInheritBox.OnClick := InheritClick;
  Inc(FTop, Scale(34));
  AddSection(aWork, aInherited);
end;

destructor TRdcSectionPage.Destroy;
begin
  FFields.Free;
  FSections.Free;
  inherited Destroy;
end;

procedure TRdcSectionPage.AddSection(aWork, aInherited: TRdcSettingsGroup);
var
  lAllInherit: Boolean;
  lSection: TRdcPageSection;
begin
  FCurrent := TRdcPageSection.Create;
  FCurrent.Work := aWork;
  FCurrent.InheritedFrom := aInherited;
  FCurrent.InitiallyInherited := aWork.Inherit;
  FSections.Add(FCurrent);
  // Het vinkje staat alleen aan als álle secties van dit tabblad erven.
  lAllInherit := True;
  for lSection in FSections do
    lAllInherit := lAllInherit and lSection.Work.Inherit;
  FLoading := True;
  try
    FInheritBox.Checked := lAllInherit;
  finally
    FLoading := False;
  end;
end;

procedure TRdcSectionPage.UseSection(aWork: TRdcSettingsGroup);
var
  lSection: TRdcPageSection;
begin
  for lSection in FSections do
    if lSection.Work = aWork then
    begin
      FCurrent := lSection;
      Exit;
    end;
  raise EArgumentException.Create('Sectie hoort niet bij dit tabblad');
end;

function TRdcSectionPage.Scale(aValue: Integer): Integer;
begin
  Result := MulDiv(aValue, FSheet.PageControl.CurrentPPI, 96);
end;

function TRdcSectionPage.NewLabel(const aCaption: string): TLabel;
begin
  Result := TLabel.Create(FSheet);
  Result.Parent := FSheet;
  Result.Left := Scale(cLeft);
  Result.Top := FTop + Scale(4);
  Result.Caption := aCaption;
end;

function TRdcSectionPage.AddField(aKind: TRdcFieldKind; const aElement, aCaption: string; aControl: TWinControl; aLabel: TLabel): TRdcFieldBinding;
begin
  Result := TRdcFieldBinding.Create;
  Result.Section := FCurrent;
  Result.Kind := aKind;
  Result.Element := aElement;
  Result.Caption := aCaption;
  Result.Control := aControl;
  Result.LabelControl := aLabel;
  FFields.Add(Result);
end;

function TRdcSectionPage.AddCheck(const aElement, aCaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(FSheet);
  Result.Parent := FSheet;
  Result.SetBounds(Scale(cLeft), FTop, Scale(cControlLeft + cControlWidth - cLeft), Scale(17));
  Result.Caption := aCaption;
  Result.OnClick := FieldChanged;
  AddField(fkBool, aElement, aCaption, Result, nil);
  Inc(FTop, Scale(cCheckHeight));
end;

function TRdcSectionPage.AddText(const aElement, aCaption: string; aWidth: Integer): TEdit;
var
  lLabel: TLabel;
begin
  lLabel := NewLabel(aCaption);
  Result := TEdit.Create(FSheet);
  Result.Parent := FSheet;
  Result.SetBounds(Scale(cControlLeft), FTop, Scale(aWidth), Result.Height);
  Result.OnChange := FieldChanged;
  AddField(fkText, aElement, aCaption, Result, lLabel);
  Inc(FTop, Scale(cRowHeight));
end;

function TRdcSectionPage.AddNumber(const aElement, aCaption: string; aMin, aMax: Integer): TEdit;
var
  lField: TRdcFieldBinding;
begin
  Result := AddText(aElement, aCaption, 80);
  Result.NumbersOnly := True;
  lField := FFields.Last;
  lField.Kind := fkInt;
  lField.MinValue := aMin;
  lField.MaxValue := aMax;
end;

function TRdcSectionPage.AddChoice(const aElement, aCaption: string; const aValues, aCaptions: array of string): TComboBox;
var
  lCaption: string;
  lField: TRdcFieldBinding;
  lLabel: TLabel;
  lValue: string;
begin
  lLabel := NewLabel(aCaption);
  Result := TComboBox.Create(FSheet);
  Result.Parent := FSheet;
  Result.Style := csDropDownList;
  Result.SetBounds(Scale(cControlLeft), FTop, Scale(cControlWidth), Result.Height);
  for lCaption in aCaptions do
    Result.Items.Add(lCaption);
  Result.OnChange := FieldChanged;
  lField := AddField(fkChoice, aElement, aCaption, Result, lLabel);
  for lValue in aValues do
    lField.Values := lField.Values + [lValue];
  Inc(FTop, Scale(cRowHeight));
end;

function TRdcSectionPage.AddSuggestions(const aElement, aCaption: string; const aItems: array of string): TComboBox;
var
  lItem: string;
  lLabel: TLabel;
begin
  lLabel := NewLabel(aCaption);
  Result := TComboBox.Create(FSheet);
  Result.Parent := FSheet;
  Result.Style := csDropDown;
  Result.SetBounds(Scale(cControlLeft), FTop, Scale(160), Result.Height);
  for lItem in aItems do
    Result.Items.Add(lItem);
  Result.OnChange := FieldChanged;
  AddField(fkText, aElement, aCaption, Result, lLabel);
  Inc(FTop, Scale(cRowHeight));
end;

procedure TRdcSectionPage.AddHint(const aText: string);
var
  lLabel: TLabel;
begin
  Inc(FTop, Scale(6));
  lLabel := TLabel.Create(FSheet);
  lLabel.Parent := FSheet;
  lLabel.AutoSize := False;
  lLabel.WordWrap := True;
  lLabel.SetBounds(Scale(cLeft), FTop, Scale(cControlLeft + cControlWidth - cLeft), Scale(48));
  lLabel.Font.Color := clGrayText;
  lLabel.Caption := aText;
  Inc(FTop, Scale(52));
end;

procedure TRdcSectionPage.SetHint(const aElement, aHint: string);
var
  lField: TRdcFieldBinding;
begin
  for lField in FFields do
    if lField.Element = aElement then
    begin
      lField.Control.Hint := aHint;
      lField.Control.ShowHint := True;
      if lField.LabelControl <> nil then
      begin
        lField.LabelControl.Hint := aHint;
        lField.LabelControl.ShowHint := True;
      end;
    end;
end;

function TRdcSectionPage.FindField(const aElement: string): TRdcFieldBinding;
var
  lField: TRdcFieldBinding;
begin
  for lField in FFields do
    if lField.Element = aElement then
      Exit(lField);
  raise EArgumentException.CreateFmt('Onbekend veld %s', [aElement]);
end;

function TRdcSectionPage.FieldOfControl(aControl: TObject): TRdcFieldBinding;
var
  lField: TRdcFieldBinding;
begin
  for lField in FFields do
    if lField.Control = aControl then
      Exit(lField);
  Result := nil;
end;

function TRdcSectionPage.ChoiceIndex(aField: TRdcFieldBinding; const aStored: string): Integer;
var
  lIndex: Integer;
begin
  for lIndex := 0 to High(aField.Values) do
    if SameText(aField.Values[lIndex], aStored) then
      Exit(lIndex);
  // Onbekende waarde: de default tonen (de waarde zelf blijft bewaard zolang het veld niet gewijzigd wordt).
  for lIndex := 0 to High(aField.Values) do
    if SameText(aField.Values[lIndex], aField.Section.Work.DefaultFor(aField.Element)) then
      Exit(lIndex);
  Result := 0;
end;

function TRdcSectionPage.ControlText(aField: TRdcFieldBinding): string;
begin
  case aField.Kind of
    fkBool:
      Result := RdcBoolText(TCheckBox(aField.Control).Checked);
    fkChoice:
      if TComboBox(aField.Control).ItemIndex >= 0 then
        Result := aField.Values[TComboBox(aField.Control).ItemIndex]
      else
        Result := '';
    fkInt:
      Result := IntToStr(StrToIntDef(Trim(TEdit(aField.Control).Text), StrToIntDef(aField.Section.Work.DefaultFor(aField.Element), 0)));
  else
    if aField.Control is TComboBox then
      Result := Trim(TComboBox(aField.Control).Text)
    else
      Result := Trim(TEdit(aField.Control).Text);
  end;
end;

function TRdcSectionPage.NormalizedText(aField: TRdcFieldBinding; const aStored: string): string;
begin
  case aField.Kind of
    fkBool:
      Result := RdcBoolText(RdcTextToBool(aStored, RdcTextToBool(aField.Section.Work.DefaultFor(aField.Element), False)));
    fkChoice:
      Result := aField.Values[ChoiceIndex(aField, aStored)];
    fkInt:
      Result := IntToStr(StrToIntDef(aStored, StrToIntDef(aField.Section.Work.DefaultFor(aField.Element), 0)));
  else
    Result := Trim(aStored);
  end;
end;

procedure TRdcSectionPage.ShowField(aField: TRdcFieldBinding; const aStored: string);
begin
  case aField.Kind of
    fkBool:
      TCheckBox(aField.Control).Checked := RdcTextToBool(NormalizedText(aField, aStored), False);
    fkChoice:
      TComboBox(aField.Control).ItemIndex := ChoiceIndex(aField, aStored);
    fkInt:
      TEdit(aField.Control).Text := NormalizedText(aField, aStored);
  else
    if aField.Control is TComboBox then
      TComboBox(aField.Control).Text := aStored
    else
      TEdit(aField.Control).Text := aStored;
  end;
end;

procedure TRdcSectionPage.ShowValues(aInherited: Boolean);
var
  lField: TRdcFieldBinding;
begin
  for lField in FFields do
    if aInherited then
      ShowField(lField, lField.Section.InheritedFrom.Values[lField.Element])
    else
      ShowField(lField, lField.Section.Work.Values[lField.Element]);
end;

procedure TRdcSectionPage.StoreInto(aSection: TRdcPageSection);
var
  lField: TRdcFieldBinding;
  lText: string;
begin
  for lField in FFields do
  begin
    if lField.Section <> aSection then
      Continue;
    lText := ControlText(lField);
    if NormalizedText(lField, aSection.Work.Values[lField.Element]) <> lText then
      aSection.Work.Values[lField.Element] := lText;
  end;
end;

procedure TRdcSectionPage.UseInheritedAsStart;
var
  lSection: TRdcPageSection;
begin
  // Lege secties: de geërfde waarden als startpunt, zodat het tabblad een consistent geheel toont.
  for lSection in FSections do
    if lSection.Work.Node.Children.Count = 0 then
      lSection.Work.ReplaceNode(lSection.InheritedFrom.Node.Clone);
end;

procedure TRdcSectionPage.PrepareOnce;
begin
  if FPrepared then
    Exit;
  FPrepared := True;
  if not FInheritBox.Checked then
    UseInheritedAsStart;
end;

procedure TRdcSectionPage.Refresh;
begin
  PrepareOnce;
  FLoading := True;
  try
    ShowValues(FInheritBox.Checked);
  finally
    FLoading := False;
  end;
  UpdateEnabled;
end;

procedure TRdcSectionPage.UpdateEnabled;
var
  lApplies: Boolean;
  lField: TRdcFieldBinding;
begin
  for lField in FFields do
  begin
    lApplies := not Assigned(FFieldApplies) or FFieldApplies(lField.Element);
    lField.Control.Enabled := not FInheritBox.Checked and lApplies;
    if lField.LabelControl <> nil then
      lField.LabelControl.Enabled := lApplies;
  end;
end;

procedure TRdcSectionPage.InheritClick(Sender: TObject);
begin
  InheritToggled;
end;

procedure TRdcSectionPage.FieldChanged(Sender: TObject);
begin
  FieldEdited(Sender);
end;

procedure TRdcSectionPage.FieldEdited(aSender: TObject);
var
  lField: TRdcFieldBinding;
begin
  if FLoading then
    Exit;
  lField := FieldOfControl(aSender);
  if lField <> nil then
    lField.Section.Touched := True;
  UpdateEnabled;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TRdcSectionPage.InheritToggled;
var
  lSection: TRdcPageSection;
begin
  if FLoading then
    Exit;
  if FInheritBox.Checked then
  begin
    // Eigen waarden bewaren voor als het vinkje weer uit gaat.
    for lSection in FSections do
      StoreInto(lSection);
  end
  else
  begin
    // Bewust uitgezet: alle secties van dit tabblad worden eigen.
    UseInheritedAsStart;
    for lSection in FSections do
      lSection.Touched := True;
  end;
  Refresh;
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TRdcSectionPage.ApplyToWork;
var
  lSection: TRdcPageSection;
begin
  for lSection in FSections do
  begin
    // Geërfd (vinkje aan), of bij openen geërfd en niet aangeraakt: blijft erven; RDCMan schrijft de sectie niet.
    if FInheritBox.Checked or (lSection.InitiallyInherited and not lSection.Touched) then
    begin
      lSection.Work.Inherit := True;
      lSection.Work.Clear;
      Continue;
    end;
    lSection.Work.Inherit := False;
    // Nieuwe eigen sectie: volledig (met defaults) wegschrijven, zoals RDCMan dat doet. Een bestaande sectie
    // niet aanvullen: ontbrekende elementen blijven ontbreken zolang het veld niet gewijzigd wordt.
    if lSection.Work.Node.Children.Count = 0 then
      lSection.Work.FillDefaults;
    StoreInto(lSection);
  end;
end;

function TRdcSectionPage.Validate(out aControl: TWinControl; out aMessage: string): Boolean;
var
  lField: TRdcFieldBinding;
  lValue: Integer;
begin
  aControl := nil;
  aMessage := '';
  if FInheritBox.Checked then
    Exit(True);
  for lField in FFields do
    if (lField.Kind = fkInt) and (not TryStrToInt(Trim(TEdit(lField.Control).Text), lValue) or (lValue < lField.MinValue) or (lValue > lField.MaxValue)) then
    begin
      aControl := lField.Control;
      aMessage := Format(_('"%s" moet een getal tussen %d en %d zijn.'), [lField.Caption, lField.MinValue, lField.MaxValue]);
      Exit(False);
    end;
  Result := True;
end;

function TRdcSectionPage.FieldValue(const aElement: string): string;
begin
  Result := ControlText(FindField(aElement));
end;

procedure TRdcSectionPage.SetFieldValue(const aElement, aText: string);
begin
  if FInheritBox.Checked then
    Exit;
  FLoading := True;
  try
    ShowField(FindField(aElement), aText);
  finally
    FLoading := False;
  end;
end;

function TRdcSectionPage.GetIsOwn: Boolean;
begin
  Result := not FInheritBox.Checked;
end;

end.
