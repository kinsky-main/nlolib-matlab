function tests = test_runtime_handle_parser()
%TEST_RUNTIME_HANDLE_PARSER Operator function handles: lowering and parity.
%
%   Operators are function handles only. The handles are lowered to the C
%   runtime expressions privately, so these tests read the lowered text back
%   from the runtime_operator_params libstruct that prepare_sim_config builds.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
try
    testCase.TestData.api = nlolib.NLolib();
catch ME
    assumeFail(testCase, sprintf('nlolib library unavailable: %s', ME.message));
end
end

function testTranslateElementwiseAndImaginaryUnit(testCase)
beta2 = 0.5;
lowered = lower_runtime(struct('dispersion_factor_fn', @(A, w) 1i * beta2 .* (w .^ 2)));

verifyEqual(testCase, lowered.dispersion_factor_expr, 'i*c0*(w^2)');
verifyEqual(testCase, lowered.constants, beta2, "AbsTol", 0.0);
end

function testTranslateBetaSumConstants(testCase)
beta2 = 0.04;
beta3 = -0.003;
beta4 = 0.0002;
lowered = lower_runtime(struct('dispersion_factor_fn', ...
    @(A, w) 1i * (beta2 .* (w .^ 2) + beta3 .* (w .^ 3) + beta4 .* (w .^ 4))));

verifyEqual(testCase, lowered.dispersion_factor_expr, 'i*(c0*(w^2)+c1*(w^3)+c2*(w^4))');
verifyEqual(testCase, lowered.constants, [beta2, beta3, beta4], "AbsTol", 0.0);
end

function testLinearAndNonlinearConstantsAreConcatenated(testCase)
betaT = -0.018;
gamma = 0.015;
fR = 0.18;
lowered = lower_runtime(struct( ...
    'dispersion_factor_fn', @(A, w) 1i * betaT .* w, ...
    'nonlinear_fn', @(A, I, V) 1i .* A .* (gamma .* (1.0 - fR) .* I + gamma .* fR .* V)));

verifyEqual(testCase, lowered.dispersion_factor_expr, 'i*c0*w');
verifyEqual(testCase, lowered.nonlinear_expr, 'i*A*(c1*(1.0-c2)*I+c1*c2*V)');
verifyEqual(testCase, lowered.constants, [betaT, gamma, fR], "AbsTol", 0.0);
end

function testArgumentsBindByNameThenPosition(testCase)
% Any names bind in context order; a symbol name binds to that symbol even
% out of order, and an argument renamed to a symbol is not renamed again.
lowered = lower_runtime(struct( ...
    'dispersion_factor_fn', @(field, omega) 1i * omega .^ 2 .* 0 + field .* 0, ...
    'nonlinear_fn', @(V, A, I) 1i * A .* (I + V)));
verifyEqual(testCase, lowered.dispersion_factor_expr, 'i*w^2*0+A*0');
verifyEqual(testCase, lowered.nonlinear_expr, 'i*A*(I+V)');

lowered = lower_runtime(struct('linear_factor_fn', @(A, wt, kx, ky) 1i * (wt .^ 2 + kx .^ 2 + ky .^ 2)));
verifyEqual(testCase, lowered.linear_factor_expr, 'i*(wt^2+kx^2+ky^2)');
end

function testNumberLiterals(testCase)
lowered = lower_runtime(struct('dispersion_factor_fn', @(A, w) 0.5i * w - 2.5e-3 + 1j));
verifyEqual(testCase, lowered.dispersion_factor_expr, '(0.5*i)*w-2.5e-3+i');
verifyEmpty(testCase, lowered.constants);
end

function testTranslateUnknownIdentifierRejected(testCase)
beta2 = 0.5;
verifyError(testCase, @() lower_runtime(struct( ...
    'dispersion_factor_fn', @(A, w) 1i * beta2 .* w, ...
    'auto_capture_constants', false)), 'nlolib:invalidOperatorSpec');
end

function testConstantBindingsPinValues(testCase)
lowered = lower_runtime(struct( ...
    'dispersion_factor_fn', @(A, w) 1i * beta2 .* w, ...
    'auto_capture_constants', false, ...
    'constant_bindings', struct('beta2', 0.25)));
verifyEqual(testCase, lowered.dispersion_factor_expr, 'i*c0*w');
verifyEqual(testCase, lowered.constants, 0.25, "AbsTol", 0.0);
end

function testTranslateComplexCaptureRejected(testCase)
badGain = 1.0 + 2.0i;
verifyError(testCase, @() lower_runtime(struct( ...
    'dispersion_factor_fn', @(A, w) badGain .* w)), 'nlolib:invalidOperatorSpec');
end

