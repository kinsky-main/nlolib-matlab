function metrics = linear_drift()
%LINEAR_DRIFT Linear dispersive drift of a Gaussian with a phase ramp.
%   Nonlinearity is off (gamma = 0) and the launch carries the phase ramp
%   exp(-i*chirp*t), so the pulse drifts in time at the rate beta2*chirp. The
%   centroid slope is checked against that prediction, and every record
%   against the exact linear solution.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 1024;
dt = 0.01;
sigma = 0.2;
chirp = 12.0;
beta2 = 0.05;
gamma = 0.0;
z_final = 1.0;
num_records = 180;
% nlolib-example-parameters: end

t = backend.centered_time_grid(n, dt);
omega = backend.angular_frequency_grid(n, dt);
field0 = exp(-((t / sigma) .^ 2)) .* exp(-1i * chirp * t);
pulse = struct('samples', field0, 'delta_time', dt, ...
               'frequency_grid', complex(omega, 0));

result = nlolib.propagate(pulse, ...
    @(A, w) 1i * (0.5 * beta2) * w .* w, ...
    @(A, I, V) 1i * A .* (gamma * I + V), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="accuracy", ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zRecords = result.z_axis(:).';

intensity = abs(records) .^ 2;
centroid = (intensity * t(:)) ./ sum(intensity, 2);
centroidShift = centroid - centroid(1);
fit = polyfit(zRecords(:), centroidShift(:), 1);
measuredSlope = fit(1);
predictedSlope = beta2 * chirp;
slopeRelError = abs(measuredSlope - predictedSlope) / max(abs(predictedSlope), 1e-12);

% Exact linear solution: D(w) = i (beta2/2) w^2 applied in the FFT domain.
spectrum0 = fft(field0);
reference = zeros(size(records));
errorCurve = zeros(1, numel(zRecords));
for idx = 1:numel(zRecords)
    reference(idx, :) = ifft(spectrum0 .* exp(1i * (0.5 * beta2) * omega .^ 2 * zRecords(idx)));
    errorCurve(idx) = 100 * backend.relative_l2_intensity_error(records(idx, :), reference(idx, :));
end

outDir = backend.output_dir("linear_drift");
band = abs(t) <= 1.5;
backend.plot_intensity_colormap_vs_propagation(t(band), zRecords, intensity(:, band), ...
    fullfile(outDir, "linear_drift_intensity_propagation_map.png"), ...
    "x_label", "Time t", "title", "Linear drift: intensity");
backend.plot_final_re_im_comparison(t, records(1, :), records(end, :), ...
    fullfile(outDir, "linear_drift_final_re_im_comparison.png"), ...
    "x_label", "Time t", "reference_label", "Initial", "final_label", "Final");
backend.plot_final_intensity_comparison(t, records(1, :), records(end, :), ...
    fullfile(outDir, "linear_drift_final_intensity_comparison.png"), ...
    "x_label", "Time t", "reference_label", "Initial", "final_label", "Final");
backend.plot_total_error_over_propagation(zRecords, errorCurve, ...
    fullfile(outDir, "linear_drift_total_error_over_propagation.png"), ...
    "y_label", "Relative L2 intensity error (%)");

fprintf("linear drift example completed.\n");
fprintf("slope (signed): measured=%.6e, predicted=%.6e\n", measuredSlope, predictedSlope);
backend.report_metric("centroid slope relative error", slopeRelError);
fprintf("final intensity error vs exact linear solution: %.6e %%\n", errorCurve(end));
metrics = struct('centroid_slope_relative_error', slopeRelError);
end
