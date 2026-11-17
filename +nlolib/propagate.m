function result = propagate(pulse, linear_operator, nonlinear_operator, options)
%PROPAGATE Propagate a pulse, or a tensor (t, x, y) field, with the RK4IP solver.
%   result = nlolib.propagate(pulse, linear_operator, nonlinear_operator, ...
%                             propagation_distance=z, name=value...)
%
%   Example:
%     n = 1024; dt = 0.01; t = ((0:(n - 1)) - n / 2) * dt;
%     beta2 = -0.01; gamma = 0.04;
%     result = nlolib.propagate( ...
%         struct('samples', sqrt(25) * sech(t / 0.1), 'delta_time', dt), ...
%         @(A, w) 1i * (beta2 / 2) * w.^2, ...
%         @(A, I) 1i * gamma * A .* I, ...
%         propagation_distance=1.0, num_records=64);
%     imagesc(t, result.z_axis, abs(result.records).^2);
%
%   PULSE (struct)
%     samples, delta_time       complex launch field (flattened), sample spacing
%     pulse_period              default numel(samples) * delta_time (nt * delta_time)
%     frequency_grid            default FFT-order angular frequencies
%     tensor_nt, tensor_nx, tensor_ny
%                               all three for a tensor run; samples is then
%                               nt*nx*ny values, t fastest, then y, then x
%     delta_x, delta_y          transverse spacing, default 1.0
%     spatial_frequency_grid, potential_grid
%                               nx*ny values or the full volume
%     wt_axis, kx_axis, ky_axis explicit axes; generated otherwise
%
%   OPERATORS are function handles whose body is one expression; scalars the
%   body uses from the workspace become runtime constants, and a name in
%   constant_bindings takes that value instead. An argument named after a
%   symbol binds to it; other names take the symbols in the order shown.
%     linear_operator      D, applied as exp(h*D):
%                            temporal run @(A, w)            (wt is an alias of w)
%                            tensor run   @(A, wt, kx, ky, x, y, t)  (w is an alias of wt)
%     nonlinear_operator   N(A): @(A, I, V), I = |A|^2, V = potential_grid
%     linear_step_operator the per-step linear operator:
%                            temporal run @(A, D, h, w, V)
%                            tensor run   @(A, D, h, wt, kx, ky, x, y, t, V)
%     potential_operator   tensor runs only, without potential_grid: @(x, y, t)
%   Functions: exp, log, sqrt, sin, cos; imaginary unit 1i.
%
%   OPTIONS (name=value)
%     propagation_distance  required, > 0
%     preset                "fast", "balanced" (default) or "accuracy"
%     starting_step_size, max_step_size, min_step_size, error_tolerance
%                           override the preset
%     num_records           records to return; preset default
%     record_z              explicit record positions in [0, propagation_distance],
%                           nondecreasing; num_records must be unset or match
%     return_records        default true; false needs storage
%     potential_operator, linear_step_operator   see OPERATORS
%     constant_bindings     struct or containers.Map of name -> real scalar
%     nonlinear_model       "expr" (default, uses nonlinear_operator) or
%                           "kerr_raman" (built in; nonlinear_operator ignored)
%     nonlinear_gamma, raman_fraction, shock_omega0     default 0
%     raman_tau1, raman_tau2                            default 0.0122, 0.0320
%     raman_response_time   explicit complex response, replaces tau1/tau2
%     exec_options          struct: backend_type ("cpu", "vulkan", "auto"),
%                           fft_backend ("auto", "fftw", "vkfft"),
%                           device_heap_fraction, record_ring_target,
%                           forced_device_budget_bytes
%     storage               struct: sqlite_path (required), run_id,
%                           sqlite_max_bytes, chunk_records,
%                           cap_policy ("stop_writes", "fail"),
%                           log_final_output_field_to_db
%     capture_step_history  default false; fills result.step_history
%     step_history_capacity default 200000 events
%   MATLAB only:
%     live_progress         print progress and logs in the Command Window
%                           while running; Ctrl+C aborts. Default true except
%                           under -batch.
%     progress_style        "inline" (one line redrawn) or "lines"
%     stream_logs           print the runtime log buffer after the call
%
%   Records: with record_z, exactly those positions. Without it,
%   num_records = 1 returns the final field only and z_axis is
%   [propagation_distance]; otherwise num_records uniformly spaced positions
%   from 0 to propagation_distance.
%
%   RESULT (struct)
%     records         records x samples complex matrix
%     z_axis          z of each record
%     final           last record ([] when none returned)
%     step_history    [] unless capture_step_history: step_index, z,
%                     step_size, next_step_size, error, dropped, capacity
%     storage_result  [] unless storage: run_id, records_captured,
%                     records_spilled, chunks_written, db_size_bytes, truncated
%     meta            preset, records_requested, records_written,
%                     backend_requested, coupled, status ("ok")
%
%   Errors: nlolib:invalidOperator, nlolib:invalidPulse,
%   nlolib:invalidOption, nlolib:unavailable, nlolib:statusFailed,
%   nlolib:propagationAborted, nlolib:libraryLoadFailed.
%
%   See also NLOLIB.QUERY_RUNTIME_LIMITS, NLOLIB.TENSOR_RECORD_VIEW.
arguments
    pulse
    linear_operator
    nonlinear_operator
    options.propagation_distance = []
    options.preset = "balanced"
    options.starting_step_size = []
    options.max_step_size = []
    options.min_step_size = []
    options.error_tolerance = []
    options.num_records = []
    options.record_z = []
    options.return_records = true
    options.potential_operator = []
    options.linear_step_operator = []
    options.constant_bindings = []
    options.nonlinear_model = "expr"
    options.nonlinear_gamma = 0.0
    options.raman_fraction = 0.0
    options.raman_tau1 = 0.0122
    options.raman_tau2 = 0.0320
    options.shock_omega0 = 0.0
    options.raman_response_time = []
    options.exec_options = []
    options.storage = []
    options.capture_step_history = false
    options.step_history_capacity = 200000
    options.live_progress = []
    options.progress_style = []
    options.stream_logs = false
