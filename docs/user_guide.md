# MATLAB User Guide

This guide is a task-oriented walkthrough of the MATLAB binding: how to install
it, how to describe a problem, how to run it, and how to read the result. The
symbol-level reference lives in @ref matlab_binding; the mathematics of the
runtime operators is in [Runtime Operator Mathematics](../../docs/runtime_operators.md).

Everything below is the `nlolib` package: plain functions over the native
shared library, called through `loadlibrary`/`calllib`. There is no client
object and no Python dependency. The same functions, option names and string
values exist in the Python and Julia packages.

- [Install and Verify](#install)
- [Quick Start](#quickstart)
- [Describing the Pulse](#pulse)
- [Describing the Operators](#operators)
- [Propagation Options](#options)
- [Reading the Result](#result)
- [Coupled 2D and 3D Runs](#tensor)
- [Solver Telemetry and Step History](#telemetry)
- [Logging, Progress, and Perf Counters](#logging)
- [Sizing a Run with query_runtime_limits](#limits)
- [SQLite Storage](#storage)
- [Troubleshooting](#troubleshooting)
- [Example Scripts](#examples)

<a name="install"></a>

## Install and Verify

### Prerequisites

- MATLAB R2023b or later, on 64-bit Windows or 64-bit Linux.
- No C compiler, and no Visual C++ redistributable. The packaged toolbox ships
  a prebuilt `loadlibrary` prototype (`nlolib_proto.m` plus its thunk), so the
  header is never parsed on your machine, and the library links the MSVC
  runtime statically.
- For the Vulkan backend, a GPU driver shipping the Vulkan loader (standard
  NVIDIA / AMD / Intel desktop drivers include it). The CPU backend needs
  nothing extra — the library loads and runs with no Vulkan runtime installed.

Working from a build tree rather than a packaged toolbox is the one case that
still needs a compiler: with no prototype staged, `loadlibrary` falls back to
parsing `nlolib_matlab.h`. Run `matlab/generate_library_prototype.m` once to
remove that fallback, or check `mex -setup C` if the load fails complaining
about the header. Run `matlab/build_progress_mex.m` once as well to get the
live progress bar in a build tree.

### Option A — toolbox install (recommended)

Fetch and install the newest release in one step:

```matlab
f = websave([tempname '.mltbx'], 'https://github.com/kinsky-main/nlo-rk4ip-code/releases/latest/download/nlolib.mltbx');
matlab.addons.toolbox.installToolbox(f);
```

That URL always resolves to the current release. To pin a version, replace
`latest/download` with `download/1.13.0`.

Otherwise download `nlolib.mltbx` from the GitHub release page and
double-click it in MATLAB, use **Home -> Add-Ons -> Install from File**, or:

```matlab
matlab.addons.toolbox.installToolbox('nlolib.mltbx');
```

One bundle covers every supported platform: it carries `lib/win64` and
`lib/glnxa64` side by side, each holding its own shared library, `loadlibrary`
prototype and thunk, plus a `progress_mex` per platform. MATLAB loads the
folder matching `computer('arch')`. The bundle also ships `nlolib_matlab.h`,
the example scripts, and this guide.

On Linux, do not install from `matlab -batch`: the files are extracted but the
add-on registration does not survive the session, so the next session finds
nothing. Use the desktop, or:

```bash
matlab -nodisplay -r "matlab.addons.toolbox.installToolbox('nlolib.mltbx'); exit"
```

Older bundles carry a different toolbox identifier and are not replaced
automatically: one per platform before 1.13.0 (`nlolib-win64`,
`nlolib-glnxa64`), and the bare name `nlolib` in the first 1.13.0 build.
Remove such an install by hand first:

```matlab
guid = '6a93951c-b83c-45dd-97fd-72881ce03474';
t = matlab.addons.toolbox.installedToolboxes;
for k = 1:numel(t)
    if strcmp(t(k).Name, 'nlolib') && ~strcmp(t(k).Guid, guid)
        matlab.addons.toolbox.uninstallToolbox(t(k));
    end
end
```

Every bundle now shares that fixed GUID, so installing a newer
`nlolib.mltbx` replaces the installed one in place.

Installing puts only the package on the MATLAB path; run `nlolib_setup()` to
add the example folder for the current session.

### Option B — build tree

```powershell
cmake -S . -B build
cmake --build build --config Release --target matlab_stage
```

```matlab
addpath('build/matlab_toolbox');
nlolib_setup();
```

`nlolib_setup` adds the package and example folders to the MATLAB path and, on
Windows, prepends the staged library directories to `PATH` so the loader can
resolve `nlolib.dll`. Pass `nlolib_setup(true)` to persist the path with
`savepath`.

### Library discovery

Every `nlolib` function loads the library on first use, searching in order:

1. the `NLOLIB_LIBRARY` environment variable;
2. staged and build-tree locations relative to the package
   (`lib/`, `build/matlab_toolbox/lib/`, `build/src/<config>/`, `python/`, ...),
   newest file first.

`nlolib.load(path)` loads a specific library instead (and unloads a different
one that is already loaded). `nlolib.loaded_library_path()` says which one is in
use. MATLAB keeps a loaded library until `nlolib.unload()`, which is needed to
rebuild or replace it within one session.

### Verify the install

```matlab
nlolib.load();                          % throws nlolib:libraryLoadFailed if it cannot load
disp(nlolib.loaded_library_path());
disp(nlolib.query_runtime_limits());    % device budget and record limits
disp(nlolib.storage_is_available());    % true when SQLite storage is compiled in
```

<a name="quickstart"></a>

## Quick Start

A chirped Gaussian in a dispersive Kerr medium. A run is one call: the pulse,
the two operators, and options by name. Both operators are function handles;
the scalars they use are captured from the workspace:

```matlab
n  = 512;
dt = 0.02;
t  = ((0:(n - 1)) - 0.5 * (n - 1)) * dt;

pulse = struct('samples',    exp(-(t / 0.25).^2) .* exp(-1i * 8.0 * t), ...
               'delta_time', dt);

beta2 = -0.01;    % GVD  [ps^2/m]
gamma = 0.01;     % Kerr [1/W/m]
alpha = 0.0;      % power loss [1/m]

linearOperator    = @(A, w) 1i * (beta2 / 2) * w.^2 - alpha / 2;
nonlinearOperator = @(A, I, V) 1i * A .* (gamma * I + V);

result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=0.506, num_records=160, preset="balanced");

fprintf('%d records of %d samples\n', size(result.records));
fprintf('power in=%.6e out=%.6e\n', ...
        sum(abs(pulse.samples).^2), sum(abs(result.final).^2));
```

Note the factors of one half: the solver applies \f$D(\omega)\f$ as written, so
the GLSE term \f$i(\beta_2/2)\partial_t^2\f$ is written `(beta2 / 2)`, and a
power-loss coefficient \f$\alpha_{\mathrm{pow}}\f$ enters as `- alpha / 2`. See [Runtime Operator
Mathematics](../../docs/runtime_operators.md).

Options are MATLAB name=value arguments. To keep a set of them in a struct, pass
it with `namedargs2cell`:

```matlab
opts = struct('propagation_distance', 0.506, 'num_records', 160);
args = namedargs2cell(opts);
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, args{:});
```

A misspelled option name is MATLAB's own name=value error, not silently ignored.

<a name="pulse"></a>

## Describing the Pulse

The pulse struct describes the launch field and the grid it lives on. Any other
field is an `nlolib:invalidPulse` error.

| Field | Required | Meaning |
|---|---|---|
| `samples` | yes | complex launch field, flattened to a row vector |
| `delta_time` | yes | temporal sample spacing, > 0 |
| `pulse_period` | no | temporal window; default `nt * delta_time` |
| `frequency_grid` | no | complex angular-frequency axis, one entry per temporal sample; default is the FFT-order grid for `nt` and `delta_time` |
| `tensor_nt`, `tensor_nx`, `tensor_ny` | no | tensor-run shape; all three together |
| `delta_x`, `delta_y` | no | transverse sample spacing; default `1.0` |
| `spatial_frequency_grid` | no | explicit transverse frequency grid, length `nx*ny` or the full volume |
| `potential_grid` | no | complex potential \f$V\f$, length `nx*ny` or the full volume |
| `wt_axis`, `kx_axis`, `ky_axis` | no | explicit axes (`kx_axis`, `ky_axis` in tensor runs only); generated by the library otherwise |

`samples` is reshaped to a row vector internally, so any orientation works. The
default frequency grid is FFT-ordered (non-negative frequencies first, then the
negative half), matching what the library expects:

```matlab
idx   = 0:(n - 1);
half  = floor((n - 1) / 2);
omega = (2 * pi / (n * dt)) * (idx - n * (idx > half));
pulse.frequency_grid = complex(omega, zeros(1, n));
```

Supplying it explicitly is worthwhile whenever you also want the same axis for
plotting or spectral post-processing.

<a name="operators"></a>

## Describing the Operators

Operators are function handles. The handle body must be a single expression in
the runtime symbols; the binding lowers it to the library's runtime expression
when the run starts. Anything that is not a function handle (a string, a
struct) raises `nlolib:invalidOperator`.

Which symbols an operator may use depends on the run type. A run is a *tensor
run* when the pulse sets `tensor_nt`, `tensor_nx` and `tensor_ny`, and a
*temporal run* otherwise:

| Operator | How it is passed | Temporal run | Tensor run |
|---|---|---|---|
| linear \f$D\f$, applied as \f$\exp(hD)\f$ | second argument | `@(A, w)` | `@(A, wt, kx, ky, x, y, t)` |
| nonlinear \f$N(A)\f$ | third argument | `@(A, I, V)` | `@(A, I, V)` |
| per-step linear operator | `linear_step_operator=` | `@(A, D, h, w, V)` | `@(A, D, h, wt, kx, ky, x, y, t, V)` |
| potential \f$V\f$ | `potential_operator=` | not allowed | `@(x, y, t)` |

| Symbol | Meaning |
|---|---|
| `A` | current field value |
| `I` | \f$\lvert A\rvert^2\f$ |
| `V` | the potential (`potential_grid` or `potential_operator`) |
| `w`, `wt` | temporal angular frequency; the two names are the same axis |
| `kx`, `ky` | transverse frequency axes (tensor runs) |
| `t`, `x`, `y` | coordinate axes (tensor runs) |
| `D`, `h` | the linear factor and the step size, in the per-step operator |
| `exp`, `log`, `sqrt`, `sin`, `cos` | intrinsics |

An argument named after a symbol binds to that symbol, in any position; any
other name takes the next unused symbol in the order shown, so
`@(field, omega)` is `@(A, w)`. Because `w` and `wt` name the same axis, a
linear operator written as `@(A, w)` works for both run types. Declare only
what you use:

```matlab
beta2 = 0.05;
gamma = 0.01;
linearOperator    = @(A, w) 1i * (beta2 / 2.0) * (w .* w);
nonlinearOperator = @(A, I) 1i * gamma * A .* I;
```

Rules that matter in practice:

- Element-wise operators are normalised (`.*` → `*`, `.^` → `^`, `./` → `/`),
  and imaginary literals (`1i`, `0.5j`) become multiples of `i`. The body must
  be a single expression — no statements, no branching, no calls beyond the
  intrinsics above.
- An argument named after a runtime symbol the run type does not have
  (`@(A, kx)` in a temporal run, say) is an `nlolib:invalidOperator` error
  before the library is called, and so are two arguments for one symbol, such
  as `@(A, w, wt)`.
- Runtime symbols enter only through arguments. Any other identifier in the
  body, even one spelled like a symbol, is captured from the handle's
  workspace as a real scalar constant (here, `beta2` and `gamma`). A captured value that is
  non-scalar, complex, or non-finite is an error, and so is a struct field:
  copy `cfg.gamma` into a local `gamma` before writing the handle.
- `constant_bindings=struct('beta2', -0.01)` (or a `containers.Map`) names
  values explicitly; a name there wins over the workspace.
- All operators together may use at most 16 constants; more is
  `nlolib:invalidOption`.
- With `nonlinear_model="kerr_raman"` the nonlinear handle is ignored; pass
  `@(A) 0 * A`.
- `potential_operator` is for tensor runs without a `potential_grid`; on a
  temporal run, or together with `potential_grid`, it is `nlolib:invalidOption`.

<a name="options"></a>

## Propagation Options

| Option | Default | Meaning |
|---|---|---|
| `propagation_distance` | *required*, > 0 | total \f$z\f$ to propagate |
| `preset` | `"balanced"` | `"fast"`, `"balanced"` or `"accuracy"`; solver defaults, see below |
| `starting_step_size`, `max_step_size`, `min_step_size`, `error_tolerance` | from preset | step bounds in \f$z\f$ units and the adaptive-step error target |
| `num_records` | from preset | number of \f$z\f$ samples to return |
| `record_z` | unset | explicit \f$z\f$ positions to record at |
| `return_records` | `true` | `false` keeps only what `storage` writes |
| `potential_operator`, `linear_step_operator` | unset | see [Describing the Operators](#operators) |
| `constant_bindings` | unset | name → real scalar for the operators |
| `nonlinear_model` | `"expr"` | `"kerr_raman"` selects the compiled Kerr+Raman model instead of the nonlinear handle |
| `nonlinear_gamma` | `0.0` | Kerr coefficient for the built-in model |
| `raman_fraction` | `0.0` | fractional Raman contribution |
| `raman_tau1`, `raman_tau2` | `0.0122`, `0.0320` | Raman response time constants |
| `shock_omega0` | `0.0` | self-steepening reference frequency |
| `raman_response_time` | unset | explicit complex response samples, used in place of `tau1`/`tau2` |
| `exec_options` | unset | backend selection, below |
| `storage` | unset | SQLite storage, see [SQLite Storage](#storage) |
| `capture_step_history` | `false` | fill `result.step_history` |
| `step_history_capacity` | `200000` | step events to preallocate |
| `live_progress` | `true` (`false` under `-batch`) | MATLAB only: print progress and logs in the Command Window during the run; Ctrl+C aborts |
| `progress_style` | auto | MATLAB only: `"inline"` redraws one line in place; `"lines"` prints one line per milestone |
| `stream_logs` | `false` | MATLAB only: print the runtime log buffer after the call, and attach it to the error when the run fails |

### Which records come back

- `record_z` given: records at exactly those positions, which must lie within
  \f$[0, L]\f$ and be nondecreasing. `num_records` must then be unset or equal
  to `numel(record_z)`. `result.z_axis` is the list you asked for.
- `record_z` unset and `num_records = 1`: the final field only, and
  `result.z_axis` is `L`.
- Otherwise `num_records` uniformly spaced positions from 0 to \f$L\f$.

```matlab
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=0.05, record_z=[0.0, 0.005, 0.02, 0.05]);   % 4 records
```

A single `record_z` position returns the field at that \f$z\f$, like any other
length. `result.final` is the last returned record, so with a `record_z` that
ends before \f$L\f$ it is the field at `record_z(end)`, not at \f$L\f$.

### Presets

Step sizes scale with the propagation distance \f$L\f$:

| Preset | starting step | max step | min step | tolerance | records |
|---|---|---|---|---|---|
| `"fast"` | \f$L/120\f$ | \f$L/12\f$ | \f$L/4000\f$ | `5e-6` | 64 |
| `"balanced"` | \f$L/200\f$ | \f$L/25\f$ | \f$L/20000\f$ | `1e-6` | 128 |
| `"accuracy"` | \f$L/400\f$ | \f$L/50\f$ | \f$L/80000\f$ | `1e-7` | 192 |

The solver is adaptive, so these are bounds and an initial guess, not a fixed
schedule. Any of `error_tolerance`, `starting_step_size`, `max_step_size` and
`min_step_size` given as an option replaces the preset value.

### Execution options

`exec_options` is a struct with the C `execution_options` field names. Any
other field, and an integer where a string is expected, is
`nlolib:invalidOption`.

| Field | Default | Meaning |
|---|---|---|
| `backend_type` | `"auto"` | `"cpu"`, `"vulkan"` or `"auto"` |
| `fft_backend` | `"auto"` | `"auto"`, `"fftw"` or `"vkfft"` |
| `device_heap_fraction` | `0.70` | fraction of the device budget the solver may use |
| `record_ring_target` | `0` | record ring size hint; `0` lets the library choose |
| `forced_device_budget_bytes` | `0` | override the detected device budget |

```matlab
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
    propagation_distance=1.0, ...
    exec_options=struct('backend_type', "vulkan", 'fft_backend', "vkfft"));
```

<a name="result"></a>

## Reading the Result

`propagate` returns a struct:

| Field | Type | Meaning |
|---|---|---|
| `records` | `numRecords x numSamples` complex | recorded fields, one row per \f$z\f$ sample |
| `z_axis` | numeric | \f$z\f$ of each record |
| `final` | `1 x numSamples` complex | the last returned record, `records(end, :)`; the field at \f$L\f$ unless `record_z` ends earlier; `[]` when nothing was returned |
| `step_history` | struct or `[]` | solver telemetry when `capture_step_history`, see below |
| `storage_result` | struct or `[]` | what was written when `storage` is given |
| `meta` | struct | `preset`, `records_requested`, `records_written`, `backend_requested`, `coupled`, `status` |

`meta.preset`, `meta.backend_requested` and `meta.status` are strings
(`status` is `"ok"`; a failed run raises instead). `coupled` is true for a
tensor run with a transverse extent.

`records_written` can be smaller than `records_requested` — the library reduces
the count for fixed-step runs, explicit-\f$z\f$ schedules, and aborted
runs — so size plots off `size(result.records, 1)` rather than the request:

```matlab
intensity = abs(result.records).^2;
imagesc(t, result.z_axis, intensity);
set(gca, 'YDir', 'normal');
xlabel('t'); ylabel('z'); colorbar;

power = sum(intensity, 2);
fprintf('power drift = %.3e\n', abs(power(end) - power(1)) / power(1));
```

<a name="tensor"></a>

## Coupled 2D and 3D Runs

Setting `tensor_nt`, `tensor_nx`, and `tensor_ny` switches the run to a tensor
field of `tensor_nt * tensor_nx * tensor_ny` points. `samples` must be
flattened t fastest, then y, then x — which is exactly MATLAB's own ordering
for an `(nt, ny, nx)` array, so a plain `reshape(field0, 1, [])` is correct and
`reshape(row, [ny, nx])` inverts it for a transverse sheet.

Diffraction is encoded in the linear operator through `kx`/`ky`; the transverse
axes are generated by the library from `delta_x` and `delta_y` unless you supply
`spatial_frequency_grid` or `kx_axis`/`ky_axis`. The coordinate axes `x` and `y`
are centred: \f$x_i = (i - (n_x - 1)/2)\,\Delta x\f$.

### Transverse-only (x-y sheet)

Set `tensor_nt = 1`:

```matlab
[xx, yy] = meshgrid(x, y);                       % both ny-by-nx
field0    = complex(exp(-((xx - x0).^2 + yy.^2) / w^2), 0);
potential = grinDepth * (xx.^2 + yy.^2);         % V(x,y)

pulse = struct();
pulse.samples        = reshape(field0, 1, []);
pulse.tensor_nt      = 1;
pulse.tensor_nx      = nx;
pulse.tensor_ny      = ny;
pulse.delta_x        = dx;
pulse.delta_y        = dy;
pulse.delta_time     = 1.0;                      % unused when tensor_nt == 1
pulse.potential_grid = reshape(complex(potential, 0), 1, []);

betaT = -1.0 / (2.0 * k0);
linearOperator    = @(A, kx, ky) 1i * betaT * (kx.^2 + ky.^2);
nonlinearOperator = @(A, I, V) 1i * A .* V;      % consume the potential only

result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=zFinal, num_records=96);

sheets = zeros(size(result.records, 1), ny, nx);
for idx = 1:size(result.records, 1)
    sheets(idx, :, :) = reshape(result.records(idx, :), [ny, nx]);
end
```

The same potential can be written as an operator instead of a grid:
`potential_operator=@(x, y) grinDepth * (x.^2 + y.^2)`, with `potential_grid`
left out.

See [`examples/matlab/transverse_grin_beam.m`](../examples/transverse_grin_beam.m)
for the complete script, which checks the beam centroid against
\f$x_0\cos(gz)\f$.

### Full 3+1D (t, x, y)

```matlab
field0 = zeros(nt, ny, nx);
for idx = 1:nt
    field0(idx, :, :) = temporal(idx) * spatial;   % spatial is ny-by-nx
end

pulse = struct();
pulse.samples        = reshape(complex(field0, 0), 1, []);
pulse.tensor_nt      = nt;
pulse.tensor_nx      = nx;
pulse.tensor_ny      = ny;
pulse.delta_time     = dt;
pulse.delta_x        = dx;
pulse.delta_y        = dy;

b2 = 0.5 * beta2;
bt = -1.0 / (2.0 * k0);
linearOperator = @(A, wt, kx, ky) 1i * (b2 * wt.^2 + bt * (kx.^2 + ky.^2));
```

Full script: [`examples/matlab/spatiotemporal_kerr_bullet.m`](../examples/spatiotemporal_kerr_bullet.m).

Each record comes back as one flat row of `nt*nx*ny` samples.
`nlolib.tensor_record_view` reshapes one record into a volume indexed as
`volume(it, iy, ix)`, the same view the Python and Julia packages return:

```matlab
volume = nlolib.tensor_record_view(result.final, nt, nx, ny);
imagesc(abs(squeeze(volume(ceil(nt / 2), :, :))).^2);   % x-y slice at pulse centre
```

Memory grows as the product of the three dimensions times the record count —
check the budget with [`query_runtime_limits`](#limits) before launching a large
grid.

<a name="telemetry"></a>

## Solver Telemetry and Step History

```matlab
result  = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                           propagation_distance=1.0, capture_step_history=true);
history = result.step_history;

fprintf('%d steps, %d dropped, mean step %.3e\n', ...
        numel(history.step_index), history.dropped, mean(history.step_size));
semilogy(history.z, history.error);
xlabel('z'); ylabel('local error estimate');
```

| Field | Meaning |
|---|---|
| `step_index` | solver step counter |
| `z` | position at the start of the step |
| `step_size` | step actually taken |
| `next_step_size` | step proposed for the following iteration |
| `error` | local error estimate |
| `dropped` | events the library could not record — raise `step_history_capacity` |
| `capacity` | capacity the buffer was allocated with |

A non-zero `dropped` means the history is truncated, not that the run failed.

<a name="logging"></a>

## Logging, Progress, and Perf Counters

### Logs

```matlab
nlolib.set_log_level("debug");            % "error", "warn", "info" or "debug"
nlolib.set_log_buffer(256 * 1024);
nlolib.clear_log_buffer();

result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, propagation_distance=1.0);

text = nlolib.read_log_buffer();                  % read and consume
text = nlolib.read_log_buffer(consume=false);     % read without consuming
nlolib.set_log_file('run.log', append=true);      % also mirror to a file
```

`stream_logs=true` does the buffer setup and the drain for you, prints the
text, and attaches it to the error message when a propagation fails — the
fastest way to diagnose a failing run.

### Progress

The MATLAB desktop and the VS Code MATLAB extension do not show the library's
own stdout/stderr. `propagate` therefore prints a live progress line, and every
runtime log line, through the Command Window while the solver runs, and Ctrl+C
stops the run (`nlolib:propagationAborted`). This uses a small MEX file shipped
with the toolbox (`+nlolib/private/progress_mex`). Without it (a build tree
where `matlab/build_progress_mex.m` has not been run), the logs are printed
after the run instead and the progress bar is not shown.

The progress line is redrawn at most once per second, so a fast solver cannot
queue more updates than the Command Window can paint. In browser-based MATLAB
(matlab-proxy, MATLAB Online, and the R2025a+ desktop) the Command Window
prints backspaces rather than erasing with them, so `propagate` prints one line
per progress milestone instead (every 5% by default; see
`set_progress_options`). Pass `progress_style="inline"` or `"lines"` to
override the choice.

Under `-batch` the library's own console progress bar is used instead; pass
`live_progress` to choose explicitly.

```matlab
nlolib.set_progress_options(enabled=false);                 % no progress output at all
nlolib.set_progress_options(enabled=true, milestone_percent=10);
nlolib.set_progress_stream("both");                         % console bar: "stderr", "stdout" or "both"
```

When the console bar is used and MATLAB has no desktop, `propagate` selects
stream mode `"both"` automatically so progress survives redirection.

### Perf counters

```matlab
nlolib.perf_profile_set_enabled(true);
nlolib.perf_profile_reset();

result   = nlolib.propagate(pulse, linearOperator, nonlinearOperator, propagation_distance=1.0);
snapshot = nlolib.perf_profile_read();

fprintf('dispersion %.1f ms over %d calls, nonlinear %.1f ms over %d calls\n', ...
        snapshot.dispersion_ms, snapshot.dispersion_calls, ...
        snapshot.nonlinear_ms,  snapshot.nonlinear_calls);
```

The snapshot also reports GPU dispatch counts, host/device copy counts and
bytes, upload/download totals, and the operator JIT counters
(`operator_jit_programs`, `operator_jit_fallbacks`) — useful when comparing FFT
backends or tuning `device_heap_fraction`.

Every logging and perf function raises `nlolib:unavailable` when the loaded
library was built without the corresponding entry point, so guard them if you
ship against multiple builds.

<a name="limits"></a>

## Sizing a Run with query_runtime_limits

```matlab
limits = nlolib.query_runtime_limits(pulse=pulse, exec_options=struct('backend_type', "vulkan"));

fprintf('max time samples          : %d\n', limits.max_num_time_samples_runtime);
fprintf('max in-memory records     : %d\n', limits.max_num_recorded_samples_in_memory);
fprintf('max records with storage  : %d\n', limits.max_num_recorded_samples_with_storage);
fprintf('working set / budget      : %.2f / %.2f GiB\n', ...
        limits.estimated_required_working_set_bytes / 2^30, ...
        limits.estimated_device_budget_bytes / 2^30);
```

Both options are optional; without `pulse` the limits that depend on the grid
are 0. `storage_available` mirrors `nlolib.storage_is_available()`.

Query before a large tensor run and clamp `num_records` to
`max_num_recorded_samples_in_memory`, or enable storage.

<a name="storage"></a>

## SQLite Storage

Storage streams records to a database instead of holding them all in memory. It
is only present when the library was built with SQLite support — check
`nlolib.storage_is_available()` first, or you get `nlolib:unavailable`.

```matlab
storage = struct('sqlite_path', 'run.sqlite', ...   % required
                 'run_id', 'sweep-01', ...
                 'chunk_records', 64);

result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=1.0, num_records=4096, ...
                          storage=storage, return_records=false);   % stream only, keep memory flat
disp(result.storage_result);
```

| Field | Meaning |
|---|---|
| `sqlite_path` | database path, required and non-empty |
| `run_id` | run label, at most 63 characters; generated when omitted |
| `sqlite_max_bytes` | database size cap, `0` for unlimited |
| `chunk_records` | records per write batch |
| `cap_policy` | `"stop_writes"` (default) stops writing at the cap, `"fail"` fails the run |
| `log_final_output_field_to_db` | also persist the final field |

`result.storage_result` reports `run_id`, `records_captured`,
`records_spilled`, `chunks_written`, `db_size_bytes`, and `truncated`. With
`return_records=false`, `result.records` is empty by design — read the data
back from the database. `return_records=false` without `storage` is an
`nlolib:invalidOption` error, since nothing would be kept.

<a name="troubleshooting"></a>

## Troubleshooting

Every error the package raises carries one of seven identifiers:

| Identifier | Cause | Fix |
|---|---|---|
| `nlolib:invalidOperator` | an operator that is not a function handle (strings included), or a handle the binding cannot lower: an unknown identifier, an argument named after a symbol the run type does not have, two arguments for one symbol | see [Describing the Operators](#operators) |
| `nlolib:invalidPulse` | missing `samples`/`delta_time`, an unknown pulse field, or a shape mismatch | `numel(samples)` must equal `tensor_nt*tensor_nx*tensor_ny` |
| `nlolib:invalidOption` | a bad option value, including an unknown enum string or an integer where a string is expected, an unknown `exec_options`/`storage` field, more than 16 constants | the message names the option |
| `nlolib:libraryLoadFailed` | no `nlolib.dll` / `libnlolib.so` found, or every candidate failed to load, or MATLAB's parsed type table is unusable | the message lists each library and the interface used (prototype or header); a header-parse failure means no prototype was staged and no compiler is set up — run `matlab/generate_library_prototype.m` or `mex -setup C`. For a stale type table run `nlolib.unload(); clear classes;` and check only one `nlolib` package is on the path |
| `nlolib:unavailable` | the library was built without the feature (SQLite storage, a logging or perf entry point) | check `nlolib.storage_is_available()`, guard optional calls |
| `nlolib:statusFailed` | the C call returned a non-OK status; the message names it (`"invalid_argument"`, `"allocation_failed"`, `"not_implemented"`) | rerun with `stream_logs=true` and `nlolib.set_log_level("debug")` |
| `nlolib:propagationAborted` | the run was stopped (Ctrl+C during live progress) | |

An unknown option name is MATLAB's own name=value error.

When a run misbehaves numerically rather than failing, the usual sequence is:
tighten `preset` to `"accuracy"`, enable `capture_step_history` and look for the
step size pinned at `min_step_size`, then check power/energy drift across
`result.records`.

<a name="examples"></a>

## Example Scripts

The examples are the set shared with the Python and Julia packages: the same
problem, parameters and printed metric labels in every binding. Each is a
function that prints its metrics as `label: value` and returns them in a
struct. They use `setup_matlab_example_environment` and the `+backend`
helpers (grids, metrics, plots).

| Script | Shows | Metrics |
|---|---|---|
| [`quickstart.m`](../examples/quickstart.m) | the shortest propagate call: a chirped Gaussian under dispersion | initial power, final power |
| [`linear_drift.m`](../examples/linear_drift.m) | dispersive drift of a phase-ramped pulse against the exact linear solution | centroid slope relative error |
| [`spm.m`](../examples/spm.m) | self-phase modulation against the closed-form phase | final mean pointwise relative error, power drift |
| [`second_order_soliton.m`](../examples/second_order_soliton.m) | N = 2 soliton over one period, with step history | epsilon (relative L2 intensity error at z_final) |
| [`conservation_checks.m`](../examples/conservation_checks.m) | energy, momentum and Hamiltonian of a lossless NLSE run | max energy / momentum / Hamiltonian drift |
| [`raman_scattering.m`](../examples/raman_scattering.m) | built-in Kerr + Raman model, self-frequency shift against the moment equation | centroid-curve relative error vs prediction |
| [`tensor_dispersion_3d.m`](../examples/tensor_dispersion_3d.m) | linear (t, x, y) run against the exact FFT-domain solution | final field relative error, power drift |
| [`transverse_grin_beam.m`](../examples/transverse_grin_beam.m) | x-y run, potential grid, beam centroid against x0 cos(gz) | power drift, max centroid deviation |
| [`spatiotemporal_kerr_bullet.m`](../examples/spatiotemporal_kerr_bullet.m) | 3+1D Gaussian packet, linear vs Kerr, against Gaussian spreading laws | width error, radius error, energy drift |
| [`grin_soliton_fission.m`](../examples/grin_soliton_fission.m) | 4th-order soliton fission in a GRIN fibre | energy drift, peak power in/out (MW), accepted steps |
| [`high_order_grin_soliton.m`](../examples/high_order_grin_soliton.m) | saturable nonlinearity, linear_step_operator, GRIN guidance | final radius / launch radius, min overlap fidelity, power drift |
| [`sqlite_storage.m`](../examples/sqlite_storage.m) | return_records=false with SQLite storage, read back | records captured, chunks written, db size bytes |

Run one from the repository with:

```matlab
addpath('examples');
quickstart
```

Plots are written under `examples/output/<example-name>/` (or the folder in
`NLOLIB_EXAMPLE_OUTPUT`). The largest, `high_order_grin_soliton`, returns
805 MB of records.

## Related Reference

- @ref matlab_binding — generated symbol reference
- [MATLAB Binding Guide](binding_guide.md) — build-tree usage, tests, design notes
- [Runtime Operator Mathematics](../../docs/runtime_operators.md)
- [Build and Install](../../docs/build_and_install.md)
- @ref c_api — the underlying C entry points