function testStringOperatorsRejected(testCase)
% The string-expression API has been removed from every entry point.
removedFields = {'dispersion_factor_expr', 'dispersion_expr', 'linear_factor_expr', ...
                 'linear_expr', 'potential_expr', 'nonlinear_expr'};
for idx = 1:numel(removedFields)
    verifyError(testCase, ...
        @() lower_runtime(struct(removedFields{idx}, "i*c0*w*w", 'constants', 0.5)), ...
        'nlolib:stringOperatorRemoved');
end
verifyError(testCase, @() lower_runtime(struct('nonlinear_fn', "i*A*I")), ...
            'nlolib:stringOperatorRemoved');
verifyError(testCase, @() lower_runtime(struct('nonlinear_fn', 'i*A*I')), ...
            'nlolib:stringOperatorRemoved');

api = testCase.TestData.api;
pulse = struct('samples', complex(sech(linspace(-4, 4, 32))), 'delta_time', 0.02);
options = struct('propagation_distance', 0.01, ...
                 'exec_options', struct('backend_type', nlolib.constants.VECTOR_BACKEND_CPU));
kerr = @(A, I) 1i * A .* I;
gvd = @(A, w) -0.5i * w .^ 2;
verifyError(testCase, @() api.propagate(pulse, "gvd", kerr, options), ...
            'nlolib:stringOperatorRemoved');
verifyError(testCase, @() api.propagate(pulse, gvd, 'i*A*I', options), ...
            'nlolib:stringOperatorRemoved');
verifyError(testCase, @() api.propagate(pulse, struct('expr', "i*w"), kerr, options), ...
            'nlolib:invalidOperatorSpec');
verifyError(testCase, @() api.propagate(pulse, struct('fn', gvd), kerr, options), ...
            'nlolib:invalidOperatorSpec');
verifyError(testCase, @() api.propagate(pulse, options), ...
            'nlolib:invalidPropagateCall');
end

function testBetaSumPropagationParity(testCase)
% A captured-constant handle and the same operator with pinned bindings and
% different argument names must lower to the same propagation.
api = testCase.TestData.api;
execOpts = struct('backend_type', int32(0));

n = 192;
dt = 0.02;
beta2 = 0.04;
beta3 = -0.003;
beta4 = 0.0002;
omega = omega_grid_unshifted(n, dt);
inputField = deterministic_complex_field(n);

common = base_runtime_config(n, dt, 0.08, omega);

cfgCaptured = common;
cfgCaptured.runtime = struct( ...
    'dispersion_factor_fn', @(A, w) 1i * (beta2 * (w ^ 2) + beta3 * (w ^ 3) + beta4 * (w ^ 4)));

cfgBound = common;
cfgBound.runtime = struct( ...
    'dispersion_factor_fn', @(field, omega) 1i * (b2 * omega .^ 2 + b3 * omega .^ 3 + b4 * omega .^ 4), ...
    'auto_capture_constants', false, ...
    'constant_bindings', struct('b2', beta2, 'b3', beta3, 'b4', beta4));

resCaptured = api.propagate(cfgCaptured, inputField, uint64(2), execOpts);
resBound = api.propagate(cfgBound, inputField, uint64(2), execOpts);
verifyGreaterThan(testCase, max_abs_diff(resCaptured.records(2, :), inputField), 1e-6);
err = max_abs_diff(resCaptured.records(2, :), resBound.records(2, :));
verifyLessThanOrEqual(testCase, err, 5e-7);
end

function testDiffractionPropagationParity(testCase)
% linear_factor_fn/linear_fn and dispersion_factor_fn/dispersion_fn are the
% two names of the tensor linear operator.
api = testCase.TestData.api;
execOpts = struct('backend_type', int32(0));

nt = 1;
nx = 6;
ny = 4;
n = nt * nx * ny;
betaT = -0.018;
inputField = deterministic_complex_field(n);

cfgCommon = coupled_runtime_config(nt, nx, ny);
cfgCommon.potential_grid = complex(zeros(1, n), zeros(1, n));

cfgLinear = cfgCommon;
cfgLinear.runtime = struct( ...
    'linear_factor_fn', @(A, wt, kx, ky) 1i * betaT * (kx .* kx + ky .* ky), ...
    'linear_fn', @(A, D, h) exp(h .* D), ...
    'nonlinear_fn', @(A) 0);

cfgDispersion = cfgCommon;
cfgDispersion.runtime = struct( ...
    'dispersion_factor_fn', @(A, w, wt, kx, ky) 1i * betaT * (kx .* kx + ky .* ky), ...
    'dispersion_fn', @(A, D, h) exp(h .* D), ...
    'nonlinear_fn', @(A) 0);

resLinear = api.propagate(cfgLinear, inputField, uint64(2), execOpts);
resDispersion = api.propagate(cfgDispersion, inputField, uint64(2), execOpts);
verifyGreaterThan(testCase, max_abs_diff(resLinear.records(2, :), inputField), 1e-8);
err = max_abs_diff(resLinear.records(2, :), resDispersion.records(2, :));
verifyLessThanOrEqual(testCase, err, 1e-7);
end

