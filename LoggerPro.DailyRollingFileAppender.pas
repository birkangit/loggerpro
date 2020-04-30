unit LoggerPro.DailyRollingFileAppender;
{ <@abstract(The unit to include if you want to use @link(TLoggerProDateFileAppender))
  @author(Daniele Teti) }

interface

uses
  LoggerPro,
  System.Classes,
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  {
    @abstract(Logs to file using one different file for each different TAG used.)
    @author(Daniele Teti - d.teti@bittime.it)
    Implements log rotations.
    This appender is the default appender when no configuration is done on the @link(TLogger) class.

    Without any configuration LoggerPro uses the @link(TLoggerProDateFileAppender) with the default configuration.

    So the following two blocks of code are equivalent:

    @longcode(#
    ...
    TLogger.Initialize; //=> uses the TLoggerProDateFileAppender because no other configuration is provided
    ...

    ...
    TLogger.AddAppender(TLoggerProDateFileAppender.Create);
    TLogger.Initialize //=> uses the TLoggerProDateFileAppender as configured
    ...
    #)

  }

  TFileAppenderOption = (IncludePID);
  TFileAppenderOptions = set of TFileAppenderOption;

  { @abstract(The default file appender)
    To learn how to use this appender, check the sample @code(file_appender.dproj)
  }
  TLogFile = record
    Path: string;
    Tag: string;
    DateModified: TDateTime;
  end;

  TDateWriter = class
  public

    StreamWriter: TStreamWriter;
    Tag: String;
    DateStr: String;
    constructor Create;
    destructor Destroy;override;
  end;

  TLoggerProDailyRollingFileAppender = class(TLoggerProAppenderBase)
  private

    FFormatSettings: TFormatSettings;
    FDateWriterList: TObjectList<TDateWriter>;
    FPreviousDateStrings: TDictionary<string,string>;
    FMaxBackupFileCount: Integer;

    FLogFormat: string;
    FLogFileNameFormat: string;
    FFileAppenderOptions: TFileAppenderOptions;
    FLogsFolder: string;
    FEncoding: TEncoding;
    FModuleName: String;


    function FindWriter(const aDateStr: string; const aTag: string; out aWriter: TDateWriter): boolean;
    procedure RemoveWriter(const aTag: string; const aDateStr: string);
    function CreateWriter(const aLogItem: TLogItem): TDateWriter;

    function GetDateStr(const dt: TDateTime): string;
    function GetLogFileName(const aLogItem: TLogItem; fileNo: integer = 0): string;
    procedure InternalWriteLog(const aStreamWriter: TStreamWriter; const aValue: string); inline;
    procedure ClearLogFiles(const aTag: string; const oldFilesCount: integer);
  public const
    { @abstract(Defines the default format string used by the @link(TLoggerProDateFileAppender).)
      The positional parameters are the followings:
      @orderedList(
      @itemSetNumber 0
      @item TimeStamp
      @item ThreadID
      @item LogType
      @item LogMessage
      @item LogTag
      )
    }
    DEFAULT_LOG_FORMAT = '%0:s [TID %1:-8d][%2:-8s] %3:s [%4:s]';
    { @abstract(Defines the default format string used by the @link(TLoggerProDateFileAppender).)
      The positional parameters are the followings:
      @orderedList(
      @item SetNumber 0
      @item ModuleName
      @item LogNum
      @item LogTag
      )
    }
    DEFAULT_FILENAME_FORMAT = '%s_%s.%s.log';
    //DEFAULT_FILENAME_FORMAT2 = '%s.%s.%s.%s.log';
    { @abstract(Defines number of log file set to mantain during logs rotation) }
    DEFAULT_MAX_BACKUP_FILE_COUNT = 5;

    constructor Create(aMaxBackupFileCount: Integer = DEFAULT_MAX_BACKUP_FILE_COUNT;
      aLogsFolder: string = '';
      aFileAppenderOptions: TFileAppenderOptions = [];
      aLogFormat: string = DEFAULT_LOG_FORMAT; aEncoding: TEncoding = nil); reintroduce;
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); overload; override;
  end;

implementation

uses
  System.IOUtils,
  idGlobal;