end

[cfg, samples, isTensor] = normalize_pulse(pulse);
numTimeSamples = numel(samples);

zEnd = options.propagation_distance;
if isempty(zEnd)
    error('nlolib:invalidOption', 'propagation_distance is required.');
end
zEnd = real_option(zEnd, 'propagation_distance');
if zEnd <= 0
    error('nlolib:invalidOption', 'propagation_distance must be > 0.');
end
cfg.propagation_distance = zEnd;

preset = options.preset;
if ~((ischar(preset) && isrow(preset)) || (isstring(preset) && isscalar(preset))) || ...
        ~ismember(string(preset), ["fast", "balanced", "accuracy"])
    error('nlolib:invalidOption', 'preset must be "fast", "balanced" or "accuracy".');
end
preset = string(preset);
defaults = solver_defaults(preset, zEnd);
solverFields = {'starting_step_size', 'max_step_size', 'min_step_size', 'error_tolerance'};
for idx = 1:numel(solverFields)
    name = solverFields{idx};
    cfg.(name) = defaults.(name);
    if ~isempty(options.(name))
        cfg.(name) = real_option(options.(name), name);
        if cfg.(name) <= 0
            error('nlolib:invalidOption', '%s must be > 0.', name);
        end
    end
end

[numRecords, recordZ, outputMode, zAxis] = resolve_records(options, defaults, zEnd);
returnRecords = logical_option(options.return_records, 'return_records');

% Operators: the C core compiles a different expression set per run type.
bindings = options.constant_bindings;
if ~isempty(bindings) && ~isstruct(bindings) && ~isa(bindings, 'containers.Map')
    error('nlolib:invalidOption', 'constant_bindings must be a struct or a containers.Map.');
end
if isTensor
    slots = {'linear_factor_expr', 'linear_factor', linear_operator; ...
             'linear_expr', 'linear', options.linear_step_operator; ...
             'potential_expr', 'potential', options.potential_operator; ...
             'nonlinear_expr', 'nonlinear', nonlinear_operator};
else
    if ~isempty(options.potential_operator)
        error('nlolib:invalidOption', ...
              'potential_operator needs a tensor run; for a temporal run use pulse.potential_grid.');
    end
    slots = {'dispersion_factor_expr', 'dispersion_factor', linear_operator; ...
             'dispersion_expr', 'dispersion', options.linear_step_operator; ...
             'nonlinear_expr', 'nonlinear', nonlinear_operator};
end
if ~isempty(options.potential_operator) && isfield(cfg, 'potential_grid')
    error('nlolib:invalidOption', ...
          'pass potential_operator or pulse.potential_grid, not both; the core ignores the operator when the grid is set.');
