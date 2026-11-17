function metrics = high_order_grin_soliton()
%HIGH_ORDER_GRIN_SOLITON High-order temporal soliton in a GRIN-guided tensor geometry.
%   A single-lobed guided spatial mode, perturbed azimuthally and with a little
%   noise, carries a higher-order temporal soliton envelope. It propagates
%   under a saturable nonlinearity gamma I / (1 + I / I_sat) and a parabolic
%   GRIN potential for propagation_periods soliton periods. The radius, the
%   overlap with the launch field and the power are tracked.
%
%   The launch noise uses MATLAB's random generator seeded with noise_seed,
%   which does not reproduce NumPy's stream, so the noise realisation (not its
%   amplitude) differs from the Python example's.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
soliton_order = 4.5;
saturation_intensity = 2.0;
propagation_periods = 4.0;
azimuthal_amplitude = 0.25;
azimuthal_order = 4;
noise_amplitude = 0.01;
noise_seed = 12345;
nt = 512;
nx = 64;
ny = 64;
dt = 0.02;
dx = 0.06;
dy = 0.06;
temporal_width = 0.3;
mode_width_x = 0.55;
mode_width_y = 0.75;
spatial_chirp = 1.5;
beta2 = -0.08;
beta_t = -0.08;
grin_strength = 0.0015;
gamma_nonlinear = 1.5;
num_records = 24;
starting_step_size = 0.005;
max_step_size = 0.2;
min_step_size = 1e-08;
error_tolerance = 1e-05;
% nlolib-example-parameters: end
% Derived: z_final = propagation_periods x the soliton period of beta2 and
% temporal_width.

ld = temporal_width^2 / abs(beta2);
z_final = propagation_periods * 0.5 * pi * ld;
p1 = abs(beta2) / (gamma_nonlinear * temporal_width^2);    % fundamental soliton power

t = backend.centered_time_grid(nt, dt);
x = backend.centered_time_grid(nx, dx);
y = backend.centered_time_grid(ny, dy);
[xx, yy] = meshgrid(x, y);                                  % (ny, nx)
r2 = xx .^ 2 + yy .^ 2;
envelope = exp(-xx .^ 2 / (2 * mode_width_x^2) - yy .^ 2 / (2 * mode_width_y^2));
previousRng = rng(noise_seed, "twister");
noise = randn(ny, nx);
rng(previousRng);
perturbation = 1 + azimuthal_amplitude * cos(azimuthal_order * atan2(yy, xx)) + noise_amplitude * noise;
transverse = envelope .* perturbation .* exp(1i * spatial_chirp * r2);
temporal = soliton_order * sqrt(p1) ./ cosh(t(:) / temporal_width);
field0 = temporal .* reshape(transverse, [1, ny, nx]);      % (t, y, x)
potential = complex(grin_strength * r2);

pulse = struct('samples', reshape(field0, 1, []), 'delta_time', dt, ...
               'pulse_period', nt * dt, ...
               'frequency_grid', complex(backend.angular_frequency_grid(nt, dt), 0), ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'delta_x', dx, 'delta_y', dy, ...
               'potential_grid', reshape(potential, 1, []));
halfBeta2 = 0.5 * beta2;
gamma = gamma_nonlinear;
isat = saturation_intensity;

nlolib.set_progress_options(enabled=true, milestone_percent=2);
cleanup = onCleanup(@() nlolib.set_progress_options());
result = nlolib.propagate(pulse, ...
    @(A, wt, kx, ky) 1i * (halfBeta2 * wt .* wt + beta_t * (kx .* kx + ky .* ky)), ...
    @(A, I, V) 1i * A .* (gamma * (I ./ (1 + I / isat)) + V), ...
    linear_step_operator=@(A, D, h) exp(h .* D), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    starting_step_size=starting_step_size, ...
    max_step_size=max_step_size, ...
    min_step_size=min_step_size, ...
    error_tolerance=error_tolerance, ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zAxis = result.z_axis(:).';
numZ = numel(zAxis);

intensity = abs(records) .^ 2;
power = sum(intensity, 2);
powerDriftCurve = abs(power - power(1)) / max(power(1), 1e-30);
xyIntensity = squeeze(sum(reshape(intensity, [numZ, nt, ny * nx]), 2));   % records x (y, x)
radius = sqrt((xyIntensity * r2(:)) ./ max(sum(xyIntensity, 2), 1e-30));
launch = field0(:).';
overlap = abs(records * launch') ./ max(norm(launch) * vecnorm(records, 2, 2), 1e-30);
temporalMarginal = sum(reshape(intensity, [numZ, nt, ny * nx]), 3);
centerRow = floor(ny / 2) + 1;
sheets = reshape(intensity, [numZ, nt, ny, nx]);
centerline = squeeze(sum(sheets(:, :, centerRow, :), 2));

outDir = backend.output_dir("high_order_grin_soliton");
backend.plot_intensity_colormap_vs_propagation(x / mode_width_x, zAxis / ld, centerline, ...
    fullfile(outDir, "high_order_grin_soliton_centerline.png"), ...
    "x_label", "x / w_x", "y_label", "z / L_D");
backend.plot_intensity_colormap_vs_propagation(t / temporal_width, zAxis / ld, temporalMarginal, ...
    fullfile(outDir, "high_order_grin_soliton_temporal_marginal.png"), ...
    "x_label", "t / T_0", "y_label", "z / L_D");
backend.plot_curves(zAxis / ld, {radius / radius(1), overlap}, ["radius / launch radius", "overlap fidelity"], ...
    fullfile(outDir, "high_order_grin_soliton_radius_overlap.png"), "x_label", "z / L_D");
backend.plot_curves(zAxis / ld, {powerDriftCurve}, [], ...
    fullfile(outDir, "high_order_grin_soliton_power_drift.png"), ...
    "x_label", "z / L_D", "y_label", "Relative power drift");

fprintf("high-order GRIN saturable soliton summary\n");
backend.report_metric("final radius / launch radius", radius(end) / radius(1));
backend.report_metric("min overlap fidelity", min(overlap));
backend.report_metric("power drift", powerDriftCurve(end));
metrics = struct('radius_ratio', radius(end) / radius(1), 'min_overlap', min(overlap), ...
                 'power_drift', powerDriftCurve(end));
end
