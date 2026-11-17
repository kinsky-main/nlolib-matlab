function tf = perf_profile_is_enabled()
%PERF_PROFILE_IS_ENABLED True when the runtime performance counters are on.
%   tf = nlolib.perf_profile_is_enabled()
%
%   See also NLOLIB.PERF_PROFILE_SET_ENABLED.
require_function('nlolib_perf_profile_is_enabled');
tf = logical(calllib('nlolib', 'nlolib_perf_profile_is_enabled'));
end
