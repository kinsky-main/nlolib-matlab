function name = from_c_enum(enumName, code)
%FROM_C_ENUM Map a C integer back to its public enum string.
%   Private. An integer the table does not know comes back as "unknown".
[names, codes] = enum_table(enumName);
hit = find(codes == double(code), 1);
if isempty(hit)
    name = "unknown";
else
    name = names(hit);
end
end
