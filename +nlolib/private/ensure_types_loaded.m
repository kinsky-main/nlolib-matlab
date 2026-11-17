function ensure_types_loaded()
%ENSURE_TYPES_LOADED Load the library if needed and check MATLAB resolved its types.
%   Private. Raises nlolib:libraryLoadFailed when the parsed type table is
%   unusable, which happens with an incompatible header/library pair or with
%   more than one nlolib package on the path.
if ~libisloaded('nlolib')
    nlolib.load();
end

typeName = 'sim_config';
try
    s = libstruct('sim_config');
    if isempty(fieldnames(s))
        error('nlolib:libraryLoadFailed', 'sim_config resolved to an empty type');
    end
    % Some parser modes leave nested fields as empty placeholders.
    typeName = 'propagation_params';
    set(s, 'propagation', libstruct('propagation_params', ...
                                    struct('starting_step_size', 0.0)));
    typeName = 'frequency_grid';
    grid = struct('frequency_grid', struct('re', 0.0, 'im', 0.0));
    libstruct('frequency_grid', grid);
    typeName = 'runtime_operator_params';
    libstruct('runtime_operator_params', ...
              struct('dispersion_factor_expr', 'A', ...
                     'nonlinear_expr', 'A', ...
                     'num_constants', uint64(0), ...
                     'constants', zeros(1, 16)));
    typeName = 'propagate_options';
    libstruct('propagate_options');
    typeName = 'propagate_output';
    libstruct('propagate_output');
catch ME
    error('nlolib:libraryLoadFailed', ...
          ['MATLAB could not construct the C type ''%s''. This usually means an ' ...
           'incompatible header/library pair or more than one nlolib package on ' ...
           'the path. Run nlolib.unload(); clear classes; then nlolib.load().\n\n' ...
           'Original error: %s'], typeName, ME.message);
end
end