end
runtime = struct();
constants = [];
for idx = 1:size(slots, 1)
    fn = slots{idx, 3};
    optional = idx > 1 && idx < size(slots, 1);
    if optional && isempty(fn)
        continue;
    end
    [expr, captured] = translate_runtime_handle(fn, slots{idx, 2}, bindings);
    runtime.(slots{idx, 1}) = shift_constant_indices(expr, numel(constants));
    constants = [constants, captured]; %#ok<AGROW>
end
runtime.constants = constants;
runtime.nonlinear_model = to_c_enum("nonlinear_model", options.nonlinear_model, 'nonlinear_model');
physicsFields = {'nonlinear_gamma', 'raman_fraction', 'raman_tau1', 'raman_tau2', 'shock_omega0'};
for idx = 1:numel(physicsFields)
    name = physicsFields{idx};
    runtime.(name) = real_option(options.(name), name);
end
if ~isempty(options.raman_response_time)
    if ~isnumeric(options.raman_response_time) || ~isvector(options.raman_response_time)
        error('nlolib:invalidOption', 'raman_response_time must be a numeric vector.');
    end
    runtime.raman_response_time = options.raman_response_time;
end
cfg.runtime = runtime;

ensure_types_loaded();
[execOpts, backendRequested] = make_exec_options(options.exec_options);

storageEnabled = ~isempty(options.storage);
if storageEnabled
    if ~nlolib.storage_is_available()
        error('nlolib:unavailable', 'SQLite storage is not available in this nlolib build.');
    end
    [storageOpts, storageKeepalive] = make_storage_options(options.storage); %#ok<ASGLU>
    storageOptsPtr = libpointer('storage_optionsPtr', storageOpts);
    % An empty libstruct marshals as NULL, so the result would not be written.
    storageResultPtr = libpointer('storage_resultPtr', zeroed_libstruct('storage_result', ...
        {'records_captured', 'records_spilled', 'chunks_written', 'db_size_bytes', 'truncated'}));
else
    if ~returnRecords
        error('nlolib:invalidOption', 'return_records=false needs storage; nothing would be kept.');
    end
    storageOptsPtr = libpointer('storage_optionsPtr');
    storageResultPtr = libpointer('storage_resultPtr');
end

captureStepHistory = logical_option(options.capture_step_history, 'capture_step_history');
stepHistoryCapacity = uint64(count_option(options.step_history_capacity, 'step_history_capacity', 1));

% Command Window output: nlolib calls the progress_mex C callback, which
% prints the log buffer and a progress line through MATLAB. The native stderr
% bar is switched off for the call, since MATLAB does not show the library's
% stdout/stderr.
streamLogs = logical_option(options.stream_logs, 'stream_logs');
liveProgress = ~batch_startup();
if ~isempty(options.live_progress)
    liveProgress = logical_option(options.live_progress, 'live_progress');
end
progressStyle = default_progress_style();
if ~isempty(options.progress_style)
    style = options.progress_style;
    if ~((ischar(style) && isrow(style)) || (isstring(style) && isscalar(style))) || ...
            ~ismember(string(style), ["inline", "lines"])
        error('nlolib:invalidOption', 'progress_style must be "inline" or "lines".');
    end
    progressStyle = char(style);
end

[simCfgPtr, physicsCfgPtr, keepalive] = prepare_sim_config(cfg); %#ok<ASGLU>
inPtr = pack_complex_array(samples);

progressSettings = library_state("progress");
callbackAddress = uint64(0);
if liveProgress && progressSettings.enabled
    callbackAddress = live_progress_callback(progressStyle, progressSettings.milestone_percent);
end
if callbackAddress ~= uint64(0)
    streamLogs = true;
    apply_native_progress(false, progressSettings);
    restoreProgress = onCleanup(@() apply_native_progress(true, progressSettings)); %#ok<NASGU>
end
logBufferBytes = 262144;
if streamLogs && require_function('nlolib_set_log_buffer', false)
    nlolib.set_log_buffer(logBufferBytes);
    nlolib.clear_log_buffer();
end
if running_in_batch_mode() && require_function('nlolib_set_progress_stream', false)
    nlolib.set_progress_stream("both");
end

if returnRecords
    outBuffer = libpointer('doublePtr', zeros(1, 2 * numTimeSamples * numRecords));
else
    % Typed NULL: output_records is declared double* in nlolib_matlab.h.
    outBuffer = libpointer('doublePtr');
end

