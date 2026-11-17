function tf = require_function(functionName, required)
%REQUIRE_FUNCTION Load the library if needed and check it exports a function.
%   require_function(functionName)        raises nlolib:unavailable if missing
%   tf = require_function(functionName, false)   returns false instead
%
%   Private.
if nargin < 2
    required = true;
end
if ~libisloaded('nlolib')
    nlolib.load();
end
try
    tf = any(strcmp(libfunctions('nlolib'), functionName));
catch
    tf = false;
end
if ~tf && required
    error('nlolib:unavailable', '%s is not available in this nlolib build.', functionName);
end
end
