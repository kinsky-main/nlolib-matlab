function runtime_callable_operator_rk4ip()
%RUNTIME_CALLABLE_OPERATOR_RK4IP Callable runtime-operator demo.

setup_matlab_example_environment();

n = 1024;
dt = 0.01;
beta2 = 0.05;
scale = beta2 / 2.0;
zFinal = 1.0;
t = backend.centered_time_grid(n, dt);
field0 = exp(-((t / 0.20) .^ 2)) .* exp((-1.0i) * 12.0 * t);

pulse = struct();
pulse.samples = field0;
pulse.delta_time = dt;
pulse.pulse_period = n * dt;
pulse.frequency_grid = complex(backend.angular_frequency_grid(n, dt), zeros(1, n));

linearOperator = @(A, w) 1i * scale .* (w .* w);
nonlinearOperator = @(A, I) 0 .* I;

simOptions = backend.default_simulation_options( ...
    "backend", "auto", ...
    "fft_backend", "vkfft");
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
    propagation_distance=zFinal, ...
    num_records=2, ...
    preset="accuracy", ...
    exec_options=backend.make_exec_options(simOptions));
records = result.records;
zRecords = result.z_axis;

fprintf("runtime callable example completed.\n");
fprintf("z records: [%g, %g]\n", zRecords(1), zRecords(end));
fprintf("initial power=%.6e\n", sum(abs(records(1, :)) .^ 2));
fprintf("final power=%.6e\n", sum(abs(records(end, :)) .^ 2));
end
