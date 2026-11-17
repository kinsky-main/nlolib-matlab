function unload()
%UNLOAD Unload the nlolib shared library.
%   nlolib.unload()
%
%   MATLAB keeps a loaded library, and the file lock on it, until it is
%   unloaded, so this is needed to rebuild or replace the library within one
%   session. The next nlolib call loads it again.
%
%   See also NLOLIB.LOAD.
if libisloaded('nlolib')
    unloadlibrary('nlolib');
end
library_state("path", '');
end
