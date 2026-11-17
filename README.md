# nlolib for MATLAB

MATLAB toolbox for the nlolib nonlinear-optics runtime: a split-step (RK4IP)
propagator for pulses and beams in nonlinear media, with a CPU backend and an
optional Vulkan GPU backend. It supports temporal, transverse (x-y) and coupled
3+1D propagation, with operators given as MATLAB function handles.

## Install

Install **nlolib** from the Add-On Explorer, or download `nlolib.mltbx` from
the [latest release](https://github.com/kinsky-main/nlolib-matlab/releases/latest)
and double-click it, or:

```matlab
matlab.addons.install('nlolib.mltbx');
```

Requires MATLAB R2023b or later on Windows or Linux (x86-64), and nothing else:
no C compiler, no Visual C++ redistributable, no Vulkan runtime. The toolbox
ships the native library and a prebuilt `loadlibrary` prototype for both
platforms.

## Quick start

A run needs a pulse, a linear and a nonlinear operator, and a propagation
distance. Operators are function handles; the scalars they use (`beta2`,
`gamma` below) are captured when the run starts. This propagates a
fundamental soliton, which keeps its shape:

```matlab
n  = 1024;
dt = 0.01;
t  = ((0:(n - 1)) - n / 2) * dt;

beta2 = -0.01;                          % anomalous dispersion
gamma = 0.04;                           % Kerr coefficient
t0    = 0.1;                            % sech width; N = 1 needs P0 = |beta2| / (gamma * t0^2)
pulse = struct('samples',    complex(sqrt(abs(beta2) / (gamma * t0^2)) * sech(t / t0)), ...
               'delta_time', dt);

linearOp    = @(A, w) 1i * (beta2 / 2) * w.^2;     % D(w), applied as exp(h*D)
nonlinearOp = @(A, I) 1i * gamma * A .* I;          % N(A), I = |A|^2

options = struct('propagation_distance', 1.0, 'records', 64);

api    = nlolib.NLolib();
result = api.propagate(pulse, linearOp, nonlinearOp, options);

fprintf('peak power in %.3f, out %.3f\n', max(abs(pulse.samples).^2), max(abs(result.final).^2));
imagesc(t, result.z_axis, abs(result.records).^2);
xlabel('t'); ylabel('z');
```

`result.records` holds one row per recorded `z` (`result.z_axis`), and
`result.final` is the field at `propagation_distance`.

With the toolbox installed nothing else is needed. From a source checkout, put
the package on the path and point it at the built library first:

```matlab
addpath('path/to/nlolib-matlab');
nlolib_setup();
setenv('NLOLIB_LIBRARY', 'path/to/libnlolib.so');   % nlolib.dll on Windows
```

## Operators

Each operator is a function handle whose body is a single expression in the
runtime symbols. An argument named after a symbol binds to it; other names bind
in the order shown.

| Operator | Signature | Symbols |
|---|---|---|
| linear | `@(A, w, wt, kx, ky, x, y, t)` | `w` angular frequency; `wt`, `kx`, `ky` tensor-run frequency axes; `x`, `y`, `t` coordinates |
| nonlinear | `@(A, I, V)` | `A` field, `I = abs(A).^2`, `V` the `potential_grid` |

For a coupled `(t, x, y)` run, for example:
`linearOp = @(A, wt, kx, ky) 1i * (b2 * wt.^2 + bt * (kx.^2 + ky.^2))`.
Other identifiers must be real scalars in the handle's workspace. Strings are
not accepted and raise `nlolib:stringOperatorRemoved`.

## Examples

The toolbox installs its examples; `nlolib_setup()` adds them to the path.
These three are self-contained and run as they stand:

- `standalone_transverse_grin_beam` — transverse x-y propagation with a GRIN
  potential grid.
- `standalone_spatiotemporal_kerr_bullet` — coupled 3+1D Kerr propagation
  validated against Gaussian beam and pulse laws.
- `grin_fiber_soliton_fission` — higher-order soliton fission in the
  fundamental mode of a GRIN fibre.

Further examples cover function-handle operators, soliton and linear-drift
validation, and coupled dispersion, nonlinearity and diffraction.

## CPU and GPU

The CPU backend always works. The Vulkan backend is used when a Vulkan driver
is present. On Vulkan each operator program is compiled to a single GPU kernel
at runtime and falls back to an interpreter silently when it cannot be; two
counters say which happened:

```matlab
api.perf_profile_reset();
result = api.propagate(pulse, linearOp, nonlinearOp, options);

snapshot = api.perf_profile_read();
fprintf('%d JIT programs, %d interpreter fallbacks\n', ...
        snapshot.operator_jit_programs, snapshot.operator_jit_fallbacks);
```

## What is in the toolbox

| Symbol | Purpose |
|---|---|
| `nlolib.NLolib` | wrapper class: `propagate`, `query_runtime_limits`, logging, progress, performance counters, storage |
| `nlolib.constants` | C API enum values and limits by name |
| `nlolib.tensor_record_view` | coupled record row → `(nt, ny, nx)` volume |
| `nlolib_setup` | add the package, examples and library folders to the MATLAB path |

## Documentation

- [User guide](docs/user_guide.md) — pulse and operator specifications,
  options, telemetry, coupled 2D/3D runs, logging, storage, troubleshooting.
  Also installed with the toolbox, under `docs/`.
- [Full documentation and API reference](https://kinsky-main.github.io/nlo-rk4ip-code/)
- [Binding internals, tests and packaging](docs/binding_guide.md) and
  [working on the toolbox itself](docs/development.md)

## Links

- Source and issues: https://github.com/kinsky-main/nlolib-matlab
- Core C library: https://github.com/kinsky-main/nlo-rk4ip-code

## License

GPL-2.0-or-later.