{ TLoggerProDateFileAppender }
function TLoggerProDailyRollingFileAppender.GetDateStr(const dt: TDateTime): string;
begin
  result := FormatDateTime('YYYY_MM_DD', dt);
end;

function TLoggerProDailyRollingFileAppender.GetLogFileName(const aLogItem: TLogItem; fileNo: integer = 0): string;
var
  lExt: string;
  lModuleName: string;
  lPath: string;
  lFormat: String;
  lDate: string;
begin
  lDate := GetDateStr(aLogItem.TimeStamp);
  lModuleName := FModuleName; //
  lFormat := FLogFileNameFormat;

  if TFileAppenderOption.IncludePID in FFileAppenderOptions then
    lModuleName := lModuleName + '_pid_' + IntToStr(CurrentProcessId).PadLeft(6, '0');
  if fileNo > 0 then
    lModuleName := lModuleName + '_' + IntToStr(fileNo).PadLeft(2, '0');


  lPath := FLogsFolder;
  lExt := Format(lFormat, [lModuleName, lDate, aLogItem.LogTag]);
  Result := TPath.Combine(lPath, lExt);
end;

procedure TLoggerProDailyRollingFileAppender.Setup;
begin
  if FLogsFolder = '' then
    FLogsFolder := TPath.GetDirectoryName(GetModuleName(HInstance));
  if not TDirectory.Exists(FLogsFolder) then
    TDirectory.CreateDirectory(FLogsFolder);
  FFormatSettings.DateSeparator := '-';
  FFormatSettings.TimeSeparator := ':';
  FFormatSettings.ShortDateFormat := 'YYY-MM-DD HH:NN:SS:ZZZ';
  FFormatSettings.ShortTimeFormat := 'HH:NN:SS';
  FDateWriterList := TObjectList<TDateWriter>.Create;
  FPreviousDateStrings := TDictionary<string,string>.Create;

end;

procedure TLoggerProDailyRollingFileAppender.TearDown;
begin
  FDateWriterList.Free;
  FPreviousDateStrings.Free;
end;

procedure TLoggerProDailyRollingFileAppender.InternalWriteLog(const aStreamWriter: TStreamWriter; const aValue: string);
begin
  aStreamWriter.WriteLine(aValue);
  aStreamWriter.Flush;
end;
procedure TLoggerProDailyRollingFileAppender.ClearLogFiles(const aTag: string; const oldFilesCount: integer);
var
  logFiles: TList<TLogFile>;
  files: TStringDynArray;
  i: Integer;
  fileName: string;
  logFile: TLogFile;
  fileNameSplitted: TArray<String>;
  tagPos: integer;

  Comparison: TComparison<TLogFile>;
  fileCount: integer;
begin
  Comparison :=
  function(const Left, Right: TLogFile): Integer
  begin
    Result := CompareDate(Left.DateModified,Right.DateModified);
  end;

  logFiles := TList<TLogFile>.Create(TComparer<TLogFile>.Construct(Comparison));
  files := TDirectory.GetFiles(FLogsFolder, '*.log');
  for fileName in files do
  begin
    logFile.Path := fileName;
    fileNameSplitted := fileName.Split(['.']);
    tagPos := High(fileNameSplitted) - 1;
    if (tagPos >= 0) then
      logFile.Tag := fileNameSplitted[tagPos];
    logFile.DateModified := TFile.GetLastWriteTime(fileName);
    if (logFile.Path.ToLower.StartsWith(FModuleName.ToLower)) and (logFile.Tag = aTag) then
      logFiles.Add(logFile);
  end;
  logFiles.Sort();
  fileCount := logFiles.Count;
  for i := 0 to fileCount - oldFilesCount do
  begin
    try
      DeleteFile(logFiles[i].Path);
    except

    end;
  end;

end;

procedure TLoggerProDailyRollingFileAppender.WriteLog(const aLogItem: TLogItem);
var
  lWriter: TDateWriter;
  previousDateStr: string;
