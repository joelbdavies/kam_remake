unit KM_LCLControls;
{$I KaM_Remake.inc}
interface
uses
  Classes, Controls, StdCtrls;


type
  // LCL equivalents for the collapsible developer panels in the Delphi form.
  TKMCategoryPanel = class(TGroupBox)
  private
    fCollapsed: Boolean;
    fExpandedHeight: Integer;
    fOnCollapse, fOnExpand: TNotifyEvent;
    procedure SetCollapsed(aValue: Boolean);
  protected
    procedure Loaded; override;
    procedure DblClick; override;
  published
    property Collapsed: Boolean read fCollapsed write SetCollapsed;
    property ExpandedHeight: Integer read fExpandedHeight write fExpandedHeight;
    property OnCollapse: TNotifyEvent read fOnCollapse write fOnCollapse;
    property OnExpand: TNotifyEvent read fOnExpand write fOnExpand;
  end;

  TKMCategoryPanelGroup = class(TGroupBox)
  private
    fPanels: TList;
    function GetPanels: TList;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
    property Panels: TList read GetPanels;
  end;

  TCategoryPanel = TKMCategoryPanel;
  TCategoryPanelGroup = TKMCategoryPanelGroup;
  TCategoryPanelSurface = TGroupBox;


implementation


procedure TKMCategoryPanel.SetCollapsed(aValue: Boolean);
begin
  if fCollapsed = aValue then Exit;

  if aValue then fExpandedHeight := Height;
  fCollapsed := aValue;
  if csLoading in ComponentState then Exit;

  if aValue then
  begin
    Height := 24;
    if Assigned(fOnCollapse) then fOnCollapse(Self);
  end
  else
  begin
    Height := fExpandedHeight;
    if Assigned(fOnExpand) then fOnExpand(Self);
  end;
end;


procedure TKMCategoryPanel.Loaded;
begin
  inherited;
  Align := alTop;
  if fExpandedHeight = 0 then fExpandedHeight := Height;
  if fCollapsed then Height := 24;
end;


procedure TKMCategoryPanel.DblClick;
begin
  Collapsed := not Collapsed;
  inherited;
end;


constructor TKMCategoryPanelGroup.Create(aOwner: TComponent);
begin
  inherited;
  fPanels := TList.Create;
end;


destructor TKMCategoryPanelGroup.Destroy;
begin
  fPanels.Free;
  inherited;
end;


function TKMCategoryPanelGroup.GetPanels: TList;
var
  I: Integer;
begin
  fPanels.Clear;
  for I := 0 to ControlCount - 1 do
    if Controls[I] is TKMCategoryPanel then
      fPanels.Add(Controls[I]);
  Result := fPanels;
end;


initialization
  RegisterClasses([TKMCategoryPanel, TKMCategoryPanelGroup]);

end.
