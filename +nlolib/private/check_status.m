function status = check_status(statusRaw, functionName, detail)
%CHECK_STATUS Turn an nlolib_status return into a status string, raising on failure.
%   status = check_status(statusRaw, functionName)
%   status = check_status(statusRaw, functionName, detail)
%
%   Private. Returns "ok"; any other status raises nlolib:statusFailed, or
%   nlolib:propagationAborted for "aborted". The message names the status
%   string, so callers can match on it.
if nargin < 3
    detail = "";
end
[code, rawDetail] = status_code(statusRaw);
status = from_c_enum("status", code);
if code == 0
    return;
end
detail = strjoin(cellstr([string(rawDetail), string(detail)]), newline);
detail = strtrim(string(detail));
identifier = 'nlolib:statusFailed';
if status == "aborted"
    identifier = 'nlolib:propagationAborted';
end
if strlength(detail) > 0
    error(identifier, '%s failed with status "%s". %s', functionName, status, detail);
end
error(identifier, '%s failed with status "%s".', functionName, status);
end

function [code, detail] = status_code(raw)
% calllib returns the enum either as a number or as its C name, depending on
% how the library was described to loadlibrary.
detail = "";
if isnumeric(raw) && isscalar(raw)
    code = double(raw);
    return;
end
token = '';
if isnumeric(raw)
    vals = double(raw(:).');
    vals = vals(vals ~= 0);
    if ~isempty(vals) && all(vals == floor(vals) & vals >= 32 & vals <= 126)
        token = strtrim(char(vals));
    end
end
if isempty(token)
    token = strtrim(char(string(raw)));
end
names = ["NLOLIB_STATUS_OK", "NLOLIB_STATUS_INVALID_ARGUMENT", ...
         "NLOLIB_STATUS_ALLOCATION_FAILED", "NLOLIB_STATUS_NOT_IMPLEMENTED", ...
         "NLOLIB_STATUS_ABORTED"];
code = find(names == string(token), 1) - 1;
if isempty(code)
    code = -1;
    detail = "unrecognised status return of class " + string(class(raw));
end
end
