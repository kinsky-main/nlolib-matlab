function code = to_c_enum(enumName, value, optionName)
%TO_C_ENUM Map a public enum string to its C integer (int32).
%   code = to_c_enum(enumName, value, optionName)
%
%   Private. Anything but one of the enum's strings, integers included, is
%   nlolib:invalidOption naming optionName.
[names, codes] = enum_table(enumName);
hit = [];
if (ischar(value) && (isrow(value) || isempty(value))) || (isstring(value) && isscalar(value))
    hit = find(names == string(value), 1);
end
if isempty(hit)
    error('nlolib:invalidOption', '%s must be one of "%s".', ...
          optionName, strjoin(names, '", "'));
end
code = int32(codes(hit));
end
