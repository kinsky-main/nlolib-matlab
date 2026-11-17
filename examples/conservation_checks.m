function metrics = conservation_checks()
%CONSERVATION_CHECKS Energy, momentum and Hamiltonian of a lossless NLSE run.
%   A fundamental soliton with a carrier tilt (so the momentum is non-zero),
%   propagated over 0.2 dispersion lengths; the three invariants are tracked
%   relative to their launch values.

setup_matlab_example_environment();

% nlolib-example-parameters: begin
n = 1024;
tfwhm = 0.1;
beta2 = -0.01;
gamma = 0.01;
carrier = 12.0;
num_records = 100;
error_tolerance = 1e-06;
% nlolib-example-parameters: end
% Derived: dt = 16 t0 / n, z_final = 0.2 t0^2 / |beta2|, step sizes
% z_final / 1000, / 600 and / 15000.

t0 = tfwhm / (2 * acosh(sqrt(2)));
p0 = abs(beta2) / (gamma * t0 * t0);
ld = t0 * t0 / abs(beta2);
z_final = 0.2 * ld;
dt = 16 * t0 / n;
t = backend.centered_time_grid(n, dt);
omega = backend.angular_frequency_grid(n, dt);
a0 = sqrt(p0) ./ cosh(t / t0) .* exp(-1i * carrier * t);
pulse = struct('samples', a0, 'delta_time', dt, 'frequency_grid', complex(omega, 0));

nlolib.set_progress_options(enabled=false);
cleanup = onCleanup(@() nlolib.set_progress_options());
result = nlolib.propagate(pulse, ...
    @(A, w) 1i * (0.5 * beta2) * w .* w, ...
    @(A, I, V) 1i * A .* (gamma * I + V), ...
    propagation_distance=z_final, ...
    num_records=num_records, ...
    starting_step_size=z_final / 1000, ...
    max_step_size=z_final / 600, ...
    min_step_size=z_final / 15000, ...
    error_tolerance=error_tolerance, ...
    exec_options=struct('backend_type', "auto"));
records = result.records;
zAxis = result.z_axis(:).';

numRecords = size(records, 1);
energy = zeros(1, numRecords);
momentum = zeros(1, numRecords);
hamiltonian = zeros(1, numRecords);
for idx = 1:numRecords
    a = records(idx, :);
    da = ifft(1i * omega .* fft(a));
    energy(idx) = sum(abs(a) .^ 2) * dt;
    momentum(idx) = imag(sum(conj(a) .* da)) * dt;
    hamiltonian(idx) = (0.5 * beta2 * sum(abs(da) .^ 2) - 0.5 * gamma * sum(abs(a) .^ 4)) * dt;
end
drift = @(v) (v - v(1)) / max(abs(v(1)), 1e-15);
energyDrift = drift(energy);
momentumDrift = drift(momentum);
hamiltonianDrift = drift(hamiltonian);

outDir = backend.output_dir("conservation_checks");
backend.plot_curves(zAxis / ld, {energyDrift, momentumDrift, hamiltonianDrift}, ...
    ["Energy drift", "Momentum drift", "Hamiltonian drift"], ...
    fullfile(outDir, "energy_conservation_relative_invariant_drift.png"), ...
    "x_label", "Normalised propagation z / L_D", "y_label", "Relative drift");

fprintf("conservation-check summary:\n");
backend.report_metric("max energy drift", max(abs(energyDrift)));
backend.report_metric("max momentum drift", max(abs(momentumDrift)));
backend.report_metric("max Hamiltonian drift", max(abs(hamiltonianDrift)));
metrics = struct('max_energy_drift', max(abs(energyDrift)), ...
                 'max_momentum_drift', max(abs(momentumDrift)), ...
                 'max_hamiltonian_drift', max(abs(hamiltonianDrift)));
end
