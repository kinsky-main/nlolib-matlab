function metrics = second_order_soliton()
%SECOND_ORDER_SOLITON N = 2 soliton over one period against the analytic solution.
%   A second-order soliton, U(0, t) = 2 sech(t) in normalised units, recovers
%   its launch shape after one soliton period z0 = (pi/2) L_D. The final field
%   is compared with the closed-form N = 2 solution, and the run records the
%   adaptive step sizes the solver took.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 4096;
tfwhm = 0.1;
beta2 = -0.01;
gamma = 0.01;
soliton_order = 2;
num_records = 160;
starting_step_size = 0.0001;
max_step_size = 0.01;
min_step_size = 1e-09;
error_tolerance = 1e-10;
% nlolib-example-parameters: end
% Derived: t0 = tfwhm / (2 acosh(sqrt(2))), dt = 40 t0 / n,
% z_final = (pi / 2) t0^2 / |beta2|.

t0 = tfwhm / (2 * acosh(sqrt(2)));
p0 = abs(beta2) / (gamma * t0 * t0);
ld = t0 * t0 / abs(beta2);
z_final = 0.5 * pi * ld;
dt = 40 * t0 / n;
T = backend.centered_time_grid(n, dt);
tau = T / t0;
omega = backend.angular_frequency_grid(n, dt);
A0 = sqrt(p0) * soliton_order ./ cosh(tau);
pulse = struct('samples', A0, 'delta_time', dt, 'frequency_grid', complex(omega, 0));

result = nlolib.propagate(pulse, ...
    @(A, w) 1i * (0.5 * beta2) * w .* w, ...
    @(A, I, V) 1i * A .* (gamma * I + V), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    starting_step_size=starting_step_size, ...
    max_step_size=max_step_size, ...
    min_step_size=min_step_size, ...
    error_tolerance=error_tolerance, ...
    capture_step_history=true, ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zRecords = result.z_axis(:).';

uNum = records(end, :) / sqrt(p0);
uTrue = n2_soliton(tau, zRecords(end) / ld);
epsilon = backend.relative_l2_intensity_error(uNum, uTrue);

truth = zeros(size(records));
for idx = 1:numel(zRecords)
    truth(idx, :) = sqrt(p0) * n2_soliton(tau, zRecords(idx) / ld);
end
errorCurve = zeros(1, numel(zRecords));
for idx = 1:numel(zRecords)
    errorCurve(idx) = backend.relative_l2_intensity_error(records(idx, :), truth(idx, :));
end

outDir = backend.output_dir("second_order_soliton");
band = abs(tau) <= 6;
z0 = 0.5 * pi * ld;
backend.plot_intensity_colormap_vs_propagation(tau(band), zRecords / z0, abs(records(:, band)) .^ 2, ...
    fullfile(outDir, "second_order_soliton_intensity_propagation.png"), ...
    "x_label", "Normalised time t / T_0", "y_label", "z / z_0");
backend.plot_final_intensity_comparison(tau, truth(end, :), records(end, :), ...
    fullfile(outDir, "second_order_soliton_final_intensity_comparison.png"), ...
    "x_label", "Normalised time t / T_0", "reference_label", "Analytic", "final_label", "nlolib");
backend.plot_total_error_over_propagation(zRecords / z0, errorCurve, ...
    fullfile(outDir, "second_order_soliton_error_over_propagation.png"), ...
    "y_label", "Relative L2 intensity error");
steps = result.step_history;
backend.plot_curves(steps.z / z0, {steps.step_size}, [], ...
    fullfile(outDir, "second_order_soliton_step_sizes.png"), ...
    "x_label", "z / z_0", "y_label", "Accepted step size", "log_y", true);

fprintf("second-order soliton: %d accepted steps, %d dropped\n", ...
        numel(steps.step_size), steps.dropped);
backend.report_metric("epsilon (relative L2 intensity error at z_final)", epsilon);
metrics = struct('epsilon', epsilon);
end

function u = n2_soliton(t, xi)
% Closed-form N = 2 soliton of i U_z + 0.5 U_tt + |U|^2 U = 0, U(0, t) = 2 sech(t),
% at xi = z / L_D.
numerator = 4 * (cosh(3 * t) + 3 * exp(4i * xi) * cosh(t)) * exp(0.5i * xi);
denominator = cosh(4 * t) + 4 * cosh(2 * t) + 3 * cos(4 * xi);
u = numerator ./ denominator;
end
