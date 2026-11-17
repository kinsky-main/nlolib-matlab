function perf_profile_set_enabled(enabled)
%PERF_PROFILE_SET_ENABLED Turn the runtime performance counters on or off.
%   nlolib.perf_profile_set_enabled()           on
%   nlolib.perf_profile_set_enabled(enabled)
%
%   See also NLOLIB.PERF_PROFILE_READ, NLOLIB.PERF_PROFILE_RESET.
arguments
    enabled = true
end
enabled = logical_option(enabled, 'enabled');
require_function('nlolib_perf_profile_set_enabled');
check_status(calllib('nlolib', 'nlolib_perf_profile_set_enabled', int32(enabled)), ...
             'nlolib_perf_profile_set_enabled');
end