propagateOptions = libstruct('propagate_options');
propagateOptions.num_recorded_samples = uint64(numRecords);
propagateOptions.output_mode = int32(outputMode);
propagateOptions.return_records = int32(returnRecords);
propagateOptions.exec_options = libpointer('execution_optionsPtr', execOpts);
propagateOptions.storage_options = storageOptsPtr;
propagateOptions.progress_callback = callbackAddress;
% recordZPtr must outlive the calllib below, so it is kept in a local.
if isempty(recordZ)
    recordZPtr = libpointer('doublePtr');
    propagateOptions.explicit_record_z_count = uint64(0);
else
    recordZPtr = libpointer('doublePtr', recordZ);
    propagateOptions.explicit_record_z_count = uint64(numel(recordZ));
end
propagateOptions.explicit_record_z = recordZPtr;

recordsWrittenPtr = libpointer('uint64Ptr', uint64(0));
propagateOutput = libstruct('propagate_output');
propagateOutput.output_records = outBuffer;
propagateOutput.output_record_capacity = uint64(numRecords * returnRecords);
propagateOutput.records_written = recordsWrittenPtr;
propagateOutput.storage_result = storageResultPtr;
if captureStepHistory
    % A plain struct array marshals as a contiguous step_event[].
    % repmat(libstruct(...)) must not be used here: libstruct returns a handle
    % object, so every element would alias one underlying struct.
    stepEventsPtr = libpointer('step_eventPtr', make_step_event_buffer(stepHistoryCapacity));
    propagateOutput.output_step_event_capacity = stepHistoryCapacity;
else
    stepEventsPtr = libpointer('step_eventPtr');
    propagateOutput.output_step_event_capacity = uint64(0);
end
propagateOutput.output_step_events = stepEventsPtr;
stepEventsWrittenPtr = libpointer('uint64Ptr', uint64(0));
stepEventsDroppedPtr = libpointer('uint64Ptr', uint64(0));
propagateOutput.step_events_written = stepEventsWrittenPtr;
propagateOutput.step_events_dropped = stepEventsDroppedPtr;

statusRaw = calllib('nlolib', 'nlolib_propagate', simCfgPtr, physicsCfgPtr, ...
                    uint64(numTimeSamples), inPtr, propagateOptions, propagateOutput);

logs = "";
if streamLogs && require_function('nlolib_read_log_buffer', false)
    logs = nlolib.read_log_buffer(consume=true, max_bytes=logBufferBytes);
    if strlength(logs) > 0
        fprintf('%s', char(logs));
        if ~endsWith(logs, newline)
            fprintf('\n');
        end
    end
end
detail = "";
if strlength(logs) > 0
    detail = "runtime logs:" + newline + logs;
end
status = check_status(statusRaw, 'nlolib_propagate', detail);

recordsWritten = double(recordsWrittenPtr.Value);
if returnRecords
    records = unpack_records(outBuffer, recordsWritten, numTimeSamples);
else
    records = zeros(0, numTimeSamples);
end

result = struct();
result.records = records;
% zAxis holds the intended positions, which for record_z are not a linspace.
% Fall back only when the solver wrote fewer records than were asked for.
if numel(zAxis) == recordsWritten
    result.z_axis = zAxis;
elseif recordsWritten == 1
    result.z_axis = zEnd;
else
    result.z_axis = linspace(0.0, zEnd, recordsWritten);
end
if isempty(records)
    result.final = [];
else
    result.final = records(end, :);
end
result.step_history = [];
if captureStepHistory
    result.step_history = unpack_step_history(stepEventsPtr, ...
                                              double(stepEventsWrittenPtr.Value), ...
                                              double(stepEventsDroppedPtr.Value), ...
                                              double(stepHistoryCapacity));
end
result.storage_result = [];
if storageEnabled
    result.storage_result = to_storage_result(storageResultPtr.Value);
end
result.meta = struct( ...
    'preset', preset, ...
    'records_requested', numRecords, ...
    'records_written', recordsWritten, ...
    'backend_requested', backendRequested, ...
    'coupled', isTensor && (cfg.tensor_nx > 1 || cfg.tensor_ny > 1), ...
    'status', status);
end

% ------------------------------------------------------------------------

