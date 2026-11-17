function set_progress_stream(stream_mode)
%SET_PROGRESS_STREAM Choose where the runtime progress bar is written.
%   nlolib.set_progress_stream()               "stderr"
%   nlolib.set_progress_stream(stream_mode)    "stderr", "stdout" or "both"
%
%   MATLAB does not show the library's own stdout/stderr in the Command
%   Window; the live_progress option of nlolib.propagate does.
%
%   See also NLOLIB.SET_PROGRESS_OPTIONS.
arguments
    stream_mode = "stderr"
end
code = to_c_enum("progress_stream", stream_mode, 'stream_mode');
require_function('nlolib_set_progress_stream');
check_status(calllib('nlolib', 'nlolib_set_progress_stream', code), ...
             'nlolib_set_progress_stream');
end
