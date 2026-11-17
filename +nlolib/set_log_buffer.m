function set_log_buffer(capacity_bytes)
%SET_LOG_BUFFER Keep runtime logs in an in-memory ring buffer.
%   nlolib.set_log_buffer()                 262144 bytes
%   nlolib.set_log_buffer(capacity_bytes)
%
%   See also NLOLIB.READ_LOG_BUFFER, NLOLIB.CLEAR_LOG_BUFFER.
arguments
    capacity_bytes = 262144
end
capacity_bytes = count_option(capacity_bytes, 'capacity_bytes', 1);
require_function('nlolib_set_log_buffer');
check_status(calllib('nlolib', 'nlolib_set_log_buffer', uint64(capacity_bytes)), ...
             'nlolib_set_log_buffer');
end
