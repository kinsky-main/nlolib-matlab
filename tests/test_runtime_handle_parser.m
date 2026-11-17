function tests = test_runtime_handle_parser()
%TEST_RUNTIME_HANDLE_PARSER Operator function handles: lowering and parity.
%
%   Operators are function handles only. They are lowered to the C runtime
%   expressions by the private translate_runtime_handle, which these tests
%   call through a handle taken inside +nlolib/private. The lowering and the
%   argument checks need no shared library; the propagation parity tests are
%   skipped when none is available (set NLOLIB_LIBRARY to select one).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
bindingRoot = fileparts(fileparts(mfilename('fullpath')));
previous = cd(fullfile(bindingRoot, '+nlolib', 'private'));
restore = onCleanup(@() cd(previous));
testCase.TestData.lower = @translate_runtime_handle;
end

% --- lowering --------------------------------------------------------------

function testTranslateElementwiseAndImaginaryUnit(testCase)
beta2 = 0.5;
[expr, constants] = lower(testCase, @(A, w) 1i * beta2 .* (w .^ 2), 'dispersion_factor');
verifyEqual(testCase, expr, 'i*c0*(w^2)');
verifyEqual(testCase, constants, beta2, "AbsTol", 0.0);
end

function testTranslateBetaSumConstants(testCase)
beta2 = 0.04;
beta3 = -0.003;
beta4 = 0.0002;
[expr, constants] = lower(testCase, ...
    @(A, w) 1i * (beta2 .* (w .^ 2) + beta3 .* (w .^ 3) + beta4 .* (w .^ 4)), 'dispersion_factor');
verifyEqual(testCase, expr, 'i*(c0*(w^2)+c1*(w^3)+c2*(w^4))');
verifyEqual(testCase, constants, [beta2, beta3, beta4], "AbsTol", 0.0);
end

function testArgumentsBindByNameThenPosition(testCase)
% Any names bind in parameter order; a symbol name binds to that symbol even
% out of order, and an argument renamed to a symbol is not renamed again.
verifyEqual(testCase, lower(testCase, @(field, omega) 1i * omega .^ 2 .* 0 + field .* 0, ...
                            'dispersion_factor'), 'i*w^2*0+A*0');
verifyEqual(testCase, lower(testCase, @(V, A, I) 1i * A .* (I + V), 'nonlinear'), 'i*A*(I+V)');
verifyEqual(testCase, lower(testCase, @(A, wt, kx, ky) 1i * (wt .^ 2 + kx .^ 2 + ky .^ 2), ...
                            'linear_factor'), 'i*(wt^2+kx^2+ky^2)');
verifyEqual(testCase, lower(testCase, @(A, D, h) exp(h .* D), 'dispersion'), 'exp(h*D)');
verifyEqual(testCase, lower(testCase, @(x, y) x .^ 2 + y .^ 2, 'potential'), 'x^2+y^2');
% Named arguments bind first, wherever they are; the rest fill in order.
verifyEqual(testCase, lower(testCase, @(B, A) A + B, 'dispersion_factor'), 'A+w');
end

function testTwoArgumentsForOneSymbolRejected(testCase)
% In a tensor run w is wt, so the old @(A, w, wt, kx, ky) signature would bind
% wt twice; shifting it would silently rename kx to ky and ky to x.
verifyError(testCase, @() lower(testCase, @(A, w, wt, kx, ky) kx + ky, 'linear_factor'), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() lower(testCase, @(A, w, wt) w, 'dispersion_factor'), ...
            'nlolib:invalidOperator');
end

function testWAndWtAreAliasesInLinearContexts(testCase)
% One linear operator written as @(A, w) works for both run types.
verifyEqual(testCase, lower(testCase, @(A, w) 1i * w .^ 2, 'linear_factor'), 'i*wt^2');
verifyEqual(testCase, lower(testCase, @(A, wt) 1i * wt .^ 2, 'dispersion_factor'), 'i*w^2');
verifyEqual(testCase, lower(testCase, @(A, D, h, w) exp(h .* D) + w, 'linear'), 'exp(h*D)+wt');
verifyEqual(testCase, lower(testCase, @(A, kx, w) kx + w, 'linear_factor'), 'kx+wt');
end

