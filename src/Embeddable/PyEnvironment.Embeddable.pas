(**************************************************************************)
(*                                                                        *)
(* Module:  Unit 'PyEnvironment.Embeddable'                               *)
(*                                                                        *)
(*                                  Copyright (c) 2021                    *)
(*                                  Lucas Moura Belo - lmbelo             *)
(*                                  lucas.belo@live.com                   *)
(*                                  Brazil                                *)
(*                                                                        *)
(* Project page:         https://github.com/Embarcadero/PythonEnviroments *)
(**************************************************************************)
(*  Functionality:  PyEnvironment embeddable                              *)
(*                                                                        *)
(*                                                                        *)
(**************************************************************************)
(* This source code is distributed with no WARRANTY, for no reason or use.*)
(* Everyone is allowed to use and change this code free for his own tasks *)
(* and projects, as long as this header and its copyright text is intact. *)
(* For changed versions of this code, which are public distributed the    *)
(* following additional conditions have to be fullfilled:                 *)
(* 1) The header has to contain a comment on the change and the author of *)
(*    it.                                                                 *)
(* 2) A copy of the changed source has to be sent to the above E-Mail     *)
(*    address or my then valid address, if this is possible to the        *)
(*    author.                                                             *)
(* The second condition has the target to maintain an up to date central  *)
(* version of the component. If this condition is not acceptable for      *)
(* confidential or legal reasons, everyone is free to derive a component  *)
(* or to generate a diff file to my or other original sources.            *)
(**************************************************************************)
unit PyEnvironment.Embeddable;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Zip,
  PythonEngine,
  PyTools.Cancelation,
  PyEnvironment,
  PyEnvironment.Distribution;

