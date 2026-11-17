function [s, backendRequested] = make_exec_options(opts)
%MAKE_EXEC_OPTIONS Build the execution_options libstruct from an exec_options struct.
%   [s, backendRequested] = make_exec_options(opts)
%
%   Private. opts is [] or a struct with any of the C field names:
%     backend_type                "cpu", "vulkan" or "auto" (default)
%     fft_backend                 "auto" (default), "fftw" or "vkfft"
%     device_heap_fraction        default 0.70
%     record_ring_target          default 0
%     forced_device_budget_bytes  default 0
%   Any other field, or an integer where a string is expected, is
%   nlolib:invalidOption. backendRequested is the backend string.
if isempty(opts)
    opts = struct();
end
if ~isstruct(opts) || ~isscalar(opts)
    error('nlolib:invalidOption', 'exec_options must be a struct.');
end
known = {'backend_type', 'fft_backend', 'device_heap_fraction', ...
         'record_ring_target', 'forced_device_budget_bytes'};
unknown = setdiff(fieldnames(opts), known);
if ~isempty(unknown)
    error('nlolib:invalidOption', 'exec_options.%s is not an execution option; expected one of %s.', ...
          unknown{1}, strjoin(known, ', '));
end

backendRequested = "auto";
if isfield(opts, 'backend_type') && ~isempty(opts.backend_type)
    backendRequested = opts.backend_type;
end
fftBackend = "auto";
if isfield(opts, 'fft_backend') && ~isempty(opts.fft_backend)
    fftBackend = opts.fft_backend;
end

s = libstruct('execution_options');
s.backend_type = to_c_enum("vector_backend", backendRequested, 'exec_options.backend_type');
backendRequested = string(backendRequested);
s.fft_backend = to_c_enum("fft_backend", fftBackend, 'exec_options.fft_backend');
s.device_heap_fraction = 0.70;
if isfield(opts, 'device_heap_fraction') && ~isempty(opts.device_heap_fraction)
    fraction = opts.device_heap_fraction;
    if ~(isnumeric(fraction) && isscalar(fraction) && isreal(fraction) && ...
            fraction > 0 && fraction <= 1)
        error('nlolib:invalidOption', 'exec_options.device_heap_fraction must be in (0, 1].');
    end
    s.device_heap_fraction = double(fraction);
end
s.record_ring_target = uint64(0);
if isfield(opts, 'record_ring_target') && ~isempty(opts.record_ring_target)
    s.record_ring_target = uint64(count_option(opts.record_ring_target, ...
                                               'exec_options.record_ring_target', 0));
end
s.forced_device_budget_bytes = uint64(0);
if isfield(opts, 'forced_device_budget_bytes') && ~isempty(opts.forced_device_budget_bytes)
    s.forced_device_budget_bytes = uint64(count_option(opts.forced_device_budget_bytes, ...
                                                       'exec_options.forced_device_budget_bytes', 0));
end

% The Vulkan sub-struct stays zero: the library creates its own device.
s.vulkan.physical_device = libpointer();
s.vulkan.device = libpointer();
s.vulkan.queue = libpointer();
s.vulkan.queue_family_index = uint32(0);
s.vulkan.command_pool = libpointer();
s.vulkan.descriptor_set_budget_bytes = uint64(0);
s.vulkan.descriptor_set_count_override = uint32(0);
end
