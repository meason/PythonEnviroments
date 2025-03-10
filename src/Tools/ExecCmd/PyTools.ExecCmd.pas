(**************************************************************************)
(*                                                                        *)
(* Module:  Unit 'PyTools.ExecCmd'                                        *)
(*                                                                        *)
(*                                  Copyright (c) 2021                    *)
(*                                  Lucas Moura Belo - lmbelo             *)
(*                                  lucas.belo@live.com                   *)
(*                                  Brazil                                *)
(*                                                                        *)
(* Project page:         https://github.com/Embarcadero/PythonEnviroments *)
(**************************************************************************)
(*  Functionality: Execute Shell Commands and/or Subprocess               *)
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
unit PyTools.ExecCmd;

interface

uses
  System.SysUtils;

type
  TRedirect = (stdin, stdout, stderr);
  TRedirections = set of TRedirect;

  IStdReader = interface
    ['{D199DC97-A11B-4284-8F66-2E3C5301C91A}']
    function ReadNext: string;
    function ReadAll(): string; overload;
    function ReadAll(out AValue: string; const ATimeout: cardinal): boolean; overload;
  end;

  IStdWriter = interface
    ['{47015ED5-97DF-4CD3-8251-FADA71DB4A4A}']
    procedure Write(const AValue: string);
  end;

  IExecCmd = interface
    ['{FDCA9BAA-D412-4B48-96C2-0F08057FD6ED}']
    function GetStdOut(): IStdReader;
    function GetStdIn(): IStdWriter;
    function GetStdErr(): IStdReader;
    function GetOutput(): string;

    function GetExitCode: Integer;
    function GetIsAlive: boolean;

    function Run(): IExecCmd; overload;
    function Run(out AOutput: string): IExecCmd; overload;
    function Run(const ARedirections: TRedirections): IExecCmd; overload;

    procedure Kill();
    function Wait(): Integer; overload;

    property StdOut: IStdReader read GetStdOut;
    property StdIn: IStdWriter read GetStdIn;
    property StdErr: IStdReader read GetStdErr;

    property Output: string read GetOutput;

    property IsAlive: boolean read GetIsAlive;
    property ExitCode: Integer read GetExitCode;
  end;

  TExecCmdService = class
  public
    class function Cmd(const ACmd: string; const AArg, AEnv: TArray<string>): IExecCmd; overload;
    class function Cmd(const ACmd: string; const AArg: TArray<string>): IExecCmd; overload;
  end;

const
  EXIT_SUCCESS  = 0;
  EXIT_FAILURE = 1;

implementation

uses
  PyTools.Exception,
  PyTools.ExecCmd.Platform;

{ TExecCmdService }

class function TExecCmdService.Cmd(const ACmd: string; const AArg, AEnv: TArray<string>): IExecCmd;
begin
  Result := TExecCmd.Create(ACmd, AArg, AEnv);
end;

class function TExecCmdService.Cmd(const ACmd: string;
  const AArg: TArray<string>): IExecCmd;
begin
  Result := Cmd(ACmd, AArg, []);
end;

end.
