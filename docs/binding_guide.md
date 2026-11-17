# MATLAB Binding Guide

The MATLAB package exposes the native library as plain package functions
(`nlolib.propagate`, `nlolib.load`, ...), using `loadlibrary`/`calllib` with no
Python dependency. Its public surface is the vocabulary shared with the Python
and Julia packages (core `docs/binding_api_vocabulary.md`).

For the full walkthrough — pulse and operator specifications, options,
telemetry, coupled 2D/3D runs, logging, storage, and troubleshooting — see the
[MATLAB User Guide](user_guide.md). This page covers the binding
itself: install, build-tree usage, tests, and design notes.

## Install

Option A — toolbox (recommended). Download `nlolib.mltbx` from the release page
and double-click it, or:

```matlab
matlab.addons.install('nlolib.mltbx');
```

Option B — build tree, after configuring the core with this binding checked out
(see [development.md](development.md)):

```powershell
cmake --build build --config Release --target matlab_stage
```

```matlab
addpath('build/matlab_toolbox');
nlolib_setup();
nlolib.load();   % optional; the first nlolib call loads the library
```

Requires MATLAB R2023b or later and nothing else — no C compiler, no Visual C++
redistributable, no Vulkan runtime. The packaged toolbox ships a prebuilt
`loadlibrary` prototype, so the header is never parsed on the client.

The shared library (`nlolib.dll` / `libnlolib.so` / `libnlolib.dylib`) must be
reachable at runtime; the wrapper searches common staged and build-tree
locations, and `NLOLIB_LIBRARY` overrides the search. In a build tree with no
staged prototype the wrapper falls back to parsing `nlolib_matlab.h`, which
does need a compiler — run `generate_library_prototype.m` to avoid it,
and `build_progress_mex.m` for the live progress bar.

## Packaging a Release

Build one toolbox per platform, then merge them into a single `.mltbx` that
serves Windows and Linux users alike (one release asset, e.g. for File
Exchange):

```matlab
% On each platform, from the folder holding the build directory (needs a C
% compiler for the MEX), with this repository on the path:
package_mltbx('build');   % -> dist/nlolib-<version>-<arch>.mltbx

% On any machine, with all bundles copied into dist/:
merge_mltbx(["dist/nlolib-1.13.0-glnxa64.mltbx", "dist/nlolib-1.13.0-win64.mltbx"]);
% -> dist/nlolib-1.13.0.mltbx
```

Each bundle keeps its shared library, `loadlibrary` prototype and thunk in
`lib/<arch>`, and its progress MEX in `+nlolib/private` with the platform
extension, so the merge only adds files. `merge_mltbx` stops if the bundles'
versions differ or if any shared file differs (line endings aside), since
that means they were built from different sources. All bundles use the
toolbox identifier `nlolib`, so installing a newer one replaces the old;
toolboxes packaged before this change used `nlolib-<arch>` and must be
uninstalled once by hand.

## Minimal Math-to-API Example

This example uses the quadratic GLSE mapping

\f[
D(\omega)=i\left(\frac{\beta_2}{2}\right)\omega^2-\frac{\alpha}{2},
\qquad
N(A)=i\gamma A|A|^2
\f]

written as function handles. The scalars the handles use are captured as
runtime constants when the run starts:

```matlab
beta2 = -0.02;
alpha = 0.10;
gamma = 1.20;

linearOperator    = @(A, w) 1i * (beta2 / 2) * w.^2 - alpha / 2;
nonlinearOperator = @(A, I) 1i * gamma * A .* I;
```

The C API takes operators as expression strings; `nlolib.propagate` lowers
each handle to one privately (`+nlolib/private/translate_runtime_handle.m`),
in the C context the run type compiles: `dispersion_factor` for a temporal
run, `linear_factor` for a tensor run. Strings are not accepted from users.

## Quick Start

`nlolib.propagate` derives the solver schedule from a preset, so a run needs
only a pulse, two operators, and a propagation distance:

```matlab
n  = 512;
dt = 0.02;
t  = ((0:(n - 1)) - 0.5 * (n - 1)) * dt;

pulse = struct( ...
    'samples',    exp(-(t / 0.25).^2) .* exp(-1i * 8.0 * t), ...
    'delta_time', dt);

beta2 = -0.005;
gamma = 0.01;
linearOperator    = @(A, w) 1i * beta2 * w.^2;
nonlinearOperator = @(A, I) 1i * gamma * A .* I;

result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=1.0, num_records=128, preset="balanced");

imagesc(t, result.z_axis, abs(result.records).^2);
```

