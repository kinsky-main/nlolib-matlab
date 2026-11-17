function metrics = spatiotemporal_kerr_bullet()
%SPATIOTEMPORAL_KERR_BULLET Spatiotemporal Gaussian packet in a bulk Kerr medium.
%       dA/dz = i (b2 wt^2 + beta_t (kx^2 + ky^2)) A + i gamma |A|^2 A
%   with b2 = beta2 / 2 (anomalous) and beta_t = -1/(2 k0) (diffraction). The
%   waist and duration are chosen so the Rayleigh range equals the dispersion
%   length (zR = k0 w0^2 / 2 = T0^2 / |beta2| = l0): the packet spreads equally
%   in time and space, the regime where a light bullet can form.
%
%   Two runs on the same grid: a linear one (gamma = 0), checked against the
%   Gaussian laws T0 sqrt(1 + (z/l0)^2) and w0 sqrt(1 + (z/l0)^2), and a Kerr
%   one in which self-focusing arrests part of the spread. Lengths in um,
%   times in fs; the envelope has unit peak amplitude.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
lambda0 = 1.55;
n0 = 1.444;
beta2 = -0.028;
l0 = 100000.0;
nt = 32;
nx = 64;
ny = 64;
dt = 20.0;
dx = 32.0;
dy = 32.0;
num_records = 48;
% nlolib-example-parameters: end
% Derived: z_final = 1.5 l0, gamma_kerr = 0.6 / l0, beta_t = -1 / (2 k0),
% k0 = 2 pi n0 / lambda0, w0 = sqrt(2 l0 / k0), T0 = sqrt(l0 |beta2|).

k0 = 2 * pi * n0 / lambda0;
w0 = sqrt(2 * l0 / k0);
t0 = sqrt(l0 * abs(beta2));
z_final = 1.5 * l0;
gamma_kerr = 0.6 / l0;
beta_t = -1 / (2 * k0);
fprintf("w0 = %.1f um, T0 = %.1f fs, zR = LD = %.1f mm, z_end = %.1f mm\n", ...
        w0, t0, l0 * 1e-3, z_final * 1e-3);

t = backend.centered_time_grid(nt, dt);
x = backend.centered_time_grid(nx, dx);
y = backend.centered_time_grid(ny, dy);
[xx, yy] = meshgrid(x, y);
spatial = exp(-(xx .^ 2 + yy .^ 2) / w0^2);
temporal = exp(-t(:) .^ 2 / (2 * t0^2));
field0 = complex(temporal .* reshape(spatial, [1, ny, nx]));   % (t, y, x)
omega = backend.angular_frequency_grid(nt, dt);
geom = struct('t', t, 'x', x, 'nt', nt, 'nx', nx, 'ny', ny);
pulse = struct('samples', reshape(field0, 1, []), 'delta_time', dt, ...
               'pulse_period', nt * dt, 'frequency_grid', complex(omega, 0), ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'delta_x', dx, 'delta_y', dy);

linear = run_case(pulse, 0.0, beta2, beta_t, z_final, num_records, geom);
kerr = run_case(pulse, gamma_kerr, beta2, beta_t, z_final, num_records, geom);

growth = sqrt(1 + (linear.z / l0) .^ 2);
widthError = max(abs(sqrt(2) * linear.sigma_t - t0 * growth)) / t0;
radiusError = max(abs(2 * linear.sigma_x - w0 * growth)) / w0;

outDir = backend.output_dir("spatiotemporal_kerr_bullet");
zMm = kerr.z * 1e-3;
backend.plot_intensity_colormap_vs_propagation(t, zMm, kerr.power_t, ...
    fullfile(outDir, "kerr_bullet_power_vs_time.png"), "x_label", "t (fs)", "y_label", "z (mm)");
backend.plot_intensity_colormap_vs_propagation(x, zMm, kerr.fluence_x, ...
    fullfile(outDir, "kerr_bullet_fluence_vs_x.png"), "x_label", "x (um)", "y_label", "z (mm)");
backend.plot_curves(zMm, {sqrt(2) * kerr.sigma_t, sqrt(2) * linear.sigma_t}, ["Kerr", "linear"], ...
    fullfile(outDir, "kerr_bullet_pulse_width.png"), "x_label", "z (mm)", "y_label", "Pulse width T (fs)");
backend.plot_curves(zMm, {2 * kerr.sigma_x, 2 * linear.sigma_x}, ["Kerr", "linear"], ...
    fullfile(outDir, "kerr_bullet_beam_radius.png"), "x_label", "z (mm)", "y_label", "Beam radius w (um)");

fprintf("final peak intensity: linear %.3f, Kerr %.3f (input 1)\n", linear.peak(end), kerr.peak(end));
fprintf("energy drift: linear %.3e, Kerr %.3e\n", linear.energy_drift, kerr.energy_drift);
backend.report_metric("linear-run width error vs analytic Gaussian", widthError);
backend.report_metric("linear-run radius error vs analytic Gaussian", radiusError);
backend.report_metric("energy drift", kerr.energy_drift);
metrics = struct('width_error', widthError, 'radius_error', radiusError, ...
                 'energy_drift', kerr.energy_drift);
end

function out = run_case(pulse, gammaKerr, beta2, beta_t, zFinal, numRecords, geom)
b2 = 0.5 * beta2;
result = nlolib.propagate(pulse, ...
    @(A, wt, kx, ky) 1i * (b2 * wt .^ 2 + beta_t * (kx .^ 2 + ky .^ 2)), ...
    @(A, I) 1i * gammaKerr * A .* I, ...
    propagation_distance=zFinal, ...
    num_records=numRecords, ...
    preset="accuracy", ...
    exec_options=struct('backend_type', "auto"));
numZ = numel(result.z_axis);
intensity = abs(result.records) .^ 2;               % records x (t fastest, y, x)
energy = sum(intensity, 2);
tFlat = repmat(geom.t(:), geom.ny * geom.nx, 1);
xFlat = kron(geom.x(:), ones(geom.nt * geom.ny, 1));
out.z = result.z_axis(:).';
out.sigma_t = sqrt((intensity * tFlat .^ 2) ./ energy).';
out.sigma_x = sqrt((intensity * xFlat .^ 2) ./ energy).';
out.power_t = sum(reshape(intensity, [numZ, geom.nt, geom.ny * geom.nx]), 3);
out.fluence_x = squeeze(sum(reshape(intensity, [numZ, geom.nt * geom.ny, geom.nx]), 2));
out.peak = max(intensity, [], 2).';
out.energy_drift = abs(energy(end) - energy(1)) / max(energy(1), 1e-30);
end
