function s = zeroed_libstruct(typeName, fieldNames)
%ZEROED_LIBSTRUCT Build a materialised, zero-filled libstruct.
%   Private. libstruct(TYPE) with no initial value creates an empty structure
%   object, which calllib marshals as a NULL pointer, so output-parameter
%   calls such as nlolib_query_runtime_limits() fail with INVALID_ARGUMENT.
%   An initialiser forces MATLAB to allocate real backing storage.
init = struct();
for idx = 1:numel(fieldNames)
    init.(fieldNames{idx}) = 0;
end
s = libstruct(typeName, init);
end
