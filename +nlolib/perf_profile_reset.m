function perf_profile_reset()
%PERF_PROFILE_RESET Zero the runtime performance counters.
%   nlolib.perf_profile_reset()
%
%   See also NLOLIB.PERF_PROFILE_READ.
require_function('nlolib_perf_profile_reset');
check_status(calllib('nlolib', 'nlolib_perf_profile_reset'), 'nlolib_perf_profile_reset');
end