function testRamanLikePropagationParity(testCase)
% Argument order must not matter when the names are runtime symbols.
api = testCase.TestData.api;
execOpts = struct('backend_type', int32(0));

nt = 4;
nx = 4;
ny = 4;
n = nt * nx * ny;
gamma = 0.015;
fR = 0.18;
potentialXY = complex(0.02 * double(1:(nx * ny)), zeros(1, nx * ny));
potential = repmat(potentialXY, 1, nt);
inputField = deterministic_complex_field(n);

cfgCommon = coupled_runtime_config(nt, nx, ny);
cfgCommon.potential_grid = potential;
cfgCommon.propagation_distance = 0.008;
cfgCommon.runtime = struct( ...
    'linear_factor_fn', @(A) 0, ...
    'linear_fn', @(A, D, h) exp(h .* D));

cfgOrdered = cfgCommon;
cfgOrdered.runtime.nonlinear_fn = ...
    @(A, I, V) 1i .* A .* (gamma .* (1.0 - fR) .* I + gamma .* fR .* V);

cfgShuffled = cfgCommon;
cfgShuffled.runtime.nonlinear_fn = ...
    @(V, I, A) 1i .* A .* (gamma .* (1.0 - fR) .* I + gamma .* fR .* V);

resOrdered = api.propagate(cfgOrdered, inputField, uint64(2), execOpts);
resShuffled = api.propagate(cfgShuffled, inputField, uint64(2), execOpts);
verifyGreaterThan(testCase, max_abs_diff(resOrdered.records(2, :), inputField), 1e-8);
err = max_abs_diff(resOrdered.records(2, :), resShuffled.records(2, :));
verifyLessThanOrEqual(testCase, err, 1e-7);
end

function lowered = lower_runtime(runtime)
% Lower cfg.runtime through the public prepare_sim_config and read back the
% expression strings and constants the C API would receive.
n = 8;
cfg = base_runtime_config(n, 0.1, 0.1, zeros(1, n));
cfg.runtime = runtime;
[~, physicsCfgPtr, keepalive] = nlolib.prepare_sim_config(cfg); %#ok<ASGLU>
lowered = struct();
names = {'linear_factor_expr', 'linear_expr', 'potential_expr', ...
         'dispersion_factor_expr', 'dispersion_expr', 'nonlinear_expr'};
for idx = 1:numel(names)
    value = physicsCfgPtr.(names{idx});
    if isempty(value)
        value = '';
    end
    lowered.(names{idx}) = char(value);
end
lowered.constants = physicsCfgPtr.constants(1:double(physicsCfgPtr.num_constants));
end

function cfg = base_runtime_config(n, dt, zFinal, omega)
cfg = struct();
cfg.num_time_samples = uint64(n);
cfg.propagation_distance = zFinal;
cfg.starting_step_size = 1e-3;
cfg.max_step_size = 5e-3;
cfg.min_step_size = 1e-5;
cfg.error_tolerance = 1e-7;
cfg.pulse_period = n * dt;
cfg.delta_time = dt;
cfg.frequency_grid = complex(omega, zeros(1, n));
end

function cfg = coupled_runtime_config(nt, nx, ny)
cfg = struct();
cfg.num_time_samples = uint64(nt * nx * ny);
cfg.propagation_distance = 0.01;
cfg.starting_step_size = 1e-3;
cfg.max_step_size = 2e-3;
cfg.min_step_size = 1e-5;
cfg.error_tolerance = 1e-7;
cfg.pulse_period = nt * 0.02;
cfg.delta_time = 0.02;
cfg.tensor_nt = uint64(nt);
cfg.tensor_nx = uint64(nx);
cfg.tensor_ny = uint64(ny);
cfg.tensor_layout = int32(0);
cfg.frequency_grid = complex(zeros(1, nt), zeros(1, nt));
end

function out = omega_grid_unshifted(n, dt)
twoPi = 2.0 * pi;
out = zeros(1, n);
for idx = 1:n
    i = idx - 1;
    if i <= floor((n - 1) / 2)
        out(idx) = twoPi * (double(i) / (double(n) * dt));
    else
        out(idx) = twoPi * (-(double(n - i) / (double(n) * dt)));
    end
end
end

function field = deterministic_complex_field(n)
idx = double(0:(n - 1));
re = 0.12 * sin(0.13 * idx) + 0.07 * cos(0.23 * idx);
im = 0.11 * sin(0.19 * idx) - 0.05 * cos(0.31 * idx);
field = complex(re, im);
end

function err = max_abs_diff(a, b)
err = max(abs(a(:) - b(:)));
end