type
  (*-----------------------------------------------------------------------*)
  (*                                                                       *)
  (*                      Embeddables structure example                    *)
  (*                                                                       *)
  (* [Root] Directory                                                      *)
  (*  +-- python version/                                                  *)
  (*       +-- python zip                                                  *)
  (*-----------------------------------------------------------------------*)

  TPyCustomEmbeddableDistribution = class;
  TZipProgress = procedure(Sender: TObject;
    ADistribution: TPyCustomEmbeddableDistribution; FileName: string;
    Header: TZipHeader; Position: Int64) of object;

  TPyCustomEmbeddableDistribution = class(TPyDistribution)
  private
    FEmbeddablePackage: string;
    FEnvironmentPath: string;
    FOnZipProgress: TZipProgress;
    function FindSharedLibrary(): string;
    function FindExecutable(): string;
  private
    procedure DoZipProgressEvt(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64);
    {$IFDEF POSIX}
    function FileIsExecutable(const AFilePath: string): boolean;
    {$ENDIF POSIX}
    procedure CreateSymlink(const ASymlink, ATarget: string);
  protected
    function EnvironmentExists(): boolean;
    /// <summary>
    ///   Navigates through the embeddables searching for a compatible distribution.
    /// </summary>
    function EmbeddableExists(): boolean;
    /// <summary>
    ///   Creates a new environment based on the current settings.
    ///   An embeddable distribution will be used as an "image".
    /// </summary>
    procedure CreateEnvironment(const ACancelation: ICancelation); virtual;
    procedure CreateSymLinks(); virtual;
    procedure LoadSettings(const ACancelation: ICancelation); virtual;
  protected
    function GetEnvironmentPath(): string;
  public
    function Setup(const ACancelation: ICancelation): boolean; override;
  public
    property EmbeddablePackage: string read FEmbeddablePackage write FEmbeddablePackage;
  published
    property EnvironmentPath: string read FEnvironmentPath write FEnvironmentPath;
    property OnZipProgress: TZipProgress read FOnZipProgress write FOnZipProgress;
  end;

  TPyEmbeddableDistribution = class(TPyCustomEmbeddableDistribution)
  private
    FScanned: boolean;
    FDeleteEmbeddable: boolean;
    procedure DoDeleteEmbeddable();
  protected
    procedure LoadSettings(const ACancelation: ICancelation); override;
  public
    function Setup(const ACancelation: ICancelation): boolean; override;
    property Scanned: boolean read FScanned write FScanned;
  published
    property EmbeddablePackage;
    /// <summary>
    ///   Delete the embeddable zip file after install.
    /// </summary>
    property DeleteEmbeddable: boolean read FDeleteEmbeddable write FDeleteEmbeddable;
  end;

  TPyEmbeddableCustomCollection = class(TPyDistributionCollection);

  TPyEmbeddableCollection = class(TPyEmbeddableCustomCollection);

  TPyCustomEmbeddedEnvironment = class(TPyEnvironment)
  private
    FOnZipProgress: TZipProgress;
  published
    property OnZipProgress: TZipProgress read FOnZipProgress write FOnZipProgress;
  end;

  [ComponentPlatforms(pidAllPlatforms)]
  TPyEmbeddedEnvironment = class(TPyCustomEmbeddedEnvironment)
  public type
    TScanRule = (srFolder, srFileName);
  private type
    TScanner = class(TPersistent)
    private
      FAutoScan: boolean;
      FScanRule: TScanRule;
      FEmbeddablesPath: string;
      FEnvironmentPath: string;
      FDeleteEmbeddable: boolean;
    public
      procedure Scan(const AEmbedabblesPath: string; ACallback: TProc<TPythonVersionProp, string>);
    published
      property AutoScan: boolean read FAutoScan write FAutoScan default false;
      property ScanRule: TScanRule read FScanRule write FScanRule;
      property EmbeddablesPath: string read FEmbeddablesPath write FEmbeddablesPath;
      /// <summary>
      ///   Default environment path.
      /// </summary>
      property EnvironmentPath: string read FEnvironmentPath write FEnvironmentPath;
      /// <summary>
      ///   Delete the embeddable zip file after install.
      /// </summary>
      property DeleteEmbeddable: boolean read FDeleteEmbeddable write FDeleteEmbeddable;
    end;
  private
    FScanner: TScanner;
    procedure SetScanner(const Value: TScanner);
  protected
    function CreateCollection(): TPyDistributionCollection; override;
    procedure Prepare(const ACancelation: ICancelation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy(); override;
  published
    property Distributions;
    property Scanner: TScanner read FScanner write SetScanner;
  end;

implementation

uses
  System.IOUtils,
  System.Character,
  System.StrUtils,
  System.RegularExpressions,
  PyTools.ExecCmd,
  PyEnvironment.Exception,
  PyEnvironment.Path
  {$IFDEF POSIX}
  , Posix.SysStat, Posix.Stdlib, Posix.String_, Posix.Errno, Posix.Unistd
  {$ENDIF}
  ;

type
  TZipEventToAnonMethodAdapter = class
  public type
    TAdapterProc = TProc<TObject, string, TZipHeader, Int64>;
  private
    FAdapterProc: TAdapterProc;
  public
    constructor Create(const AAdapterProc: TAdapterProc);
    procedure Evt(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64);
  end;

{ TPyCustomEmbeddableDistribution }

procedure TPyCustomEmbeddableDistribution.CreateEnvironment(const ACancelation: ICancelation);
var
  LAdapter: TZipEventToAnonMethodAdapter;
  LProgress: TZipEventToAnonMethodAdapter.TAdapterProc;
begin
  LProgress := procedure(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64)
    begin
      ACancelation.CheckCancelled();
      DoZipProgressEvt(Sender, FileName, Header, Position);
    end;

  LAdapter := TZipEventToAnonMethodAdapter.Create(LProgress);
  try
    TZipFile.ExtractZipFile(FEmbeddablePackage, GetEnvironmentPath(), LAdapter.Evt);
  finally
    LAdapter.Free();
  end;
end;

procedure TPyCustomEmbeddableDistribution.CreateSymlink(const ASymlink,
  ATarget: string);
var
  LExistingTarget: string;
begin
  LExistingTarget := String.Empty;
  if TFile.Exists(ATarget) then begin
    //There is a bug with TFile.Exists and TFile.GetSymLinkTarget for Android
    //So we recreate it every time
    DeleteFile(ASymlink);

    if not TFile.CreateSymLink(ASymlink, ATarget) then
      raise ESymlinkFailed.CreateFmt('Failed to create the symlink: %s -> %s', [ASymlink, ATarget]);
  end;
end;

procedure TPyCustomEmbeddableDistribution.CreateSymLinks;
var
  LTargetInterpreter: string;
  LTargetLauncher: string;
  LSymlinkInterpreter: string;
  LSynlinkLauncher: string;
begin
  {$IFNDEF ANDROID}
  Exit;
  {$ENDIF ANDROID}
  //Real file names
  LTargetInterpreter := TPath.Combine(
    TPath.GetLibraryPath(),
    String.Format('libpython%s.so', [PythonVersion]));
  LTargetLauncher := TPath.Combine(
    TPath.GetLibraryPath(),
    String.Format('libpythonlauncher%s.so', [PythonVersion]));
  //Symlink names
  LSymlinkInterpreter := TPath.Combine(
    TPath.Combine(GetEnvironmentPath(), 'lib'),
    String.Format('libpython%s.so', [PythonVersion]));
  LSynlinkLauncher := TPath.Combine(
    TPath.Combine(GetEnvironmentPath(), 'bin'),
    String.Format('python%s', [PythonVersion]));
  //Creates the interpreter symlink
  CreateSymlink(LSymlinkInterpreter, LTargetInterpreter);
  //Creates the launcher symlink
  CreateSymlink(LSynlinkLauncher, LTargetLauncher);
end;

procedure TPyCustomEmbeddableDistribution.DoZipProgressEvt(Sender: TObject; FileName: string;
  Header: TZipHeader; Position: Int64);
begin
  if Assigned(FOnZipProgress) then
    FOnZipProgress(Sender, Self, FileName, Header, Position);
end;

function TPyCustomEmbeddableDistribution.EmbeddableExists: boolean;
begin
  Result := TFile.Exists(FEmbeddablePackage);
end;

function TPyCustomEmbeddableDistribution.EnvironmentExists: boolean;
begin
  Result := TDirectory.Exists(GetEnvironmentPath());
end;

{$IFDEF POSIX}
function TPyCustomEmbeddableDistribution.FileIsExecutable(
  const AFilePath: string): boolean;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  //Avoiding symlinks
  Result := (TFileAttribute.faOwnerExecute in TFile.GetAttributes(AFilePath))
    or (TFileAttribute.faGroupExecute in TFile.GetAttributes(AFilePath))
    or (TFileAttribute.faOthersExecute in TFile.GetAttributes(AFilePath));
  {$WARN SYMBOL_PLATFORM ON}
end;
{$ENDIF POSIX}

function TPyCustomEmbeddableDistribution.FindExecutable: string;

  function DoSearch(const APath: string): TArray<string>;
  {$IFDEF POSIX}
  var
    LFile: string;
  {$ENDIF POSIX}
  begin
    Result := TDirectory.GetFiles(APath, 'python*', TSearchOption.soTopDirectoryOnly,
      function(const Path: string; const SearchRec: TSearchRec): boolean
      var
        LFileName: string;
      begin
        LFileName := SearchRec.Name;
        if LFileName.EndsWith('m') then //3.7 and lower contain a "m" as sufix.
          LFileName := LFileName.Remove(Length(LFileName) - 1);

        Result := Char.IsDigit(LFileName, Length(LFileName) - 1);
      end);

    {$IFDEF POSIX}
    for LFile in Result do begin
      if (TPath.GetFileName(LFile).StartsWith('python' + PythonVersion)) and (FileIsExecutable(LFile)) then
        Exit(TArray<string>.Create(LFile));
    end;
    {$ENDIF POSIX}
  end;

var
  LFiles: TArray<string>;
begin
  {$IFDEF MSWINDOWS}
  //If we get this far and we're in a Windows only section
  //then we're done so just exit with the Result intact
  Result := TPath.Combine(GetEnvironmentPath(), 'python.exe');
  if TFile.Exists(Result) then
    Exit(Result)
  else
    Exit(String.Empty);
  {$ELSE}
  Result := TPath.Combine(GetEnvironmentPath(), 'bin');
  {$ENDIF}

  LFiles := DoSearch(Result);
  if Length(LFiles) > 0 then begin
    Result := LFiles[Low(LFiles)];
    if not TFile.Exists(Result) then
      Result := String.Empty;
  end else
    Result := String.Empty;
end;

function TPyCustomEmbeddableDistribution.FindSharedLibrary: string;

  function DoSearch(const ALibName: string; const APath: string): TArray<string>;
  var
    LFile: string;
    LSearch: string;
  begin
    LFile := TPath.Combine(APath, ALibName);
    if TFile.Exists(LFile) then
      Exit(TArray<string>.Create(LFile));

    LSearch := ALibName.Replace(TPath.GetExtension(ALibName), '') + '*' + TPath.GetExtension(ALibName);
    Result := TDirectory.GetFiles(
      APath,
      LSearch, //Python <= 3.7 might contain a "m" as sufix.
      TSearchOption.soTopDirectoryOnly);
  end;

var
  I: integer;
  LLibName: string;
  LPath: string;
  LFiles: TArray<string>;
begin
  for I := Low(PYTHON_KNOWN_VERSIONS) to High(PYTHON_KNOWN_VERSIONS) do
    if PythonVersion.StartsWith(PYTHON_KNOWN_VERSIONS[I].RegVersion) then begin
      LLibName := PYTHON_KNOWN_VERSIONS[I].DllName;
      Break;
    end;

  {$IFDEF MSWINDOWS}
  LPath := GetEnvironmentPath();
  {$ELSEIF DEFINED(MACOS)}
  //Let's try it in the library path first
  LPath := TPyEnvironmentPath.ResolvePath(TPyEnvironmentPath.ENVIRONMENT_PATH);
  LFiles := DoSearch(LLibName, LPath);
  if LFiles <> nil then
    Exit(LFiles[Low(LFiles)]);
  //Try to find it in the environment folder
  LPath := TPath.Combine(GetEnvironmentPath(), 'lib');
  {$ELSE}
  LPath := TPath.Combine(GetEnvironmentPath(), 'lib');
  {$ENDIF}

  LFiles := DoSearch(LLibName, LPath);
  if LFiles <> nil then
    Result := LFiles[Low(LFiles)]
  else
    Result := String.Empty;

  {$IFDEF LINUX}
  //Targets directly to the so file instead of a symlink.
  if TFile.Exists(Result + '.1.0') then
    Result := Result + '.1.0';
  {$ENDIF}
end;

procedure TPyCustomEmbeddableDistribution.LoadSettings(const ACancelation: ICancelation);
begin
  ACancelation.CheckCancelled();

  Home := GetEnvironmentPath();
  SharedLibrary := FindSharedLibrary();
  Executable := FindExecutable();
end;

function TPyCustomEmbeddableDistribution.GetEnvironmentPath: string;
begin
  Result := TPyEnvironmentPath.ResolvePath(EnvironmentPath, PythonVersion);
end;

function TPyCustomEmbeddableDistribution.Setup(const ACancelation: ICancelation): boolean;
begin
  inherited;
  if not EnvironmentExists() then begin
    if not EmbeddableExists() then
      raise EEmbeddableNotFound.CreateFmt(
        'Embeddable package not found.' + #13#10 + '%s', [FEmbeddablePackage]);

    CreateEnvironment(ACancelation);
  end;

  CreateSymLinks();

  LoadSettings(ACancelation);

  Result := true;
end;

{ TPyEmbeddableDistribution }

procedure TPyEmbeddableDistribution.DoDeleteEmbeddable;
begin
  TFile.Delete(EmbeddablePackage);
end;

procedure TPyEmbeddableDistribution.LoadSettings(const ACancelation: ICancelation);
begin
  if FScanned then
    inherited;
end;

function TPyEmbeddableDistribution.Setup(const ACancelation: ICancelation): boolean;
begin
  Result := inherited;
  if FDeleteEmbeddable and EmbeddableExists() then
    DoDeleteEmbeddable();
end;

{ TPyEmbeddedEnvironment }

constructor TPyEmbeddedEnvironment.Create(AOwner: TComponent);
begin
  inherited;
  FScanner := TScanner.Create();
  FScanner.ScanRule := TScanRule.srFolder;
  if not (csDesigning in ComponentState) then begin
    FScanner.EnvironmentPath := TPyEnvironmentPath.CreateEnvironmentPath();
    FScanner.EmbeddablesPath := TPyEnvironmentPath.CreateEmbeddablesPath();
  end;
end;

destructor TPyEmbeddedEnvironment.Destroy;
begin
  FScanner.Free();
  inherited;
end;

function TPyEmbeddedEnvironment.CreateCollection: TPyDistributionCollection;
begin
  Result := TPyEmbeddableCollection.Create(Self, TPyEmbeddableDistribution);
end;

procedure TPyEmbeddedEnvironment.Prepare(const ACancelation: ICancelation);
var
  I: integer;
  LExistingEnvironment: string;
  LDistribution: TPyEmbeddableDistribution;
begin
  if FScanner.AutoScan then begin
    //Let's first look for existing environments
    for I := Low(PYTHON_KNOWN_VERSIONS) to High(PYTHON_KNOWN_VERSIONS) do begin
      LExistingEnvironment := TPyEnvironmentPath.ResolvePath(
        FScanner.EnvironmentPath,
        PYTHON_KNOWN_VERSIONS[I].RegVersion);

      if TDirectory.Exists(LExistingEnvironment) then begin
        LDistribution := TPyEmbeddableDistribution(Distributions.Add());
        LDistribution.Scanned := true;
        LDistribution.PythonVersion := PYTHON_KNOWN_VERSIONS[I].RegVersion;
        LDistribution.EnvironmentPath := LExistingEnvironment;
      end;
    end;

    FScanner.Scan(
      TPyEnvironmentPath.ResolvePath(FScanner.EmbeddablesPath),
      procedure(APyVersionInfo: TPythonVersionProp; AEmbeddablePackage: string) begin
        if Assigned(Distributions.LocateEnvironment(APyVersionInfo.RegVersion)) then
          Exit;

        LDistribution := TPyEmbeddableDistribution(Distributions.Add());
        LDistribution.Scanned := true;
        LDistribution.PythonVersion := APyVersionInfo.RegVersion;
        LDistribution.EnvironmentPath := TPyEnvironmentPath.ResolvePath(
          FScanner.EnvironmentPath,
          APyVersionInfo.RegVersion);
        LDistribution.EmbeddablePackage := AEmbeddablePackage;
        LDistribution.OnZipProgress := FOnZipProgress;
        LDistribution.DeleteEmbeddable := FScanner.DeleteEmbeddable;
      end);
  end;
  inherited;
end;

procedure TPyEmbeddedEnvironment.SetScanner(const Value: TScanner);
begin
  FScanner.Assign(Value);
end;

{ TPyEmbeddedEnvironment.TScanner }

procedure TPyEmbeddedEnvironment.TScanner.Scan(const AEmbedabblesPath: string;
  ACallback: TProc<TPythonVersionProp, string>);
var
  I: Integer;
  LPath: string;
  LFiles: TArray<string>;
  LPythonVersion: string;
  LSearchPatter: string;
begin
  if not Assigned(ACallback) then
    Exit;

  if not TDirectory.Exists(AEmbedabblesPath) then
    raise EDirectoryNotFoundException.CreateFmt('Directory "%s" not found.', [
      AEmbedabblesPath]);

  //Look for version named subfolders
  if (FScanRule = TScanRule.srFolder) then begin
    LSearchPatter := '*.zip';
    for I := Low(PYTHON_KNOWN_VERSIONS) to High(PYTHON_KNOWN_VERSIONS) do begin
      LPath := TPath.Combine(AEmbedabblesPath, PYTHON_KNOWN_VERSIONS[I].RegVersion);
      if not TDirectory.Exists(LPath) then
        Continue;

      LFiles := TDirectory.GetFiles(LPath, LSearchPatter, TSearchOption.soTopDirectoryOnly);
      if (Length(LFiles) = 0) then
        Continue;

      ACallback(PYTHON_KNOWN_VERSIONS[I], LFiles[0]);
    end;
  end else if (FScanRule = TScanRule.srFileName) then begin
    //Look for pattern named files
    for I := Low(PYTHON_KNOWN_VERSIONS) to High(PYTHON_KNOWN_VERSIONS) do begin
      LPythonVersion := PYTHON_KNOWN_VERSIONS[I].RegVersion;
      LSearchPatter := Format('python3-*-%s*.zip', [LPythonVersion]);
      LFiles := TDirectory.GetFiles(AEmbedabblesPath, LSearchPatter, TSearchOption.soTopDirectoryOnly);
      if (Length(LFiles) = 0) then
        Continue;

      ACallback(PYTHON_KNOWN_VERSIONS[I], LFiles[0]);
    end
  end;
end;

{ TZipEventToAnonMethodAdapter }

constructor TZipEventToAnonMethodAdapter.Create(const AAdapterProc: TAdapterProc);
begin
  FAdapterProc := AAdapterProc;
end;

procedure TZipEventToAnonMethodAdapter.Evt(Sender: TObject; FileName: string;
  Header: TZipHeader; Position: Int64);
begin
  FAdapterProc(Sender, FileName, Header, Position);
end;

end.
