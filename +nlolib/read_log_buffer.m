function text = read_log_buffer(options)
%READ_LOG_BUFFER Read the in-memory runtime log buffer.
%   text = nlolib.read_log_buffer()
%   text = nlolib.read_log_buffer(consume=false, max_bytes=65536)
%
%   consume (default true) removes the returned text from the buffer;
%   max_bytes (default 262144, at least 2) bounds the read. Returns a string.
%
%   See also NLOLIB.SET_LOG_BUFFER.
arguments
    options.consume = true
    options.max_bytes = 262144
end
consume = logical_option(options.consume, 'consume');
maxBytes = count_option(options.max_bytes, 'max_bytes', 2);
require_function('nlolib_read_log_buffer');

% nlolib_read_log_buffer takes `char* dst`, which loadlibrary marshals as a
% cstring: pass a preallocated char buffer and take the modified text back as
% calllib's second output. The library always NUL-terminates.
buffer = blanks(maxBytes);
writtenPtr = libpointer('uint64Ptr', uint64(0));
[statusRaw, bufferOut] = calllib('nlolib', 'nlolib_read_log_buffer', ...
                                 buffer, uint64(maxBytes), writtenPtr, ...
                                 int32(consume));
check_status(statusRaw, 'nlolib_read_log_buffer');

byteCount = double(writtenPtr.Value);
if byteCount <= 0
    text = "";
    return;
end
% calllib already decoded the C string, so byteCount is an upper bound on the
% character count (exact for ASCII log output).
raw = char(bufferOut);
text = string(raw(1:min(byteCount, numel(raw))));
end
