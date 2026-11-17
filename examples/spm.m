function metrics = spm()
%SPM Self-phase modulation against the closed-form phase evolution.
%   Pure Kerr nonlinearity, no dispersion: A(z, t) = A0 exp(i gamma |A0|^2 z).

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 1024;
dt = 0.01;
pulse_width = 0.2;
beta2 = 0.0;
gamma = 80.0;
z_final = 0.5;
num_records = 100;
% nlolib-example-parameters: end

t = backend.centered_time_grid(n, dt);
a0 = complex(exp(-((t / pulse_width) .^ 2)));
% With beta2 = 0 the frequency axis plays no part; it is left at zero.
pulse = struct('samples', a0, 'delta_time', dt, 'frequency_grid', complex(zeros(1, n)));

nlolib.set_progress_options(enabled=false);
cleanup = onCleanup(@() nlolib.set_progress_options());
result = nlolib.propagate(pulse, ...
    @(A, w) 1i * (0.5 * beta2) * w .* w, ...
    @(A, I, V) 1i * A .* (gamma * I + V), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    preset="accuracy", ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zAxis = result.z_axis(:).';

errorCurve = zeros(1, numel(zAxis));
for idx = 1:numel(zAxis)
    aRef = a0 .* exp(1i * gamma * abs(a0) .^ 2 * zAxis(idx));
    errorCurve(idx) = backend.relative_l2_intensity_error(records(idx, :), aRef);
end
aFinal = records(end, :);
finalError = errorCurve(end);

phaseNum = angle(aFinal .* conj(a0));
phaseRef = gamma * abs(a0) .^ 2 * z_final;
phaseError = angle(exp(1i * (phaseNum - phaseRef)));
support = abs(a0) .^ 2 >= 1e-4 * max(abs(a0) .^ 2);
power0 = sum(abs(a0) .^ 2);
power1 = sum(abs(aFinal) .^ 2);
powerDrift = abs(power1 - power0) / max(power0, 1e-15);

outDir = backend.output_dir("spm");
unwrapped = unwrap(phaseNum);
backend.plot_curves(t(support), {unwrapped(support), phaseRef(support)}, ...
    ["nlolib", "analytic"], fullfile(outDir, "spm_final_phase_shift_comparison.png"), ...
    "x_label", "Time t", "y_label", "Phase shift (rad)");
backend.plot_intensity_colormap_vs_propagation(t, zAxis, abs(records) .^ 2, ...
    fullfile(outDir, "spm_time_intensity_propagation.png"), "x_label", "Time t");
spectra = fftshift(abs(fft(records, [], 2)) .^ 2, 2);
freqAxis = fftshift(backend.angular_frequency_grid(n, dt)) / (2 * pi);
backend.plot_intensity_colormap_vs_propagation(freqAxis, zAxis, spectra, ...
    fullfile(outDir, "spm_frequency_intensity_propagation.png"), ...
    "x_label", "Frequency detuning (1/time)");
backend.plot_total_error_over_propagation(zAxis, errorCurve, ...
    fullfile(outDir, "spm_error_over_propagation.png"), ...
    "y_label", "Relative L2 intensity error");

fprintf("SPM analytical validation summary:\n");
backend.report_metric("final mean pointwise relative error", finalError);
backend.report_metric("power drift", powerDrift);
fprintf("  max wrapped phase error (pulse support)   = %.6e\n", max(abs(phaseError(support))));
metrics = struct('final_error', finalError, 'power_drift', powerDrift);
end