Every option is documented in [Propagation Options](user_guide.md#options).

## Checking Whether the GPU JIT Ran

On the Vulkan backend each operator program is compiled to a single GPU kernel
at runtime, and falls back to the interpreter when it cannot be. The fallback is
silent: results stay correct, only slower. Two counters say which happened.

```matlab
nlolib.perf_profile_reset();
result = nlolib.propagate(pulse, linearOperator, nonlinearOperator, ...
                          propagation_distance=1.0, exec_options=struct('backend_type', "vulkan"));

snapshot = nlolib.perf_profile_read();
fprintf('%d JIT programs, %d interpreter fallbacks\n', ...
        snapshot.operator_jit_programs, snapshot.operator_jit_fallbacks);
```

Unlike the timing counters in the same struct, these two need no
`perf_profile_set_enabled(true)`, so a shipped toolbox can be checked as it
stands. Both stay zero wherever the JIT is never reached -- the CPU backend, or
a library built with `ENABLE_VULKAN_BACKEND=OFF` -- which is not the same as a
program falling back. See [GPU backend behaviour](../../docs/gpu_backend.md).

## Examples

`examples/` holds the shared example set: twelve problems defined once in
the core's `tests/api_surface.json` and implemented in each binding. Each file
carries its numbers in a parameter block between the
`nlolib-example-parameters: begin` and `end` comments, which the core's
`tools/check_api_parity.py` compares with the manifest, and prints its metrics
with `backend.report_metric` under the shared labels. The index is in the
[user guide](user_guide.md#examples).

## Public API Entry Points

| Symbol | Purpose |
|---|---|
| `nlolib.propagate` | run a propagation; options by name |
| `nlolib.query_runtime_limits` | memory and record limits for a pulse |
| `nlolib.tensor_record_view` | one tensor-run record → `(nt, ny, nx)` volume |
| `nlolib.load`, `nlolib.unload`, `nlolib.loaded_library_path` | the shared library |
| `nlolib.storage_is_available` | SQLite storage built in |
| `nlolib.set_log_*`, `clear_log_buffer`, `read_log_buffer` | runtime logging |
| `nlolib.set_progress_options`, `set_progress_stream` | progress bar |
| `nlolib.perf_profile_*` | performance counters |
| `nlolib_setup` | add package, examples, and library directories to the MATLAB path |

Everything else is in `+nlolib/private`: the config builder
(`prepare_sim_config`), the complex buffer helpers (`pack_complex_array`,
`unpack_records`), the handle lowering, and the string-to-C-integer tables
(`enum_table`). Enum-style values are lowercase strings on the public surface;
there are no integer constants.

## Tests

| CTest name | Needs MATLAB? | Covers |
|---|---|---|
| `test_matlab_binding_types` | no | Every `libstruct('T')`/`libpointer('TPtr')` name resolves to a typedef in the core's `src/nlolib_matlab.h` |
| `test_matlab_header_abi` | no | Compile-time `sizeof`/`offsetof` parity between `nlolib_matlab.h` and the canonical headers |
| `test_matlab_bindings` | yes | Runtime-handle lowering and argument checks, the public package surface, plus an end-to-end FFI smoke suite (propagate, record selection, step history, storage, runtime limits, log buffer, perf counters) |

The core's `tools/check_api_parity.py --bindings matlab --surface report`
compares this package's sources with the shared surface manifest
(`tests/api_surface.json` in the core repository).

Run the MATLAB-free checks alone with:

```bash
ctest --test-dir build -R "test_matlab_binding_types|test_matlab_header_abi"
```

## Design Notes

`libstruct(TYPE)` with no initialiser creates an *empty* object that `calllib`
marshals as `NULL`; output-parameter calls must use
`zeroed_libstruct()` (private). Reading `.Value` on a struct pointer returns only
the first element, and `setdatatype()` rejects struct pointers outright, so
array read-back uses pointer arithmetic (`ptr = ptr + 1`).

`prepare_sim_config` returns a `keepalive` cell array holding the `libpointer`
objects that back the pointer fields. It must stay in scope for as long as the
config is used, otherwise MATLAB frees the buffers underneath the library.

MATLAB does not show the library's stdout/stderr, and `loadlibrary` cannot
take MATLAB functions as C callbacks. `mex/progress_mex.c` supplies the
C `progress_callback` instead: it prints nlolib's log buffer and a progress
line with `mexPrintf` (at most once per second, redrawn in place or one line
per milestone) and returns 0 on Ctrl+C. `package_mltbx` compiles it into
`+nlolib/private`, so toolbox users need no compiler. `propagate_options`
declares the callback field as `uint64_t` in `nlolib_matlab.h` so MATLAB can
store the address.

Why the binding is not generated with `clibgen`:
[clibgen_evaluation.md](clibgen_evaluation.md).

## Related Reference

- [MATLAB User Guide](user_guide.md)
- [Runtime Operator Mathematics](../../docs/runtime_operators.md)
- @ref matlab_binding
