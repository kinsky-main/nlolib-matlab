function metrics = sqlite_storage()
%SQLITE_STORAGE Stream records to a SQLite database instead of returning them.
%   The one shared example that sets return_records=false: the records go to
%   the snapshot store in chunks of chunk_records, and the database is then
%   read back.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
nt = 128;
dt = 0.0078125;
pulse_period = 1.0;
z_final = 0.2;
num_records = 24;
chunk_records = 6;
sqlite_max_bytes = 53687091200;
% nlolib-example-parameters: end

if ~nlolib.storage_is_available()
    error("This nlolib build does not include SQLite storage support.");
end
t = ((0:(nt - 1)) - nt / 2) * dt * 8;
pulse = struct('samples', complex(exp(-t .^ 2)), 'delta_time', dt, ...
               'pulse_period', pulse_period, 'frequency_grid', complex(0:(nt - 1)));
dbPath = fullfile(backend.output_dir("sqlite_storage"), "sqlite_storage.sqlite");
if isfile(dbPath)
    delete(dbPath);
end

result = nlolib.propagate(pulse, @(A, w) 0, @(A, I) 0, ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="balanced", ...
    return_records=false, ...
    storage=struct('sqlite_path', dbPath, 'run_id', "sqlite_storage", ...
                   'chunk_records', chunk_records, 'sqlite_max_bytes', sqlite_max_bytes), ...
    exec_options=struct('backend_type', "auto"));
storage = result.storage_result;

fprintf("sqlite db: %s\n", dbPath);
fprintf("storage summary: captured=%d spilled=%d chunks=%d truncated=%d db_size_bytes=%d\n", ...
        storage.records_captured, storage.records_spilled, storage.chunks_written, ...
        storage.truncated, storage.db_size_bytes);
backend.report_metric("records captured", storage.records_captured);
backend.report_metric("chunks written", storage.chunks_written);
backend.report_metric("db size bytes", storage.db_size_bytes);

% Read the database back with MATLAB's own SQLite interface (R2022a+).
try
    conn = sqlite(dbPath, "readonly");
    closer = onCleanup(@() close(conn));
    counts = [fetch(conn, "SELECT COUNT(*) FROM io_runs"), ...
              fetch(conn, "SELECT COUNT(*) FROM io_record_chunks")];
    counts = cellfun(@double, table2cell(counts));
    fprintf("db rows: runs=%d chunks=%d\n", counts(1), counts(2));
catch ME
    fprintf("db rows: not read (%s)\n", ME.message);
end
metrics = struct('records_captured', storage.records_captured, ...
                 'chunks_written', storage.chunks_written, ...
                 'db_size_bytes', storage.db_size_bytes);
end