function testSymbolsOutsideTheContextAreRejected(testCase)
% The C parser rejects these; the binding reports them before the C call.
verifyError(testCase, @() lower(testCase, @(A, w) 1i * w .^ 2 + kx, 'dispersion_factor'), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() lower(testCase, @(A, w) w + t, 'dispersion'), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() lower(testCase, @(x, y) x + wt, 'potential'), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() lower(testCase, @(A, I) A .* I + t, 'nonlinear'), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() lower(testCase, @(A, w, a, b) w, 'dispersion_factor'), ...
            'nlolib:invalidOperator');
end

function testNumberLiterals(testCase)
[expr, constants] = lower(testCase, @(A, w) 0.5i * w - 2.5e-3 + 1j, 'dispersion_factor');
verifyEqual(testCase, expr, '(0.5*i)*w-2.5e-3+i');
verifyEmpty(testCase, constants);
end

function testUnknownIdentifierRejected(testCase)
verifyError(testCase, @() lower(testCase, @(A, w) 1i * notDefinedAnywhere .* w, ...
                                'dispersion_factor'), 'nlolib:invalidOperator');
end

function testConstantBindingsWinOverCapture(testCase)
beta2 = 0.5;
[expr, constants] = lower(testCase, @(A, w) 1i * beta2 .* w, 'dispersion_factor', ...
                          struct('beta2', 0.25));
verifyEqual(testCase, expr, 'i*c0*w');
verifyEqual(testCase, constants, 0.25, "AbsTol", 0.0);
[~, constants] = lower(testCase, @(A, w) 1i * b2 .* w, 'dispersion_factor', ...
                       containers.Map({'b2'}, {0.75}));
verifyEqual(testCase, constants, 0.75, "AbsTol", 0.0);
end

function testComplexCaptureRejected(testCase)
badGain = 1.0 + 2.0i;
verifyError(testCase, @() lower(testCase, @(A, w) badGain .* w, 'dispersion_factor'), ...
            'nlolib:invalidOperator');
end

% --- what propagate accepts -------------------------------------------------

function testNonHandleOperatorsRejected(testCase)
% Strings, presets and struct specs are not operators. These fail before the
% library is needed.
pulse = small_pulse();
kerr = @(A, I) 1i * A .* I;
gvd = @(A, w) -0.5i * w .^ 2;
verifyError(testCase, @() lower(testCase, "i*w", 'dispersion_factor'), 'nlolib:invalidOperator');
verifyError(testCase, @() nlolib.propagate(pulse, "gvd", kerr, propagation_distance=0.01), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, 'i*A*I', propagation_distance=0.01), ...
            'nlolib:invalidOperator');
verifyError(testCase, @() nlolib.propagate(pulse, struct('expr', "i*w"), kerr, ...
                                           propagation_distance=0.01), 'nlolib:invalidOperator');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=0.01, ...
                                           linear_step_operator="exp(h*D)"), ...
            'nlolib:invalidOperator');
end

function testOptionsAreChecked(testCase)
pulse = small_pulse();
kerr = @(A, I) 1i * A .* I;
gvd = @(A, w) -0.5i * w .^ 2;
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=-1), ...
            'nlolib:invalidOption');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, ...
                                           preset="slow"), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, ...
                                           record_z=[0, 0.5], num_records=3), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, ...
                                           record_z=[0.5, 0.25]), 'nlolib:invalidOption');
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, ...
                                           nonlinear_model=1), 'nlolib:invalidOption');
% potential_operator is compiled only for tensor runs.
verifyError(testCase, @() nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, ...
                                           potential_operator=@(x, y) x), 'nlolib:invalidOption');
