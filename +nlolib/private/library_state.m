function value = library_state(key, newValue)
%LIBRARY_STATE Session state shared by the package functions.
%   value = library_state(key)            read
%   library_state(key, newValue)          write
%
%   Private. Keys:
%     "path"      shared library loadlibrary used ('' when none)
%     "progress"  last options given to nlolib.set_progress_options
persistent state
if isempty(state)
    state = struct('path', '', ...
                   'progress', struct('enabled', true, ...
                                      'milestone_percent', int32(5), ...
                                      'emit_on_step_adjust', false));
end
key = char(key);
if nargin > 1
    state.(key) = newValue;
end
value = state.(key);
end
