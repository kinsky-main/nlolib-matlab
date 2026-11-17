function [names, codes] = enum_table(enumName)
%ENUM_TABLE Public strings of one C enum and the C integers they map to.
%   [names, codes] = enum_table(enumName)
%
%   Private. The public API takes and returns these lowercase strings; the
%   integers never leave the package.
switch char(enumName)
    case 'vector_backend'          % execution_options.backend_type
        names = ["cpu", "vulkan", "auto"];
        codes = [0, 1, 2];
    case 'fft_backend'             % execution_options.fft_backend
        names = ["auto", "fftw", "vkfft"];
        codes = [0, 1, 2];
    case 'nonlinear_model'         % runtime_operator_params.nonlinear_model
        names = ["expr", "kerr_raman"];
        codes = [0, 1];
    case 'storage_cap_policy'      % storage_options.cap_policy
        names = ["stop_writes", "fail"];
        codes = [0, 1];
    case 'log_level'               % nlolib_set_log_level
        names = ["error", "warn", "info", "debug"];
        codes = [0, 1, 2, 3];
    case 'progress_stream'         % nlolib_set_progress_stream
        names = ["stderr", "stdout", "both"];
        codes = [0, 1, 2];
    case 'status'                  % nlolib_status
        names = ["ok", "invalid_argument", "allocation_failed", ...
                 "not_implemented", "aborted"];
        codes = [0, 1, 2, 3, 4];
    otherwise
        error("enum_table: unknown enum '%s'", enumName);
end
end
