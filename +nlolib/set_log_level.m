function set_log_level(level)
%SET_LOG_LEVEL Set the runtime log level threshold.
%   nlolib.set_log_level()          "info"
%   nlolib.set_log_level(level)     "error", "warn", "info" or "debug"
%
%   See also NLOLIB.SET_LOG_BUFFER, NLOLIB.SET_LOG_FILE.
arguments
    level = "info"
end
code = to_c_enum("log_level", level, 'level');
require_function('nlolib_set_log_level');
check_status(calllib('nlolib', 'nlolib_set_log_level', code), 'nlolib_set_log_level');
end
