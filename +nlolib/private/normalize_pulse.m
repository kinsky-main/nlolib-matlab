function [cfg, samples, isTensor] = normalize_pulse(pulse)
%NORMALIZE_PULSE Check a pulse struct and turn it into the grid part of a config.
%   [cfg, samples, isTensor] = normalize_pulse(pulse)
%
%   Private. pulse fields (any other field is nlolib:invalidPulse):
%     samples, delta_time                       required
%     pulse_period, frequency_grid              default nt*delta_time, FFT order
%     tensor_nt, tensor_nx, tensor_ny           all three for a tensor run
%     delta_x, delta_y                          default 1.0
%     spatial_frequency_grid, potential_grid    nx*ny or the full volume
%     wt_axis, kx_axis, ky_axis                 explicit axes; generated otherwise
%
%   cfg carries the C field names that prepare_sim_config reads.
known = {'samples', 'delta_time', 'pulse_period', 'frequency_grid', ...
         'tensor_nt', 'tensor_nx', 'tensor_ny', 'delta_x', 'delta_y', ...
         'spatial_frequency_grid', 'potential_grid', ...
         'wt_axis', 'kx_axis', 'ky_axis'};
if ~isstruct(pulse) || ~isscalar(pulse)
    error('nlolib:invalidPulse', 'pulse must be a struct with samples and delta_time.');
end
unknown = setdiff(fieldnames(pulse), known);
if ~isempty(unknown)
    error('nlolib:invalidPulse', 'pulse.%s is not a pulse field; expected one of %s.', ...
          unknown{1}, strjoin(known, ', '));
end
if ~isfield(pulse, 'samples') || ~isfield(pulse, 'delta_time')
    error('nlolib:invalidPulse', 'pulse must define samples and delta_time.');
end
samples = pulse.samples;
if isempty(samples) || ~isnumeric(samples) || any(~isfinite(samples(:)))
    error('nlolib:invalidPulse', 'pulse.samples must be a non-empty finite numeric array.');
end
n = numel(samples);
samples = complex(double(reshape(samples, 1, n)));

deltaTime = pulse.delta_time;
if ~(isnumeric(deltaTime) && isscalar(deltaTime) && isreal(deltaTime) && deltaTime > 0)
    error('nlolib:invalidPulse', 'pulse.delta_time must be a positive scalar.');
end
deltaTime = double(deltaTime);

dims = {'tensor_nt', 'tensor_nx', 'tensor_ny'};
given = cellfun(@(name) isfield(pulse, name) && ~isempty(pulse.(name)), dims);
if any(given) && ~all(given)
    error('nlolib:invalidPulse', 'pulse.tensor_nt, tensor_nx and tensor_ny go together.');
end
isTensor = all(given);
cfg = struct();
cfg.num_time_samples = n;
temporalSamples = n;
if isTensor
    shape = zeros(1, 3);
    for idx = 1:3
        value = pulse.(dims{idx});
        if ~(isnumeric(value) && isscalar(value) && value >= 1 && value == floor(value))
            error('nlolib:invalidPulse', 'pulse.%s must be a positive integer.', dims{idx});
        end
        shape(idx) = double(value);
    end
    if n ~= prod(shape)
        error('nlolib:invalidPulse', ...
              'numel(pulse.samples) is %d but tensor_nt*tensor_nx*tensor_ny is %d.', ...
              n, prod(shape));
    end
    cfg.tensor_nt = shape(1);
    cfg.tensor_nx = shape(2);
    cfg.tensor_ny = shape(3);
    temporalSamples = shape(1);
end
cfg.delta_time = deltaTime;

cfg.pulse_period = temporalSamples * deltaTime;
if isfield(pulse, 'pulse_period') && ~isempty(pulse.pulse_period)
    cfg.pulse_period = positive_scalar(pulse.pulse_period, 'pulse_period');
end
if isfield(pulse, 'frequency_grid') && ~isempty(pulse.frequency_grid)
    cfg.frequency_grid = pulse.frequency_grid;
else
    cfg.frequency_grid = default_frequency_grid(temporalSamples, deltaTime);
end
cfg.delta_x = 1.0;
cfg.delta_y = 1.0;
if isfield(pulse, 'delta_x') && ~isempty(pulse.delta_x)
    cfg.delta_x = positive_scalar(pulse.delta_x, 'delta_x');
end
if isfield(pulse, 'delta_y') && ~isempty(pulse.delta_y)
    cfg.delta_y = positive_scalar(pulse.delta_y, 'delta_y');
end

% Grids that cover the transverse plane or the full volume.
gridFields = {'spatial_frequency_grid', 'potential_grid'};
for idx = 1:numel(gridFields)
    name = gridFields{idx};
    if ~isfield(pulse, name) || isempty(pulse.(name))
        continue;
    end
    count = numel(pulse.(name));
    if isTensor
        ok = count == cfg.tensor_nx * cfg.tensor_ny || count == n;
        want = 'tensor_nx*tensor_ny or numel(samples)';
    else
        ok = count == n;
        want = 'numel(samples)';
    end
    if ~ok
        error('nlolib:invalidPulse', 'pulse.%s has %d values; expected %s.', name, count, want);
    end
    cfg.(name) = pulse.(name);
end

axisFields = {'wt_axis', 'kx_axis', 'ky_axis'};
axisLength = [temporalSamples, get_dim(cfg, 'tensor_nx'), get_dim(cfg, 'tensor_ny')];
for idx = 1:numel(axisFields)
    name = axisFields{idx};
    if ~isfield(pulse, name) || isempty(pulse.(name))
        continue;
    end
    if idx > 1 && ~isTensor
        error('nlolib:invalidPulse', 'pulse.%s needs a tensor run (tensor_nt/nx/ny).', name);
    end
    if numel(pulse.(name)) ~= axisLength(idx)
        error('nlolib:invalidPulse', 'pulse.%s has %d values; expected %d.', ...
              name, numel(pulse.(name)), axisLength(idx));
    end
    cfg.(name) = pulse.(name);
end
end

function value = positive_scalar(value, name)
if ~(isnumeric(value) && isscalar(value) && isreal(value) && value > 0)
    error('nlolib:invalidPulse', 'pulse.%s must be a positive scalar.', name);
end
value = double(value);
end

function value = get_dim(cfg, name)
value = 0;
if isfield(cfg, name)
    value = cfg.(name);
end
end

function omega = default_frequency_grid(numTimeSamples, deltaTime)
% Angular frequencies in FFT order.
k = 0:(numTimeSamples - 1);
positiveLimit = floor((numTimeSamples - 1) / 2);
k(k > positiveLimit) = k(k > positiveLimit) - numTimeSamples;
omega = complex(k * (2.0 * pi / (numTimeSamples * deltaTime)), 0.0);
end
