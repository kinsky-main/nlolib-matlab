function set_log_file(path, options)
%SET_LOG_FILE Write runtime logs to a file.
%   nlolib.set_log_file(path)
%   nlolib.set_log_file(path, append=true)
%
%   An empty path turns file logging off. append (default false) appends
%   instead of truncating.
%
%   See also NLOLIB.SET_LOG_LEVEL, NLOLIB.SET_LOG_BUFFER.
arguments
    path
    options.append = false
end
require_function('nlolib_set_log_file');
if strlength(string(path)) == 0
    pathPtr = libpointer();
else
    pathPtr = libpointer('cstring', char(string(path)));
end
check_status(calllib('nlolib', 'nlolib_set_log_file', pathPtr, ...
                     int32(logical_option(options.append, 'append'))), ...
             'nlolib_set_log_file');
end