% An unknown option name is MATLAB's own name=value error.
try
    nlolib.propagate(pulse, gvd, kerr, propagation_distance=1, records=4);
    verifyFail(testCase, 'an unknown option name was accepted');
catch ME
    verifyFalse(testCase, startsWith(ME.identifier, 'nlolib:'), ME.identifier);
end
end

function testPulseIsChecked(testCase)
kerr = @(A, I) 1i * A .* I;
gvd = @(A, w) -0.5i * w .^ 2;
pulse = small_pulse();
verifyError(testCase, @() nlolib.propagate(rmfield(pulse, 'delta_time'), gvd, kerr, ...
                                           propagation_distance=1), 'nlolib:invalidPulse');
withLayout = pulse;
withLayout.tensor_layout = 0;
verifyError(testCase, @() nlolib.propagate(withLayout, gvd, kerr, propagation_distance=1), ...
            'nlolib:invalidPulse');
tensor = struct('samples', zeros(1, 12), 'delta_time', 0.1, ...
                'tensor_nt', 2, 'tensor_nx', 2, 'tensor_ny', 2);
verifyError(testCase, @() nlolib.propagate(tensor, gvd, kerr, propagation_distance=1), ...
            'nlolib:invalidPulse');
partial = struct('samples', zeros(1, 8), 'delta_time', 0.1, 'tensor_nt', 8);
verifyError(testCase, @() nlolib.propagate(partial, gvd, kerr, propagation_distance=1), ...
            'nlolib:invalidPulse');
end

% --- propagation parity (needs the library) --------------------------------

function testBetaSumPropagationParity(testCase)
% A captured-constant handle and the same operator with bound constants and
% different argument names must give the same propagation.
require_library(testCase);
n = 192;
dt = 0.02;
beta2 = 0.04;
beta3 = -0.003;
beta4 = 0.0002;
pulse = struct('samples', deterministic_complex_field(n), 'delta_time', dt);
common = {'propagation_distance', 0.08, 'num_records', 2, ...
          'exec_options', struct('backend_type', "cpu")};

resCaptured = nlolib.propagate(pulse, ...
    @(A, w) 1i * (beta2 * (w ^ 2) + beta3 * (w ^ 3) + beta4 * (w ^ 4)), ...
    @(A, I) 0 * A, common{:});
resBound = nlolib.propagate(pulse, ...
    @(field, omega) 1i * (b2 * omega .^ 2 + b3 * omega .^ 3 + b4 * omega .^ 4), ...
    @(A, I) 0 * A, common{:}, ...
    constant_bindings=struct('b2', beta2, 'b3', beta3, 'b4', beta4));
verifyGreaterThan(testCase, max_abs_diff(resCaptured.final, pulse.samples), 1e-6);
verifyLessThanOrEqual(testCase, max_abs_diff(resCaptured.final, resBound.final), 5e-7);
end

function testTensorLinearOperatorParity(testCase)
% A tensor run lowers linear_operator in the linear_factor context, where w
% is an alias of wt; an explicit linear_step_operator exp(h*D) is the default.
require_library(testCase);
nt = 4;
nx = 6;
ny = 4;
betaT = -0.018;
pulse = struct('samples', deterministic_complex_field(nt * nx * ny), 'delta_time', 0.02, ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny);
common = {'propagation_distance', 0.01, 'num_records', 2, ...
          'exec_options', struct('backend_type', "cpu")};

resWt = nlolib.propagate(pulse, @(A, wt, kx, ky) 1i * (0.01 * wt .^ 2 + betaT * (kx .^ 2 + ky .^ 2)), ...
                         @(A) 0 * A, common{:});
resW = nlolib.propagate(pulse, @(A, w, kx, ky) 1i * (0.01 * w .^ 2 + betaT * (kx .^ 2 + ky .^ 2)), ...
                        @(A) 0 * A, common{:}, linear_step_operator=@(A, D, h) exp(h .* D));
