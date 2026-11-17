function set_progress_options(options)
%SET_PROGRESS_OPTIONS Configure the runtime progress bar.
%   nlolib.set_progress_options(enabled=true, milestone_percent=5, ...
%                               emit_on_step_adjust=false)
%
%   enabled shows the bar, milestone_percent is the percent between updates
%   (1 to 100) and emit_on_step_adjust also reports step-size changes. The
%   live_progress option of nlolib.propagate follows these settings.
%
%   See also NLOLIB.SET_PROGRESS_STREAM, NLOLIB.PROPAGATE.
arguments
    options.enabled = true
    options.milestone_percent = 5
    options.emit_on_step_adjust = false
end
settings = struct( ...
    'enabled', logical_option(options.enabled, 'enabled'), ...
    'milestone_percent', int32(count_option(options.milestone_percent, 'milestone_percent', 1)), ...
    'emit_on_step_adjust', logical_option(options.emit_on_step_adjust, 'emit_on_step_adjust'));
if settings.milestone_percent > 100
    error('nlolib:invalidOption', 'milestone_percent must be between 1 and 100.');
end
require_function('nlolib_set_progress_options');
check_status(calllib('nlolib', 'nlolib_set_progress_options', ...
                     int32(settings.enabled), settings.milestone_percent, ...
                     int32(settings.emit_on_step_adjust)), ...
             'nlolib_set_progress_options');
library_state("progress", settings);
end
