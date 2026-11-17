function metrics = tensor_dispersion_3d()
%TENSOR_DISPERSION_3D Linear (t, x, y) dispersion and diffraction against the exact solution.
%   D = i (beta2/2 wt^2 + beta_t (kx^2 + ky^2)) is diagonal in the 3-D FFT
%   domain, so every record has a closed form; the run is compared with it.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
nt = 128;
nx = 64;
ny = 64;
dt = 0.04;
dx = 0.15;
dy = 0.15;
temporal_width = 0.24;
x_width = 0.6;
y_width = 0.7;
beta2 = 0.08;
beta_t = -0.2;
z_final = 0.8;
num_records = 24;
starting_step_size = 0.02;
max_step_size = 0.08;
min_step_size = 1e-05;
error_tolerance = 1e-07;
% nlolib-example-parameters: end

t = backend.centered_time_grid(nt, dt);
x = backend.centered_time_grid(nx, dx);
y = backend.centered_time_grid(ny, dy);
omega = backend.angular_frequency_grid(nt, dt);
kx = backend.angular_frequency_grid(nx, dx);
ky = backend.angular_frequency_grid(ny, dy);

% (nt, ny, nx): MATLAB's column-major order is the solver's layout (t fastest,
% then y, then x), so the volume flattens with a plain reshape.
[xx, yy] = meshgrid(x, y);
transverse = exp(-(xx / x_width) .^ 2 - (yy / y_width) .^ 2);
field0 = complex(exp(-(t(:) / temporal_width) .^ 2) .* reshape(transverse, [1, ny, nx]));
pulse = struct('samples', reshape(field0, 1, []), 'delta_time', dt, ...
               'frequency_grid', complex(omega, 0), ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'delta_x', dx, 'delta_y', dy);

result = nlolib.propagate(pulse, ...
    @(A, wt, kx, ky) 1i * ((0.5 * beta2) * wt .^ 2 + beta_t * (kx .^ 2 + ky .^ 2)), ...
    @(A, I, V) 0, ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    starting_step_size=starting_step_size, ...
    max_step_size=max_step_size, ...
    min_step_size=min_step_size, ...
    error_tolerance=error_tolerance, ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zRecords = result.z_axis(:).';

linearFactor = 1i * ((0.5 * beta2) * omega(:) .^ 2 + ...
                     beta_t * (reshape(ky, [1, ny]) .^ 2 + reshape(kx, [1, 1, nx]) .^ 2));
spectrum0 = fftn(field0);
fieldError = zeros(1, numel(zRecords));
for idx = 1:numel(zRecords)
    reference = ifftn(spectrum0 .* exp(linearFactor * zRecords(idx)));
    numerical = reshape(records(idx, :), [nt, ny, nx]);
    fieldError(idx) = norm(numerical(:) - reference(:)) / max(norm(reference(:)), 1e-30);
end
power = sum(abs(records) .^ 2, 2);
powerDrift = abs(power(end) - power(1)) / max(power(1), 1e-30);

outDir = backend.output_dir("tensor_dispersion_3d");
intensity = reshape(abs(records) .^ 2, [numel(zRecords), nt, ny, nx]);
backend.plot_intensity_colormap_vs_propagation(t, zRecords, sum(intensity, [3, 4]), ...
    fullfile(outDir, "tensor_dispersion_3d_temporal_marginal.png"), "x_label", "Time t");
backend.plot_intensity_colormap_vs_propagation(x, zRecords, squeeze(sum(intensity, [2, 3])), ...
    fullfile(outDir, "tensor_dispersion_3d_x_marginal.png"), "x_label", "x");
backend.plot_total_error_over_propagation(zRecords, 100 * fieldError, ...
    fullfile(outDir, "tensor_dispersion_3d_field_error.png"), ...
    "y_label", "Relative L2 field error (%)");

fprintf("tensor 3D dispersion example completed: %d records of %d samples.\n", size(records));
backend.report_metric("final field relative error vs exact linear solution", fieldError(end));
backend.report_metric("power drift", powerDrift);
metrics = struct('final_field_error', fieldError(end), 'power_drift', powerDrift);
end
