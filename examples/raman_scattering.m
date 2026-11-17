function metrics = raman_scattering()
%RAMAN_SCATTERING Raman self-frequency shift against the centroid-moment prediction.
%   A fundamental soliton is propagated twice: with the Kerr expression only,
%   and with the built-in Kerr + Raman model. The Raman run's spectral
%   centroid moves to the red; its trajectory is checked against the
%   prediction integrated from the moment equation
%     d<w>/dz = -(gamma f_R / E) int |A|^2 d/dt (h_R * |A|^2) dt.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 4096;
dt = 0.002;
beta2 = -0.01;
gamma = 1.4;
pulse_width = 0.08;
z_final = 0.4;
num_records = 80;
f_r = 0.18;
tau1 = 0.0522;
tau2 = 0.032;
shock_omega0 = 0.0;
error_tolerance = 2e-08;
% nlolib-example-parameters: end
% Derived: step sizes z_final / 500, / 80 and / 20000.

t = backend.centered_time_grid(n, dt);
omega = backend.angular_frequency_grid(n, dt);
p0 = abs(beta2) / (gamma * pulse_width * pulse_width);
ld = pulse_width * pulse_width / abs(beta2);
field0 = complex(sqrt(p0) ./ cosh(t / pulse_width));
pulse = struct('samples', field0, 'delta_time', dt, 'frequency_grid', complex(omega, 0));
common = {'propagation_distance', z_final, 'num_records', num_records, ...
          'starting_step_size', z_final / 500, 'max_step_size', z_final / 80, ...
          'min_step_size', z_final / 20000, 'error_tolerance', error_tolerance, ...
          'nonlinear_gamma', gamma, 'shock_omega0', shock_omega0, ...
          'exec_options', struct('backend_type', "auto")};
linearOp = @(A, w) 1i * (0.5 * beta2) * w .* w;

kerr = nlolib.propagate(pulse, linearOp, @(A, I) 1i * gamma * A .* I, ...
                        common{:}, nonlinear_model="expr", raman_fraction=0.0);
raman = nlolib.propagate(pulse, linearOp, @(A, I) 0, ...
                         common{:}, nonlinear_model="kerr_raman", ...
                         raman_fraction=f_r, raman_tau1=tau1, raman_tau2=tau2);
zAxis = raman.z_axis(:).';

% Spectra in the optics convention used by the examples: IFFT to frequency.
omegaAxis = fftshift(omega);
kerrSpec = abs(fftshift(ifft(kerr.records, [], 2), 2)) .^ 2;
ramanSpec = abs(fftshift(ifft(raman.records, [], 2), 2)) .^ 2;
centroid = @(spec) (spec * omegaAxis(:)) ./ max(sum(spec, 2), 1e-15);
kerrCentroid = centroid(kerrSpec);
ramanCentroid = centroid(ramanSpec);

% Moment-equation prediction from the Raman run's own records.
tr = (0:(n - 1)) * dt;
response = (tau1^2 + tau2^2) / (tau1 * tau2^2) * exp(-tr / tau2) .* sin(tr / tau1);
response = response / (sum(response) * dt);
responseFft = fft(response);
rhs = zeros(numel(zAxis), 1);
for idx = 1:numel(zAxis)
    intensity = abs(raman.records(idx, :)) .^ 2;
    delayed = real(ifft(fft(intensity) .* responseFft));
    delayedDt = real(ifft(1i * omega .* fft(delayed)));
    energy = max(sum(intensity) * dt, 1e-15);
    rhs(idx) = -(gamma * f_r / energy) * sum(intensity .* delayedDt) * dt;
end
predicted = ramanCentroid(1) + cumtrapz(zAxis(:), rhs);
centeredNum = ramanCentroid - ramanCentroid(1);
centeredPred = predicted - predicted(1);
curveError = backend.relative_l2_intensity_error(centeredNum, centeredPred);

outDir = backend.output_dir("raman_scattering");
backend.plot_intensity_colormap_vs_propagation(t, zAxis / ld, abs(raman.records) .^ 2, ...
    fullfile(outDir, "raman_time_intensity_propagation.png"), ...
    "x_label", "Time t", "y_label", "z / L_D");
backend.plot_intensity_colormap_vs_propagation(omegaAxis, zAxis / ld, ramanSpec, ...
    fullfile(outDir, "raman_spectral_intensity_propagation.png"), ...
    "x_label", "Angular frequency detuning", "y_label", "z / L_D");
backend.plot_curves(zAxis / ld, {centeredNum, centeredPred, kerrCentroid - kerrCentroid(1)}, ...
    ["Raman (nlolib)", "Raman (moment prediction)", "Kerr only"], ...
    fullfile(outDir, "raman_centroid_shift.png"), ...
    "x_label", "z / L_D", "y_label", "Spectral centroid shift");

fprintf("raman scattering summary:\n");
fprintf("  final centroid shift (raman-kerr) = %.6e\n", ramanCentroid(end) - kerrCentroid(end));
fprintf("  predicted centroid shift          = %.6e\n", centeredPred(end));
backend.report_metric("centroid-curve relative error vs prediction", curveError);
metrics = struct('centroid_curve_relative_error', curveError);
end
