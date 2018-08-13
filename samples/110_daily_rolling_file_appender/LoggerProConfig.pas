unit LoggerProConfig;

interface

uses
  LoggerPro;

function Log: ILogWriter;

implementation

uses
  LoggerPro.DailyRollingFileAppender;

var
  _Log: ILogWriter;

function Log: ILogWriter;
begin
  Result := _Log;
end;

initialization

{ The TDailyRollingFileAppender has its defaults defined as follows:
  DEFAULT_LOG_FORMAT = '%0:s [TID %1:-8d][%2:-10s] %3:s [%4:s]';
  DEFAULT_MAX_BACKUP_FILE_COUNT = 5;
}

_Log := BuildLogWriter([TLoggerProDailyRollingFileAppender.Create(5, '..\..',[])]);

end.
