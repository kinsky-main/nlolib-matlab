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

Upgrading from 1.x? 2.0.0 replaces the API; the user guide's
[Upgrading from 1.x](docs/user_guide.md#upgrading) section lists every change.

## Quick start

A run is one call: a pulse, a linear and a nonlinear operator, and options by
name, of which `propagation_distance` is required. Operators are function
handles; the scalars they use (`beta2`, `gamma` below) are captured when the
run starts. This propagates a fundamental soliton, which keeps its shape:

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

result = nlolib.propagate(pulse, linearOp, nonlinearOp, ...
                          propagation_distance=1.0, num_records=64);

fprintf('peak power in %.3f, out %.3f\n', max(abs(pulse.samples).^2), max(abs(result.final).^2));
imagesc(t, result.z_axis, abs(result.records).^2);
xlabel('t'); ylabel('z');
```

`result.records` holds one row per recorded `z` (`result.z_axis`), and
`result.final` is the last returned record: the field at `propagation_distance`
unless a `record_z` ends earlier. `result.meta` says what
ran (`preset`, `records_requested`, `records_written`, `backend_requested`,
`coupled`, `status`). The library is loaded on first use; `nlolib.load(path)`
picks a specific one.

With the toolbox installed nothing else is needed. From a source checkout, put
the package on the path and point it at the built library first:

```matlab
addpath('path/to/nlolib-matlab');
nlolib_setup();
setenv('NLOLIB_LIBRARY', 'path/to/libnlolib.so');   % nlolib.dll on Windows
```

## Operators

Each operator is a function handle whose body is a single expression in the
runtime symbols. An argument named after a symbol binds to it; other names take
the remaining symbols in the order shown. A run is a tensor run when the pulse
sets `tensor_nt`, `tensor_nx` and `tensor_ny`.

| Operator | Temporal run | Tensor run |
|---|---|---|
| `linear_operator` (positional) | `@(A, w)` | `@(A, wt, kx, ky, x, y, t)` |
| `nonlinear_operator` (positional) | `@(A, I, V)` | `@(A, I, V)` |
| `linear_step_operator` (option) | `@(A, D, h, w, V)` | `@(A, D, h, wt, kx, ky, x, y, t, V)` |
| `potential_operator` (option) | not allowed | `@(x, y, t)` |

`w` and `wt` name the same frequency axis, so `@(A, w)` works in both run
types. `A` is the field, `I = abs(A).^2`, `V` the `potential_grid`, and `D`,
`h` the linear factor and step in the per-step operator (default
`exp(h*D)`). For a coupled `(t, x, y)` run, for example:
`linearOp = @(A, wt, kx, ky) 1i * (b2 * wt.^2 + bt * (kx.^2 + ky.^2))`.
Other identifiers must be real scalars in the handle's workspace, or be named in
`constant_bindings=struct('beta2', -0.01)`, which wins over the workspace.
Anything but a function handle raises `nlolib:invalidOperator`.

## Examples

The toolbox installs its examples; `nlolib_setup()` adds them to the path.
They are the twelve examples shared with the Python and Julia packages: the
same problem, the same parameters and the same printed metrics in each. Run
one by name, for example `quickstart` or `transverse_grin_beam`; plots go to
`examples/output/<name>/`. The full list is in the
[user guide](docs/user_guide.md#examples).

## CPU and GPU

The CPU backend always works. The Vulkan backend is used when a Vulkan driver
is present. On Vulkan each operator program is compiled to a single GPU kernel
at runtime and falls back to an interpreter silently when it cannot be; two
counters say which happened:

```matlab
nlolib.perf_profile_reset();
result = nlolib.propagate(pulse, linearOp, nonlinearOp, propagation_distance=1.0, ...
                          exec_options=struct('backend_type', "vulkan"));

snapshot = nlolib.perf_profile_read();
fprintf('%d JIT programs, %d interpreter fallbacks\n', ...
        snapshot.operator_jit_programs, snapshot.operator_jit_fallbacks);
```

## What is in the toolbox

| Function | Purpose |
|---|---|
| `nlolib.propagate` | run a propagation; options by name |
| `nlolib.query_runtime_limits` | memory and record limits for a pulse, without a run |
| `nlolib.tensor_record_view` | one tensor-run record → `(nt, ny, nx)` volume |
| `nlolib.load`, `nlolib.unload`, `nlolib.loaded_library_path` | pick, release and report the shared library |
| `nlolib.storage_is_available` | whether SQLite storage is built in |
| `nlolib.set_log_level`, `set_log_file`, `set_log_buffer`, `clear_log_buffer`, `read_log_buffer` | runtime logging |
| `nlolib.set_progress_options`, `set_progress_stream` | progress bar |
| `nlolib.perf_profile_set_enabled`, `perf_profile_is_enabled`, `perf_profile_reset`, `perf_profile_read` | performance counters |
| `nlolib_setup` | add the package, examples and library folders to the MATLAB path |

Every option that names a mode takes a lowercase string: `backend_type`
`"cpu"`, `"vulkan"` or `"auto"`; `preset` `"fast"`, `"balanced"` or
`"accuracy"`; log level `"error"` to `"debug"`. Errors carry one of seven
identifiers: `nlolib:invalidOperator`, `nlolib:invalidPulse`,
`nlolib:invalidOption`, `nlolib:libraryLoadFailed`, `nlolib:unavailable`,
`nlolib:statusFailed` and `nlolib:propagationAborted`.

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
