function [simCfgPtr, physicsCfgPtr, keepalive] = prepare_sim_config(cfg)
%PREPARE_SIM_CONFIG Build the simulation_config and runtime_operator_params libstructs.
%   [simCfgPtr, physicsCfgPtr, keepalive] = prepare_sim_config(cfg)
%
%   Private. cfg is a flat struct with the C API's field names, built by
%   nlolib.propagate and nlolib.query_runtime_limits:
%
%     num_time_samples, propagation_distance, starting_step_size,
%     max_step_size, min_step_size, error_tolerance, pulse_period,
%     delta_time, frequency_grid                              (required)
%     tensor_nt, tensor_nx, tensor_ny, delta_x, delta_y,
%     spatial_frequency_grid, kx_axis, ky_axis, potential_grid, wt_axis,
%     limits_query_nt, runtime                                (optional)
%
%   cfg.runtime holds the operators already lowered to C expression text
%   (linear_factor_expr, linear_expr, potential_expr, dispersion_factor_expr,
%   dispersion_expr, nonlinear_expr), their constants, and the C integer
%   nonlinear_model with the built-in model parameters.
%
%   wt_axis, kx_axis and ky_axis are left unset unless supplied, which tells
%   the library to generate those axes itself. keepalive must stay in scope
%   for as long as the returned pointers are used, or MATLAB frees the
%   buffers underneath the library.
required = { ...
    "num_time_samples", ...
    "propagation_distance", "starting_step_size", "max_step_size", ...
    "min_step_size", "error_tolerance", "pulse_period", "delta_time", ...
    "frequency_grid"};
for idx = 1:numel(required)
    if ~isfield(cfg, required{idx})
        error("prepare_sim_config: cfg.%s is required", required{idx});
    end
end

ensure_types_loaded();
keepalive = {};
maxConstants = 16;            % RUNTIME_OPERATOR_CONSTANTS_MAX from nlolib_matlab.h

numTs = double(cfg.num_time_samples);

runtimeCfg = struct();
if isfield(cfg, "runtime") && ~isempty(cfg.runtime)
    runtimeCfg = cfg.runtime;
end
constants = double(get_optional(runtimeCfg, "constants", []));
constants = constants(:).';
numConstants = numel(constants);
if numConstants > maxConstants
    error('nlolib:invalidOption', ...
          'the operators capture %d constants but at most %d are supported.', ...
          numConstants, maxConstants);
end
constantsFixed = zeros(1, maxConstants);
if numConstants > 0
    constantsFixed(1:numConstants) = constants;
end

freqPtr = pack_complex_array(cfg.frequency_grid);
keepalive{end + 1} = freqPtr;

spatialMl = struct();
tensorNt = double(get_optional(cfg, "tensor_nt", 0));
tensorNx = double(get_optional(cfg, "tensor_nx", 0));
tensorNy = double(get_optional(cfg, "tensor_ny", 0));
if tensorNt > 0
    spatialMl.nx = uint64(tensorNx);
    spatialMl.ny = uint64(tensorNy);
elseif isfield(cfg, "limits_query_nt") && ~isempty(cfg.limits_query_nt)
    % A limits query states its sample count in time.nt, and the core sizes
    % the grid as time.nt * spatial.nx * spatial.ny, so the transverse extent
    % must be 1 here or the query sizes an nt x nt grid.
    spatialMl.nx = uint64(1);
    spatialMl.ny = uint64(1);
else
    spatialMl.nx = uint64(numTs);
    spatialMl.ny = uint64(1);
end
spatialMl.delta_x = double(get_optional(cfg, "delta_x", 1.0));
spatialMl.delta_y = double(get_optional(cfg, "delta_y", 1.0));

pointerFields = {"spatial_frequency_grid", "kx_axis", "ky_axis"};
for idx = 1:numel(pointerFields)
    name = pointerFields{idx};
    if isfield(cfg, name) && ~isempty(cfg.(name))
        ptr = pack_complex_array(cfg.(name));
        spatialMl.(name) = ptr;
        keepalive{end + 1} = ptr; %#ok<AGROW>
    end
