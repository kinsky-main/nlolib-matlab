function metrics = grin_soliton_fission()
%GRIN_SOLITON_FISSION Higher-order soliton fission in a graded-index fibre, (t, x, y).
%   A 4th-order soliton (by launch power) enters the fundamental mode of a GRIN
%   multimode fibre. The field A(t, x, y, z), in sqrt(W/um^2), obeys
%       dA/dz = i (beta2/2 w^2 + beta3/6 w^3 - (kx^2 + ky^2)/(2 k0)) A
%             + i (gamma |A|^2 + V(x, y)) A
%   with the parabolic GRIN potential V = -(k0 g^2 / 2)(x^2 + y^2). The fibre
%   holds the beam in its fundamental mode while, in time, third-order
%   dispersion splits the input into fundamental solitons and sheds a
%   dispersive wave on the blue side. Units: um, fs, W.
%
%   The operator's wt is the FFT frequency (+2 pi k / T); with the envelope
%   convention exp(-i w t) the physical offset is w = -wt, so the odd (beta3)
%   term changes sign in the operator.
%
%   Known issue: past about 30 mm a fast component wraps around the 2560 fs
%   time window.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
lambda0 = 1.55;
n0 = 1.45;
beta2 = -0.028;
beta3 = 0.3;
n2 = 2.6e-08;
soliton_order = 4;
t0 = 30.0;
nt = 1024;
dt = 2.5;
nx = 24;
ny = 24;
dx = 2.0;
t_launch = -400.0;
num_records = 48;
error_tolerance = 1e-06;
% nlolib-example-parameters: end
% Derived: g_grin = sqrt(2 * 0.01) / 25 (1% index step, 25 um core),
% z_final = 1.2 t0^2 / |beta2|, step sizes z_final / 500, / 50 and / 1e5.

k0 = 2 * pi * n0 / lambda0;
g_grin = sqrt(2 * 0.01) / 25;
gamma = 2 * pi * n2 / lambda0;
w0 = sqrt(2 / (k0 * g_grin));            % fundamental GRIN mode radius
ld = t0 * t0 / abs(beta2);
gamma_eff = gamma / (pi * w0 * w0);
p0 = soliton_order^2 / (gamma_eff * ld);
z_final = 1.2 * ld;
fprintf("mode radius %.1f um, LD = %.1f mm, P0 = %.2f MW, z = %.1f mm\n", ...
        w0, ld / 1e3, p0 / 1e6, z_final / 1e3);

t = ((0:(nt - 1)) - nt / 2) * dt;
x = ((0:(nx - 1)) - nx / 2) * dx;
y = ((0:(ny - 1)) - ny / 2) * dx;
[xx, yy] = meshgrid(x, y);               % (ny, nx)
mode = exp(-(xx .^ 2 + yy .^ 2) / w0^2);
peakAmp = sqrt(2 * p0 / (pi * w0 * w0));
temporal = peakAmp ./ cosh((t(:) - t_launch) / t0);
field0 = complex(temporal .* reshape(mode, [1, ny, nx]));   % (t, y, x)
potential = complex(-0.5 * k0 * g_grin^2 * (xx .^ 2 + yy .^ 2));

b2 = beta2 / 2;
b3 = beta3 / 6;
bt = -1 / (2 * k0);
pulse = struct('samples', reshape(field0, 1, []), 'delta_time', dt, ...
               'pulse_period', nt * dt, ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'delta_x', dx, 'delta_y', dx, ...
               'potential_grid', reshape(potential, 1, []));
result = nlolib.propagate(pulse, ...
    @(A, wt, kx, ky) 1i * (b2 * wt .* wt - b3 * wt .* wt .* wt + bt * (kx .* kx + ky .* ky)), ...
    @(A, I, V) 1i * A .* (gamma * I + V), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="balanced", ...
    error_tolerance=error_tolerance, ...
    starting_step_size=z_final / 500, ...
    max_step_size=z_final / 50, ...
    min_step_size=z_final / 1e5, ...
    capture_step_history=true, ...
    exec_options=struct('backend_type', "auto"));
steps = result.step_history;
fprintf("%d accepted steps, step %.2f to %.2f um, max local error %.1e\n", ...
        numel(steps.step_size), min(steps.step_size), max(steps.step_size), max(steps.error));

numZ = numel(result.z_axis);
zMm = result.z_axis(:).' / 1e3;
fields = reshape(result.records, [numZ, nt, ny, nx]);
powerT = sum(abs(fields) .^ 2, [3, 4]) * dx * dx;                  % W, records x nt
spectrum = sum(abs(fft(fields, [], 2)) .^ 2, [3, 4]);
centerRow = floor(ny / 2) + 1;
fluenceX = squeeze(sum(abs(fields(:, :, centerRow, :)) .^ 2, 2));
w = -backend.angular_frequency_grid(nt, dt);
[wSorted, order] = sort(w);

energyDrift = abs(sum(powerT(end, :)) / sum(powerT(1, :)) - 1);
peakIn = max(powerT(1, :)) / 1e6;
peakOut = max(powerT(end, :)) / 1e6;

db = @(v) max(10 * log10(v / max(v, [], "all") + 1e-12), -40) + 40;
outDir = backend.output_dir("grin_soliton_fission");
backend.plot_intensity_colormap_vs_propagation(t, zMm, db(powerT), ...
    fullfile(outDir, "grin_soliton_fission_power_db.png"), ...
    "x_label", "t (fs)", "y_label", "z (mm)", "colorbar_label", "Power (dB + 40)");
backend.plot_intensity_colormap_vs_propagation(wSorted, zMm, db(spectrum(:, order)), ...
    fullfile(outDir, "grin_soliton_fission_spectrum_db.png"), ...
    "x_label", "\omega - \omega_0 (rad/fs)", "y_label", "z (mm)", ...
    "colorbar_label", "Spectrum (dB + 40)");
backend.plot_intensity_colormap_vs_propagation(x, zMm, fluenceX, ...
    fullfile(outDir, "grin_soliton_fission_fluence_x.png"), "x_label", "x (um)", "y_label", "z (mm)");

backend.report_metric("energy drift", energyDrift);
backend.report_metric("peak power in", peakIn);
backend.report_metric("peak power out", peakOut);
backend.report_metric("accepted steps", numel(steps.step_size));
fprintf("(peak powers in MW)\n");
metrics = struct('energy_drift', energyDrift, 'peak_power_in', peakIn, ...
                 'peak_power_out', peakOut, 'accepted_steps', numel(steps.step_size));
end
