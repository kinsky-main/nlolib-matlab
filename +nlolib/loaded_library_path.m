function path = loaded_library_path()
%LOADED_LIBRARY_PATH Path of the loaded nlolib shared library.
%   path = nlolib.loaded_library_path()
%
%   Returns a string; "" when no library is loaded. Does not load one.
%
%   See also NLOLIB.LOAD.
path = "";
if libisloaded('nlolib')
    path = string(library_state("path"));
end
end
