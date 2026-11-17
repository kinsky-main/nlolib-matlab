function clear_log_buffer()
%CLEAR_LOG_BUFFER Empty the in-memory runtime log buffer.
%   nlolib.clear_log_buffer()
%
%   See also NLOLIB.SET_LOG_BUFFER, NLOLIB.READ_LOG_BUFFER.
require_function('nlolib_clear_log_buffer');
check_status(calllib('nlolib', 'nlolib_clear_log_buffer'), 'nlolib_clear_log_buffer');
end
