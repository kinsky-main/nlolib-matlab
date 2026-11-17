function metrics = transverse_grin_beam()
%TRANSVERSE_GRIN_BEAM Off-axis Gaussian beam in a parabolic-index (GRIN) medium, x-y only.
%   A purely transverse run (tensor_nt = 1): the field is an x-y sheet
%   propagated along z by
%       dA/dz = i beta_t (kx^2 + ky^2) A + i V(x, y) A
%   with beta_t = -1/(2 k0) (diffraction) and V = -(k0 g^2 / 2)(x^2 + y^2), the
%   GRIN lens, supplied as a potential grid. A width-matched Gaussian launched
%   at rest off-axis oscillates rigidly about the axis with pitch 2 pi / g, so
%   the numerical centroid is checked against x_offset cos(g z). Lengths in um.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
lambda0 = 1.03;
n0 = 1.45;
g_grin = 0.002;
nx = 128;
ny = 128;
dx = 1.5;
dy = 1.5;
x_offset = 20.0;
num_records = 96;
% nlolib-example-parameters: end
% Derived: k0 = 2 pi n0 / lambda0, z_final = 2 pi / g_grin,
% w_matched = sqrt(2 / (k0 g_grin)), beta_t = -1 / (2 k0).

k0 = 2 * pi * n0 / lambda0;
z_final = 2 * pi / g_grin;
w_matched = sqrt(2 / (k0 * g_grin));
beta_t = -1 / (2 * k0);
grinDepth = -0.5 * k0 * g_grin^2;
fprintf("matched waist = %.2f um, pitch period = %.1f um\n", w_matched, z_final);

x = backend.centered_time_grid(nx, dx);
y = backend.centered_time_grid(ny, dy);
[xx, yy] = meshgrid(x, y);                 % (ny, nx): y fastest, then x
field0 = complex(exp(-((xx - x_offset) .^ 2 + yy .^ 2) / w_matched^2));
potential = complex(grinDepth * (xx .^ 2 + yy .^ 2));
pulse = struct('samples', reshape(field0, 1, []), ...
               'delta_time', 1.0, 'pulse_period', 1.0, 'frequency_grid', complex(0), ...
               'tensor_nt', 1, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'delta_x', dx, 'delta_y', dy, ...
               'potential_grid', reshape(potential, 1, []));

result = nlolib.propagate(pulse, ...
    @(A, wt, kx, ky) 1i * beta_t * (kx .^ 2 + ky .^ 2), ...
    @(A, I, V) 1i * A .* V, ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="accuracy", ...
    exec_options=struct('backend_type', "auto"));
zAxis = result.z_axis(:).';
intensity = abs(result.records) .^ 2;
power = sum(intensity, 2);
powerDrift = abs(power(end) - power(1)) / max(power(1), 1e-12);
centroidX = (intensity * xx(:)) ./ max(power, 1e-30);
centroidAnalytic = x_offset * cos(g_grin * zAxis(:));
centroidError = max(abs(centroidX - centroidAnalytic));

outDir = backend.output_dir("transverse_grin_beam");
centerRow = floor(ny / 2) + 1;
sheets = reshape(intensity, [numel(zAxis), ny, nx]);
backend.plot_intensity_colormap_vs_propagation(x, zAxis, squeeze(sheets(:, centerRow, :)), ...
    fullfile(outDir, "transverse_grin_beam_xz_intensity.png"), ...
    "x_label", "x (um)", "y_label", "Propagation distance z (um)");
backend.plot_curves(zAxis, {centroidX, centroidAnalytic}, ["nlolib centroid", "x_0 cos(g z)"], ...
    fullfile(outDir, "transverse_grin_beam_centroid.png"), ...
    "x_label", "Propagation distance z (um)", "y_label", "Beam centroid x (um)");

fprintf("propagated %.1f um on a %dx%d grid (%d records)\n", z_final, nx, ny, numel(zAxis));
backend.report_metric("power drift", powerDrift);
backend.report_metric("max centroid deviation from x_offset cos(g_grin z)", centroidError);
metrics = struct('power_drift', powerDrift, 'centroid_error', centroidError);
end
