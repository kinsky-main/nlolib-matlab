function runtime_temporal_demo()
setup_matlab_example_environment();

n = 512;
dt = 0.02;
t = backend.centered_time_grid(n, dt);
field0 = exp(-((t / 0.25) .^ 2)) .* exp(-1i * 8.0 * t);

omega = backend.angular_frequency_grid(n, dt);
beta2 = 0.05;

pulse = struct();
pulse.samples = field0;
pulse.delta_time = dt;
pulse.pulse_period = n * dt;
pulse.frequency_grid = complex(omega, zeros(size(omega)));

gamma = 0.01;
linearOperator = @(A, w) 1i * (beta2 / 2.0) * (w .* w);
nonlinearOperator = @(A, I, V) 1i * A .* (gamma * I + V);

nlolib.set_log_buffer(256 * 1024);
nlolib.set_log_level("info");
nlolib.set_progress_options(enabled=true, milestone_percent=10);
simOptions = backend.default_simulation_options( ...
    "backend", "auto", ...
    "fft_backend", "vkfft");
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
    propagation_distance=0.25, ...
    num_records=2, ...
    preset="accuracy", ...
    exec_options=backend.make_exec_options(simOptions), ...
    stream_logs=true);
records = result.records;
finalField = records(end, :).';

fprintf("runtime_temporal_demo: propagated %d samples.\n", n);
fprintf("initial power=%.6e final power=%.6e\n", ...
        sum(abs(field0) .^ 2), sum(abs(finalField) .^ 2));

outputDir = fullfile(fileparts(mfilename("fullpath")), "output", "runtime_temporal_demo");
if ~isfolder(outputDir)
    mkdir(outputDir);
end
plotPath = backend.plot_final_intensity_comparison( ...
    t, records(1, :), records(end, :), ...
    fullfile(outputDir, "final_intensity_comparison.png"), ...
    "x_label", "Time t", ...
    "title", "Runtime Temporal Demo: Initial vs Final Intensity", ...
    "reference_label", "Initial", ...
    "final_label", "Final");
fprintf("saved plot: %s\n", plotPath);
end
