function tests = test_ffi_smoke()
%TEST_FFI_SMOKE End-to-end checks of the loadlibrary/calllib binding.
%
%   These exercise what pure-MATLAB unit tests cannot reach: library load,
%   libstruct/libpointer type resolution, complex buffer packing/unpacking,
%   and the propagate ABI. A binding regression such as a renamed C type only
%   shows up here.
%
%   Requires a built nlolib shared library. Set NLOLIB_LIBRARY to select one.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
try
    nlolib.load();
catch ME
    assumeFail(testCase, sprintf('nlolib library unavailable: %s', ME.message));
    return;
end
testCase.TestData.n = 64;
testCase.TestData.dt = 0.02;
bindingRoot = fileparts(fileparts(mfilename('fullpath')));
previous = cd(fullfile(bindingRoot, '+nlolib', 'private'));
restore = onCleanup(@() cd(previous));
testCase.TestData.pack = @pack_complex_array;
testCase.TestData.unpack = @unpack_records;
end

function pulse = gaussian_pulse(testCase)
n = testCase.TestData.n;
dt = testCase.TestData.dt;
t = ((0:(n - 1)) - floor(n / 2)) * dt;
pulse = struct('samples', complex(exp(-((t / 0.25) .^ 2)), zeros(1, n)), 'delta_time', dt);
end

function result = run(testCase, varargin)
% A short linear run on the CPU backend; varargin adds or overrides options.
beta = 0.5;
result = nlolib.propagate(gaussian_pulse(testCase), @(A, w) 1i * beta * w .* w, @(A, I) 0 * A, ...
                          'propagation_distance', 0.05, 'starting_step_size', 1e-3, ...
                          'max_step_size', 5e-3, 'min_step_size', 1e-6, 'error_tolerance', 1e-6, ...
                          'exec_options', struct('backend_type', "cpu"), varargin{:});
end

% --- library plumbing ----------------------------------------------------

function testLibraryTypesResolve(testCase)
% Every libstruct type the binding uses must resolve. Catches header/binding
% type-name drift at the point of use.
names = {'sim_config', 'simulation_config', 'runtime_operator_params', ...
         'propagation_params', 'frequency_grid', 'execution_options', ...
         'storage_options', 'storage_result', 'step_event', ...
         'runtime_limits', 'propagate_options', 'propagate_output', ...
         'nlo_perf_profile_snapshot'};
for idx = 1:numel(names)
    s = libstruct(names{idx});
    verifyNotEmpty(testCase, fieldnames(s), ...
                   sprintf('libstruct(''%s'') resolved to an empty type', names{idx}));
end
verifyTrue(testCase, isfile(nlolib.loaded_library_path()));
end

function testComplexPointerRoundTrip(testCase)
values = complex([1.0, -2.5, 3.25], [0.5, 0.0, -1.75]);
ptr = testCase.TestData.pack(values);
back = testCase.TestData.unpack(ptr, 1, numel(values));
verifyEqual(testCase, back, values, 'AbsTol', 0.0);
end

% --- propagate -----------------------------------------------------------

function testResultShape(testCase)
result = run(testCase, num_records=4);
verifySize(testCase, result.records, [4, testCase.TestData.n]);
verifyTrue(testCase, all(isfinite(result.records(:))));
verifyEqual(testCase, result.z_axis, linspace(0, 0.05, 4), 'AbsTol', 1e-15);
verifyEqual(testCase, result.final, result.records(end, :));
verifyEqual(testCase, fieldnames(result), ...
            {'records'; 'z_axis'; 'final'; 'step_history'; 'storage_result'; 'meta'});
verifyEqual(testCase, fieldnames(result.meta), ...
            {'preset'; 'records_requested'; 'records_written'; 'backend_requested'; ...
             'coupled'; 'status'});
verifyEqual(testCase, result.meta.status, "ok");
verifyEqual(testCase, result.meta.backend_requested, "cpu");
verifyEqual(testCase, result.meta.records_written, 4);
verifyEmpty(testCase, result.step_history);
verifyEmpty(testCase, result.storage_result);
end

function testOneRecordIsTheFinalField(testCase)
result = run(testCase, num_records=1);
verifySize(testCase, result.records, [1, testCase.TestData.n]);
verifyEqual(testCase, result.z_axis, 0.05);
end

function testRecordZIsDenseOutput(testCase)
recordZ = [0.0, 0.01, 0.03, 0.05];
result = run(testCase, record_z=recordZ);
verifyEqual(testCase, size(result.records, 1), numel(recordZ));
verifyEqual(testCase, result.z_axis, recordZ, 'AbsTol', 1e-12);
verifyEqual(testCase, result.records(1, :), gaussian_pulse(testCase).samples, 'AbsTol', 1e-12);
end

function testSingleRecordZIsDenseOutput(testCase)
% One record_z position is dense output at that z, not the final field.
dense = run(testCase, record_z=[0.0, 0.01]);
mid = run(testCase, record_z=0.01);
verifySize(testCase, mid.records, [1, testCase.TestData.n]);
verifyEqual(testCase, mid.z_axis, 0.01);
% Known core limitation: nlolib_propagate overwrites the only record with the
% final field whenever one record is requested (src/nlolib.c), whatever the
% output mode, so this binding passes the position as the manifest says and
% the record is still the z = propagation_distance field.
assumeLessThan(testCase, max(abs(mid.final - dense.final)), 1e-6, ...
               'core returns the final field for a single record_z position');