function defaults = solver_defaults(preset, z)
% Step sizes are the propagation distance divided by the listed divisor.
switch preset
    case "fast"
        defaults = struct('starting_step_size', z / 120, 'max_step_size', z / 12, ...
                          'min_step_size', z / 4000, 'error_tolerance', 5e-6, ...
                          'num_records', 64);
    case "balanced"
        defaults = struct('starting_step_size', z / 200, 'max_step_size', z / 25, ...
                          'min_step_size', z / 20000, 'error_tolerance', 1e-6, ...
                          'num_records', 128);
    case "accuracy"
        defaults = struct('starting_step_size', z / 400, 'max_step_size', z / 50, ...
                          'min_step_size', z / 80000, 'error_tolerance', 1e-7, ...
                          'num_records', 192);
end
end

function [numRecords, recordZ, outputMode, zAxis] = resolve_records(options, defaults, zEnd)
% record_z given: dense output at exactly those positions. Otherwise
% num_records == 1 is the final field only, and any other count is uniformly
% spaced from 0 to zEnd. C output modes: 0 dense, 1 final only.
recordZ = [];
if ~isempty(options.num_records)
    numRecords = count_option(options.num_records, 'num_records', 1);
end
if ~isempty(options.record_z)
    recordZ = options.record_z;
    if ~isnumeric(recordZ) || ~isreal(recordZ) || ~isvector(recordZ) || any(~isfinite(recordZ))
        error('nlolib:invalidOption', 'record_z must be a vector of finite real numbers.');
    end
    recordZ = reshape(double(recordZ), 1, []);
    if any(recordZ < 0) || any(recordZ > zEnd)
        error('nlolib:invalidOption', 'record_z values must be within [0, propagation_distance].');
    end
    if any(diff(recordZ) < 0)
        error('nlolib:invalidOption', 'record_z must be nondecreasing.');
    end
    if ~isempty(options.num_records) && numRecords ~= numel(recordZ)
        error('nlolib:invalidOption', ...
              'num_records is %d but record_z has %d positions; leave num_records unset.', ...
              numRecords, numel(recordZ));
    end
    numRecords = numel(recordZ);
    outputMode = 0;
    zAxis = recordZ;
    return;
end
if isempty(options.num_records)
    numRecords = defaults.num_records;
end
if numRecords == 1
    outputMode = 1;
    zAxis = zEnd;
else
    outputMode = 0;
    zAxis = linspace(0.0, zEnd, numRecords);
end
end

function value = real_option(value, name)
if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
    error('nlolib:invalidOption', '%s must be a finite real scalar.', name);
end
value = double(value);
end

function shifted = shift_constant_indices(expr, offset)
% Renumber c<k> to c<k+offset> so the operators share one constants table.
[tokens, parts] = regexp(char(expr), '(?<![A-Za-z0-9_])c(\d+)', 'tokens', 'split');
shifted = parts{1};
for idx = 1:numel(tokens)
    shifted = [shifted, sprintf('c%d', str2double(tokens{idx}{1}) + offset), parts{idx + 1}]; %#ok<AGROW>
end
end

function [opts, keepalive] = make_storage_options(storage)
known = {'sqlite_path', 'run_id', 'sqlite_max_bytes', 'chunk_records', ...
         'cap_policy', 'log_final_output_field_to_db'};
if ~isstruct(storage) || ~isscalar(storage)
    error('nlolib:invalidOption', 'storage must be a struct with sqlite_path.');
end
unknown = setdiff(fieldnames(storage), known);
if ~isempty(unknown)
    error('nlolib:invalidOption', 'storage.%s is not a storage option; expected one of %s.', ...
          unknown{1}, strjoin(known, ', '));
end
if ~isfield(storage, 'sqlite_path') || strlength(string(storage.sqlite_path)) == 0
    error('nlolib:invalidOption', 'storage.sqlite_path must be a non-empty string.');
end
keepalive = {};
opts = libstruct('storage_options');
sqlitePathPtr = libpointer('cstring', char(string(storage.sqlite_path)));
keepalive{end + 1} = sqlitePathPtr;
opts.sqlite_path = sqlitePathPtr;
opts.run_id = libpointer();
if isfield(storage, 'run_id') && strlength(string(storage.run_id)) > 0
    runId = char(string(storage.run_id));
    if numel(runId) > 63
        error('nlolib:invalidOption', 'storage.run_id is %d characters; at most 63.', numel(runId));
    end
    runIdPtr = libpointer('cstring', runId);
    keepalive{end + 1} = runIdPtr;
    opts.run_id = runIdPtr;
