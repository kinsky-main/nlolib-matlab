function tf = storage_is_available()
%STORAGE_IS_AVAILABLE True when this nlolib build has SQLite storage.
%   tf = nlolib.storage_is_available()
%
%   See also NLOLIB.PROPAGATE.
tf = require_function('nlolib_storage_is_available', false) && ...
     logical(calllib('nlolib', 'nlolib_storage_is_available'));
end