begin
  if not FPreviousDateStrings.TryGetValue(aLogItem.LogTag, previousDateStr) then
    previousDateStr := '';

  if GetDateStr(aLogItem.TimeStamp) <> previousDateStr then
  begin
    //DateChanged
    ClearLogFiles(aLogItem.LogTag, FMaxBackupFileCount);
    if previousDateStr <> '' then
      RemoveWriter(aLogItem.LogTag, previousDateStr);
    previousDateStr := GetDateStr(aLogItem.TimeStamp);
    FPreviousDateStrings.AddOrSetValue(aLogItem.LogTag, GetDateStr(aLogItem.TimeStamp));
    lWriter := CreateWriter(aLogItem);
  end;
  if not FindWriter(GetDateStr(aLogItem.TimeStamp), aLogItem.LogTag, lWriter) then
  begin
    lWriter := CreateWriter(aLogItem);
  end;
  InternalWriteLog(lWriter.StreamWriter, Format(FLogFormat, [datetimetostr(aLogItem.TimeStamp, FFormatSettings), aLogItem.ThreadID,
      aLogItem.LogTypeAsString, aLogItem.LogMessage, aLogItem.LogTag]));

end;

procedure TLoggerProDailyRollingFileAppender.RemoveWriter(const aTag, aDateStr: string);
var
  aDateWriter: TDateWriter;
begin
  for aDateWriter in FDateWriterList do
    if (aDateWriter.Tag = aTag) and (aDateWriter.DateStr = aDateStr) then
      FDateWriterList.Remove(aDateWriter);
end;


constructor TLoggerProDailyRollingFileAppender.Create(aMaxBackupFileCount: Integer;
  aLogsFolder: string; aFileAppenderOptions: TFileAppenderOptions; aLogFormat: string;
  aEncoding: TEncoding);
begin
  inherited Create;
  FModuleName := TPath.GetFileNameWithoutExtension(GetModuleName(HInstance));
  FLogsFolder := aLogsFolder;
  FMaxBackupFileCount := aMaxBackupFileCount;
  FLogFormat := aLogFormat;
  FLogFileNameFormat := DEFAULT_FILENAME_FORMAT;
  FFileAppenderOptions := aFileAppenderOptions;
  if Assigned(aEncoding) then
    FEncoding := aEncoding
  else
    FEncoding := TEncoding.DEFAULT;
end;

function TLoggerProDailyRollingFileAppender.CreateWriter(const aLogItem: TLogItem): TDateWriter;
var
  lFileStream: TFileStream;
  lFileAccessMode: Word;
  fileName: string;
  i: Integer;
begin
  for i := 0 to 99 do
  begin

    fileName := GetLogFileName(aLogItem, i);
    lFileAccessMode := fmOpenWrite or fmShareDenyNone;
    if not TFile.Exists(fileName) then
      lFileAccessMode := lFileAccessMode or fmCreate;
    lFileStream := nil;
    try
      try
        lFileStream := TFileStream.Create(fileName, lFileAccessMode);
      except
        continue;
      end;
      lFileStream.Seek(0, TSeekOrigin.soEnd);

      Result := TDateWriter.Create;

      Result.StreamWriter := TStreamWriter.Create(lFileStream, FEncoding, 32);
      Result.StreamWriter.AutoFlush := true;
      Result.StreamWriter.OwnStream;

      Result.Tag := aLogItem.logTag;
      Result.DateStr := GetDateStr(aLogItem.TimeStamp);
      FDateWriterList.Add(Result);
      Exit;
    except
      lFileStream.Free;
    end;
  end;

  raise ELoggerPro.CreateFmt('Cannot create log file %s', [GetLogFileName(aLogItem, 0)]);

end;

function TLoggerProDailyRollingFileAppender.FindWriter(const aDateStr: string; const aTag: string; out aWriter: TDateWriter): boolean;
var
  i: Integer;
begin
  aWriter := nil;
  result := false;
  for i := 0 to FDateWriterList.Count - 1 do
  begin
    if (FDateWriterList[i].DateStr = aDateStr) and (FDateWriterList[i].Tag = aTag) then
    begin
      aWriter := FDateWriterList[i];
      Exit(True);
    end;
  end;

end;

{ TDateWriter }

constructor TDateWriter.Create;
begin
  inherited;
  StreamWriter := nil;
end;

destructor TDateWriter.Destroy;
begin
  if StreamWriter <> nil then
    StreamWriter.Free;
  inherited;
end;

end.