end
opts.sqlite_max_bytes = uint64(storage_count(storage, 'sqlite_max_bytes'));
opts.chunk_records = uint64(storage_count(storage, 'chunk_records'));
capPolicy = "stop_writes";
if isfield(storage, 'cap_policy') && ~isempty(storage.cap_policy)
    capPolicy = storage.cap_policy;
end
opts.cap_policy = to_c_enum("storage_cap_policy", capPolicy, 'storage.cap_policy');
logFinal = false;
if isfield(storage, 'log_final_output_field_to_db') && ~isempty(storage.log_final_output_field_to_db)
    logFinal = logical_option(storage.log_final_output_field_to_db, ...
                              'storage.log_final_output_field_to_db');
end
opts.log_final_output_field_to_db = int32(logFinal);
end

function value = storage_count(storage, name)
value = 0;
if isfield(storage, name) && ~isempty(storage.(name))
    value = count_option(storage.(name), ['storage.' name], 0);
end
end

function out = to_storage_result(raw)
runId = char(raw.run_id(:).');
nul = find(runId == char(0), 1);
if ~isempty(nul)
    runId = runId(1:(nul - 1));
end
out = struct('run_id', string(runId), ...
             'records_captured', double(raw.records_captured), ...
             'records_spilled', double(raw.records_spilled), ...
             'chunks_written', double(raw.chunks_written), ...
             'db_size_bytes', double(raw.db_size_bytes), ...
             'truncated', logical(raw.truncated));
end

function buffer = make_step_event_buffer(capacity)
% Every element is populated so libpointer() can marshal the array.
zeroCells = num2cell(zeros(1, double(capacity)));
buffer = struct('step_index', zeroCells, 'z_current', zeroCells, ...
                'step_size', zeroCells, 'next_step_size', zeroCells, ...
                'error', zeroCells);
end

function out = unpack_step_history(stepEventsPtr, eventsWritten, eventsDropped, capacity)
% .Value on a struct pointer returns only the first element -- MATLAB keeps no
% element count for struct pointers -- so the array is walked with pointer
% arithmetic.
count = max(0, floor(eventsWritten));
out = struct('step_index', zeros(count, 1), 'z', zeros(count, 1), ...
             'step_size', zeros(count, 1), 'next_step_size', zeros(count, 1), ...
             'error', zeros(count, 1), 'dropped', eventsDropped, 'capacity', capacity);
cursor = stepEventsPtr;
for idx = 1:count
    raw = cursor.Value;
    event = raw(1);
    out.step_index(idx) = double(event.step_index);
    out.z(idx) = double(event.z_current);
    out.step_size(idx) = double(event.step_size);
    out.next_step_size(idx) = double(event.next_step_size);
    out.error(idx) = double(event.error);
    cursor = cursor + 1;
end
end

function apply_native_progress(enabled, settings)
% Toggle the library's own stdout/stderr bar.
calllib('nlolib', 'nlolib_set_progress_options', int32(logical(enabled)), ...
        int32(settings.milestone_percent), int32(logical(settings.emit_on_step_adjust)));
end

function address = live_progress_callback(style, milestonePercent)
% Address of the progress_mex C callback, or 0 when the MEX file is not built
% for this platform, in which case the logs are printed after the run.
address = uint64(0);
libraryPath = library_state("path");
if isempty(libraryPath) || exist('progress_mex', 'file') ~= 3 || ...
        ~require_function('nlolib_read_log_buffer', false)
    return;
end
address = progress_mex('callback', libraryPath, char(style), double(milestonePercent));
end

function style = default_progress_style()
% "lines" where the Command Window ignores backspace: browser-based Command
% Windows (matlab-proxy, MATLAB Online, the R2025a+ desktop) print backspaces
% instead of erasing, so an in-place bar grows into one long line.
style = 'inline';
browserUi = ~isempty(getenv('MWI_APP_PORT')) || contains(getenv('MW_CONTEXT_TAGS'), 'MATLAB_PROXY');
try
    browserUi = browserUi || matlab.internal.environment.context.isMATLABOnline();
catch
end
try
    browserUi = browserUi || (usejava('desktop') && ~isMATLABReleaseOlderThan('R2025a'));
catch
end
if browserUi
    style = 'lines';
end
end

function tf = batch_startup()
try
    tf = batchStartupOptionUsed();
catch
    tf = false;
end
end

function tf = running_in_batch_mode()
try
    tf = ~usejava('desktop');
catch
    tf = false;
end
end
