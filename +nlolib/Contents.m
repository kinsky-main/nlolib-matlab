% nlolib  GPU-first nonlinear optics propagation (MATLAB binding).
%
% Solver
%   propagate                - Propagate a pulse or a tensor (t, x, y) field.
%   query_runtime_limits     - Solver memory and record limits for a pulse.
%   storage_is_available     - True when SQLite storage is compiled in.
%   tensor_record_view       - Reshape a tensor record into an (nt, ny, nx) volume.
%
% Library
%   load                     - Load the shared library, optionally from a path.
%   unload                   - Unload the shared library.
%   loaded_library_path      - Path of the loaded shared library.
%
% Logging and progress
%   set_log_level            - Runtime log level threshold.
%   set_log_file             - Write runtime logs to a file.
%   set_log_buffer           - Keep runtime logs in an in-memory buffer.
%   clear_log_buffer         - Empty the log buffer.
%   read_log_buffer          - Read the log buffer.
%   set_progress_options     - Progress bar behaviour.
%   set_progress_stream      - Progress bar output stream.
%
% Performance counters
%   perf_profile_set_enabled - Turn the counters on or off.
%   perf_profile_is_enabled  - True when the counters are on.
%   perf_profile_reset       - Zero the counters.
%   perf_profile_read        - Read the counters.
%
% Setup
%   nlolib_setup             - Add nlolib (and its examples) to the MATLAB path.
%
% Examples are in the toolbox folder examples/matlab; the user guide is
% docs/matlab_user_guide.md.