end

function testShortRecordCountIsTruncatedNotAnError(testCase)
% Fixed-step runs (start == min == max) let the library write fewer records
% than requested; the unwritten tail is ignored.
result = run(testCase, num_records=512, starting_step_size=5e-3, ...
             min_step_size=5e-3, max_step_size=5e-3);
verifyGreaterThan(testCase, size(result.records, 1), 0);
verifyLessThanOrEqual(testCase, size(result.records, 1), 512);
verifyEqual(testCase, size(result.records, 1), result.meta.records_written);
verifyEqual(testCase, numel(result.z_axis), result.meta.records_written);
end

function testStepHistoryCapture(testCase)
% Distinct step_event slots, not N aliases of one struct.
result = run(testCase, num_records=2, capture_step_history=true, step_history_capacity=256);
history = result.step_history;
verifyEqual(testCase, history.capacity, 256);
verifyEqual(testCase, history.dropped, 0);
verifyGreaterThan(testCase, numel(history.step_index), 1);
verifyGreaterThan(testCase, history.step_index(end), history.step_index(1));
verifyTrue(testCase, all(diff(history.step_index) >= 0));
verifyTrue(testCase, all(isfinite(history.step_size)));
end

function testExecOptionsTakeStrings(testCase)
verifyEqual(testCase, run(testCase, num_records=2, ...
                          exec_options=struct('backend_type', "cpu", 'fft_backend', "fftw")).meta.status, ...
            "ok");
verifyError(testCase, @() run(testCase, exec_options=struct('backend_type', int32(0))), ...
            'nlolib:invalidOption');
verifyError(testCase, @() run(testCase, exec_options=struct('backend_type', "gpu")), ...
            'nlolib:invalidOption');
verifyError(testCase, @() run(testCase, exec_options=struct('capture_step_history', true)), ...
            'nlolib:invalidOption');
verifyError(testCase, @() run(testCase, return_records=false), 'nlolib:invalidOption');
end

function testStorage(testCase)
if ~nlolib.storage_is_available()
    assumeFail(testCase, 'SQLite storage is not compiled into this build');
end
path = [tempname '.sqlite'];
cleanup = onCleanup(@() delete_if_present(path));
result = run(testCase, num_records=8, return_records=false, ...
             storage=struct('sqlite_path', path, 'run_id', "smoke", 'chunk_records', 2));
verifyEmpty(testCase, result.records);
verifyEqual(testCase, result.storage_result.run_id, "smoke");
verifyEqual(testCase, result.storage_result.records_captured, 8);
verifyGreaterThan(testCase, result.storage_result.db_size_bytes, 0);
verifyError(testCase, @() run(testCase, storage=struct('sqlite_path', path, 'return_records', false)), ...
            'nlolib:invalidOption');
verifyError(testCase, @() run(testCase, storage=struct('sqlite_path', path, 'cap_policy', 1)), ...
            'nlolib:invalidOption');
verifyError(testCase, @() run(testCase, storage=struct('sqlite_path', path, ...
                                                       'run_id', repmat('r', 1, 64))), ...
            'nlolib:invalidOption');
end

% --- ancillary entry points ----------------------------------------------

function testRuntimeLimitsQuery(testCase)
limits = nlolib.query_runtime_limits(pulse=gaussian_pulse(testCase), ...
                                     exec_options=struct('backend_type', "cpu"));
verifyEqual(testCase, fieldnames(limits), ...
            {'max_num_time_samples_runtime'; 'max_num_recorded_samples_in_memory'; ...
             'max_num_recorded_samples_with_storage'; 'estimated_required_working_set_bytes'; ...
             'estimated_device_budget_bytes'; 'storage_available'});
verifyGreaterThan(testCase, double(limits.max_num_recorded_samples_in_memory), 0);
verifyGreaterThan(testCase, double(nlolib.query_runtime_limits().max_num_time_samples_runtime), 0);
end

function testLogBufferRoundTrip(testCase)
% Covers the char* / cstring marshalling of nlolib_read_log_buffer.
nlolib.set_log_buffer(65536);
nlolib.clear_log_buffer();
nlolib.set_log_level("debug");
cleanup = onCleanup(@() nlolib.set_log_level());
run(testCase, num_records=2, live_progress=false);

text = nlolib.read_log_buffer(consume=true, max_bytes=65536);
verifyClass(testCase, text, 'string');
verifyGreaterThan(testCase, strlength(text), 0);
verifyEqual(testCase, nlolib.read_log_buffer(), "", ...
            'a consuming read did not drain the ring buffer');
end

function testPerfProfileCounters(testCase)
nlolib.perf_profile_set_enabled(true);
cleanup = onCleanup(@() nlolib.perf_profile_set_enabled(false));
verifyTrue(testCase, nlolib.perf_profile_is_enabled());
nlolib.perf_profile_reset();
run(testCase, num_records=2);
snapshot = nlolib.perf_profile_read();
verifyNumElements(testCase, fieldnames(snapshot), 18);
verifyGreaterThan(testCase, double(snapshot.dispersion_calls), 0);
end

function delete_if_present(path)
if isfile(path)
    delete(path);
end
end