end

if isfield(cfg, "potential_grid") && ~isempty(cfg.potential_grid)
    potentialValues = cfg.potential_grid;
    if tensorNt > 0 && numel(potentialValues) == tensorNx * tensorNy
        potentialValues = kron(reshape(potentialValues, 1, []), ones(1, tensorNt));
    end
    potentialPtr = pack_complex_array(potentialValues);
    spatialMl.potential_grid = potentialPtr;
    keepalive{end + 1} = potentialPtr;
end

runtimeMl = struct();
exprFields = {"linear_factor_expr", "linear_expr", "potential_expr", ...
              "dispersion_factor_expr", "dispersion_expr", "nonlinear_expr"};
for idx = 1:numel(exprFields)
    name = exprFields{idx};
    text = string(get_optional(runtimeCfg, name, ""));
    if strlength(text) > 0
        ptr = libpointer('cstring', char(text));
        runtimeMl.(name) = ptr;
        keepalive{end + 1} = ptr; %#ok<AGROW>
    end
end
runtimeMl.nonlinear_model = int32(get_optional(runtimeCfg, "nonlinear_model", 0));
runtimeMl.nonlinear_gamma = double(get_optional(runtimeCfg, "nonlinear_gamma", 0.0));
runtimeMl.raman_fraction = double(get_optional(runtimeCfg, "raman_fraction", 0.0));
runtimeMl.raman_tau1 = double(get_optional(runtimeCfg, "raman_tau1", 0.0122));
runtimeMl.raman_tau2 = double(get_optional(runtimeCfg, "raman_tau2", 0.0320));
runtimeMl.shock_omega0 = double(get_optional(runtimeCfg, "shock_omega0", 0.0));
if isfield(runtimeCfg, "raman_response_time") && ~isempty(runtimeCfg.raman_response_time)
    ramanPtr = pack_complex_array(runtimeCfg.raman_response_time);
    runtimeMl.raman_response_time = ramanPtr;
    runtimeMl.raman_response_len = uint64(numel(runtimeCfg.raman_response_time));
    keepalive{end + 1} = ramanPtr;
else
    runtimeMl.raman_response_len = uint64(0);
end
runtimeMl.num_constants = uint64(numConstants);
runtimeMl.constants = constantsFixed;

simMl = struct();
simMl.propagation = struct( ...
    'starting_step_size', double(cfg.starting_step_size), ...
    'max_step_size', double(cfg.max_step_size), ...
    'min_step_size', double(cfg.min_step_size), ...
    'error_tolerance', double(cfg.error_tolerance), ...
    'propagation_distance', double(cfg.propagation_distance));
% The C API has one tensor layout (t fastest, then y, then x), value 0.
simMl.tensor = struct( ...
    'nt', uint64(tensorNt), ...
    'nx', uint64(tensorNx), ...
    'ny', uint64(tensorNy), ...
    'layout', int32(0));
% time.nt is normally left at 0, which the library reads as "infer the layout
% from the sample count passed to propagate". query_runtime_limits sets it,
% through limits_query_nt, because the limits that depend on the grid are
% computed only from a config that states its own sample count.
simMl.time = struct( ...
    'nt', uint64(get_optional(cfg, "limits_query_nt", 0)), ...
    'pulse_period', double(cfg.pulse_period), ...
    'delta_time', double(cfg.delta_time));
if isfield(cfg, "wt_axis") && ~isempty(cfg.wt_axis)
    wtAxisPtr = pack_complex_array(cfg.wt_axis);
    simMl.time.wt_axis = wtAxisPtr;
    keepalive{end + 1} = wtAxisPtr;
end
simMl.frequency = struct('frequency_grid', freqPtr);
simMl.spatial = spatialMl;

simCfgPtr = libstruct('simulation_config', simMl);
physicsCfgPtr = libstruct('runtime_operator_params', runtimeMl);
end

function val = get_optional(cfg, name, default)
if isfield(cfg, name) && ~isempty(cfg.(name))
    val = cfg.(name);
else
    val = default;
end
end