verifyGreaterThan(testCase, max_abs_diff(resWt.final, pulse.samples), 1e-8);
verifyLessThanOrEqual(testCase, max_abs_diff(resWt.final, resW.final), 1e-7);
verifyTrue(testCase, resWt.meta.coupled);
end

function testNonlinearArgumentOrderParity(testCase)
% Argument order must not matter when the names are runtime symbols.
require_library(testCase);
nt = 4;
nx = 4;
ny = 4;
gamma = 0.015;
fR = 0.18;
pulse = struct('samples', deterministic_complex_field(nt * nx * ny), 'delta_time', 0.02, ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, ...
               'potential_grid', complex(0.02 * double(1:(nx * ny)), zeros(1, nx * ny)));
common = {'propagation_distance', 0.008, 'num_records', 2, ...
          'exec_options', struct('backend_type', "cpu")};

resOrdered = nlolib.propagate(pulse, @(A) 0 * A, ...
    @(A, I, V) 1i .* A .* (gamma .* (1.0 - fR) .* I + gamma .* fR .* V), common{:});
resShuffled = nlolib.propagate(pulse, @(A) 0 * A, ...
    @(V, I, A) 1i .* A .* (gamma .* (1.0 - fR) .* I + gamma .* fR .* V), common{:});
verifyGreaterThan(testCase, max_abs_diff(resOrdered.final, pulse.samples), 1e-8);
verifyLessThanOrEqual(testCase, max_abs_diff(resOrdered.final, resShuffled.final), 1e-7);
end

function testPotentialOperatorMatchesPotentialGrid(testCase)
% potential_operator is the tensor-run alternative to pulse.potential_grid.
require_library(testCase);
nt = 2;
nx = 8;
ny = 8;
dx = 0.5;
x = ((0:(nx - 1)) - (nx - 1) / 2) * dx;   % the core's centred axes
y = ((0:(ny - 1)) - (ny - 1) / 2) * dx;
[X, Y] = meshgrid(x, y);           % rows y, columns x
grid = X .^ 2 + Y .^ 2;            % x-major, y fastest: grid(:) runs y first
pulse = struct('samples', deterministic_complex_field(nt * nx * ny), 'delta_time', 0.02, ...
               'tensor_nt', nt, 'tensor_nx', nx, 'tensor_ny', ny, 'delta_x', dx, 'delta_y', dx);
common = {'propagation_distance', 0.01, 'num_records', 2, ...
          'exec_options', struct('backend_type', "cpu")};
nonlinear = @(A, I, V) 1i * 0.3 * A .* V;

withGrid = pulse;
withGrid.potential_grid = complex(grid(:).');
resGrid = nlolib.propagate(withGrid, @(A) 0 * A, nonlinear, common{:});
resOperator = nlolib.propagate(pulse, @(A) 0 * A, nonlinear, common{:}, ...
                               potential_operator=@(x, y) x .^ 2 + y .^ 2);
verifyGreaterThan(testCase, max_abs_diff(resGrid.final, pulse.samples), 1e-8);
verifyLessThanOrEqual(testCase, max_abs_diff(resGrid.final, resOperator.final), 1e-7);
verifyError(testCase, @() nlolib.propagate(withGrid, @(A) 0 * A, nonlinear, common{:}, ...
                                           potential_operator=@(x, y) x), 'nlolib:invalidOption');
end

% --- helpers ---------------------------------------------------------------

function [expr, constants] = lower(testCase, fn, context, bindings)
if nargin < 4
    bindings = [];
end
[expr, constants] = testCase.TestData.lower(fn, context, bindings);
end

function require_library(testCase)
try
    nlolib.load();
catch ME
    assumeFail(testCase, sprintf('nlolib library unavailable: %s', ME.message));
end
end

function pulse = small_pulse()
pulse = struct('samples', complex(sech(linspace(-4, 4, 32))), 'delta_time', 0.02);
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
