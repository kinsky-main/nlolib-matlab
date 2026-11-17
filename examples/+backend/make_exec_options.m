function execOptions = make_exec_options(simOptions)
%MAKE_EXEC_OPTIONS Convert example simulation options to the exec_options struct.
%   execOptions = backend.make_exec_options(simOptions)
%
%   The result is passed as nlolib.propagate(..., exec_options=execOptions).

if nargin < 1 || isempty(simOptions)
    simOptions = backend.default_simulation_options();
end

execOptions = struct();
execOptions.backend_type = lower(string(simOptions.backend));
execOptions.fft_backend = lower(string(simOptions.fft_backend));
execOptions.device_heap_fraction = double(simOptions.device_heap_fraction);
execOptions.record_ring_target = uint64(simOptions.record_ring_target);
execOptions.forced_device_budget_bytes = uint64(simOptions.forced_device_budget_bytes);
end
