function metrics = quickstart()
%QUICKSTART A chirped Gaussian under pure dispersion, two records.
%   The shortest complete propagate call: a pulse, a linear and a nonlinear
%   operator written as function handles, and the "balanced" preset.
%   Dispersion alone conserves power, so the initial and final powers agree.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 1024;
dt = 0.01;
sigma = 0.2;
chirp = 12.0;
beta2 = 0.05;
gamma = 0.0;
z_final = 1.0;
num_records = 2;
% nlolib-example-parameters: end

t = backend.centered_time_grid(n, dt);
field0 = exp(-((t / sigma) .^ 2)) .* exp(-1i * chirp * t);
pulse = struct('samples', field0, 'delta_time', dt);

result = nlolib.propagate(pulse, ...
    @(A, w) 1i * (0.5 * beta2) * w .* w, ...
    @(A, I) 1i * gamma * A .* I, ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="balanced", ...
    exec_options=struct('backend_type', "auto"));

initialPower = sum(abs(result.records(1, :)) .^ 2);
finalPower = sum(abs(result.records(end, :)) .^ 2);

fprintf("quickstart completed: z records %s\n", mat2str(result.z_axis, 6));
backend.report_metric("initial power", initialPower);
backend.report_metric("final power", finalPower);
metrics = struct('initial_power', initialPower, 'final_power', finalPower);
end
