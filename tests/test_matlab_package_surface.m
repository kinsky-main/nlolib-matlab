function tests = test_matlab_package_surface()
%TEST_MATLAB_PACKAGE_SURFACE Checks the public MATLAB package surface.
%
%   The public surface is the shared binding vocabulary (core
%   docs/binding_api_vocabulary.md): package functions only, no client class,
%   no integer constants, and the low-level config path private. These checks
%   read this checkout's files, since another installed nlolib toolbox would
%   merge into the same package. None needs the shared library.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.root = fileparts(fileparts(mfilename('fullpath')));
end

function test_public_functions_are_the_shared_set(testCase)
package = fullfile(testCase.TestData.root, '+nlolib');
expected = sort({'load', 'loaded_library_path', 'unload', 'propagate', ...
                 'query_runtime_limits', 'storage_is_available', 'tensor_record_view', ...
                 'set_log_file', 'set_log_buffer', 'clear_log_buffer', 'read_log_buffer', ...
                 'set_log_level', 'set_progress_options', 'set_progress_stream', ...
                 'perf_profile_set_enabled', 'perf_profile_is_enabled', ...
                 'perf_profile_reset', 'perf_profile_read'});
files = dir(fullfile(package, '*.m'));
found = sort(erase(setdiff({files.name}, {'Contents.m'}), '.m'));
verifyEqual(testCase, found, expected);
end

function test_removed_names_are_not_public(testCase)
package = fullfile(testCase.TestData.root, '+nlolib');
removed = {'NLolib', 'constants', 'prepare_sim_config', 'pack_complex_array', ...
           'unpack_records', 'debug_probe_complex_ptr', 'translate_runtime_handle'};
for idx = 1:numel(removed)
    verifyFalse(testCase, isfile(fullfile(package, [removed{idx} '.m'])), ...
                sprintf('nlolib.%s must not be public', removed{idx}));
end
end

function test_function_signatures_cover_the_package(testCase)
path = fullfile(testCase.TestData.root, 'resources', 'functionSignatures.json');
signatures = jsondecode(fileread(path));
% jsondecode turns "nlolib.propagate" into a valid field name.
names = fieldnames(signatures);
verifyTrue(testCase, any(contains(names, 'propagate')));
verifyFalse(testCase, any(contains(names, 'NLolib')), ...
            'functionSignatures.json still describes the removed class');
try
    validateFunctionSignaturesJSON(path);
catch ME
    if ~strcmp(ME.identifier, 'MATLAB:UndefinedFunction')
        rethrow(ME);
    end
end
end

function test_tensor_record_view_reshapes_t_fastest(testCase)
nt = 4;
nx = 3;
ny = 2;
record = 1:(nt * nx * ny);

volume = nlolib.tensor_record_view(record, nt, nx, ny);
verifySize(testCase, volume, [nt, ny, nx]);
% t fastest, then y, then x: the first nt samples are the (iy=1, ix=1) column.
verifyEqual(testCase, squeeze(volume(:, 1, 1)).', double(1:nt));
verifyEqual(testCase, volume(1, 2, 1), double(nt + 1));
verifyEqual(testCase, volume(1, 1, 2), double(nt * ny + 1));
end

function test_tensor_record_view_takes_one_record(testCase)
records = [1:8; 11:18];
verifyEqual(testCase, nlolib.tensor_record_view(records(2, :), 2, 2, 2), ...
            reshape(11:18, 2, 2, 2));
verifyError(testCase, @() nlolib.tensor_record_view(records, 2, 2, 2), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.tensor_record_view(records(1, :), 2, 2, 3), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.tensor_record_view(records(1, :), 0, 2, 2), 'nlolib:invalidOption');
end

function test_enum_options_take_strings_only(testCase)
% These fail before any C call, so they need no library either.
verifyError(testCase, @() nlolib.set_log_level(3), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.set_log_level("verbose"), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.set_progress_stream(0), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.set_progress_stream("stdin"), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.set_progress_options(milestone_percent=0), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.read_log_buffer(max_bytes=1), 'nlolib:invalidOption');
end
