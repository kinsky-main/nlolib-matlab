function limits = query_runtime_limits(options)
%QUERY_RUNTIME_LIMITS Solver memory and record limits, without running a simulation.
%   limits = nlolib.query_runtime_limits()
%   limits = nlolib.query_runtime_limits(pulse=pulse, exec_options=execOptions)
%
%   pulse is the pulse struct nlolib.propagate would get; the limits that
%   depend on the grid (max_num_recorded_samples_in_memory and
%   estimated_required_working_set_bytes) are 0 without it. exec_options is
%   the struct nlolib.propagate takes. Cheap enough to call before committing
%   to a large grid:
%
%     limits  = nlolib.query_runtime_limits(pulse=pulse);
%     records = min(wanted, limits.max_num_recorded_samples_in_memory);
%
%   Returns a struct with the fields of the C runtime_limits:
%     max_num_time_samples_runtime, max_num_recorded_samples_in_memory,
%     max_num_recorded_samples_with_storage,
%     estimated_required_working_set_bytes, estimated_device_budget_bytes,
%     storage_available
%
%   See also NLOLIB.PROPAGATE.
arguments
    options.pulse = []
    options.exec_options = []
end
require_function('nlolib_query_runtime_limits');

if isempty(options.pulse)
    cfg = struct('num_time_samples', 1, 'pulse_period', 1.0, 'delta_time', 1.0, ...
                 'frequency_grid', complex(0.0, 0.0));
else
    [cfg, ~, isTensor] = normalize_pulse(options.pulse);
    % A config prepared for propagation leaves time.nt at 0 so the solver
    % infers the layout from the samples it is given; a query has no samples,
    % so it states the count.
    if ~isTensor
        cfg.limits_query_nt = cfg.num_time_samples;
    end
end
cfg.propagation_distance = 0.0;
cfg.starting_step_size = 1e-3;
cfg.max_step_size = 1e-2;
cfg.min_step_size = 1e-5;
cfg.error_tolerance = 1e-6;

[simCfgPtr, physicsCfgPtr, keepalive] = prepare_sim_config(cfg); %#ok<ASGLU>
execOpts = make_exec_options(options.exec_options);
out = zeroed_libstruct('runtime_limits', ...
    {'max_num_time_samples_runtime', ...
     'max_num_recorded_samples_in_memory', ...
     'max_num_recorded_samples_with_storage', ...
     'estimated_required_working_set_bytes', ...
     'estimated_device_budget_bytes', ...
     'storage_available'});
check_status(calllib('nlolib', 'nlolib_query_runtime_limits', ...
                     simCfgPtr, physicsCfgPtr, execOpts, out), ...
             'nlolib_query_runtime_limits');
limits = struct(out);
end
