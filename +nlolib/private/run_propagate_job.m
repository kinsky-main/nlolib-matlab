function [statusRaw, logTail] = run_propagate_job(propagateArgs, view)
%RUN_PROPAGATE_JOB Run nlolib_propagate as a job and print its progress.
%   [statusRaw, logTail] = run_propagate_job(propagateArgs, view)
%
%   Private. propagateArgs is the cell of the six nlolib_propagate arguments.
%   view is a struct:
%     progress           print a progress line
%     style              'inline' (one line redrawn) or 'lines'
%     milestone_percent  percent between lines in the 'lines' style
%     logs               print the runtime log buffer
%   logTail is the end of the log text read during the run, for error
%   messages.
%
%   The library runs the propagation on its own thread
%   (nlolib_propagate_start) and this function polls it, so MATLAB stays
%   responsive: Ctrl+C interrupts between polls, and the job is then
%   cancelled and joined before the caller's buffers are released.
%
%   Command Window output is pulled, never pushed. However many steps the
%   solver takes and however much it logs, this function prints
%     - at most one update per second, and less often as the run gets longer
%       (the interval grows to 1/120 of the elapsed time), and
%     - at most 64 KiB of log text per run,
%   so a run of any length adds a bounded amount to the Command Window.
POLL_MS = 100;
state = struct('lineLength', 0, 'lastUpdate', -Inf, 'nextMilestone', 0, ...
               'logBytesLeft', 65536, 'logTail', "", 'stepSize', 0);

if ~require_function('nlolib_propagate_start', false)
    % A library without the job API: one blocking call, logs afterwards.
    statusRaw = calllib('nlolib', 'nlolib_propagate', propagateArgs{:});
    state = print_logs(state, view);
    logTail = state.logTail;
    return;
end

jobPtr = libpointer('uint64Ptr', uint64(0));
check_status(calllib('nlolib', 'nlolib_propagate_start', propagateArgs{:}, jobPtr), ...
             'nlolib_propagate_start');
% Runs on Ctrl+C and on any error below; a no-op once the job is finished.
abandon = onCleanup(@() abandon_job(jobPtr, view)); %#ok<NASGU>

info = zeroed_libstruct('progress_info', ...
                        {'step_index', 'percent', 'z_end', 'eta_seconds', 'step_size', ...
                         'accepted_steps', 'rejected_steps', 'min_step_size', 'max_step_size'});
donePtr = libpointer('int32Ptr', int32(0));
started = tic;
done = false;
while ~done
    calllib('nlolib', 'nlolib_propagate_poll', jobPtr.Value, uint32(POLL_MS), info, donePtr);
    done = donePtr.Value ~= 0;
    elapsed = toc(started);
    if done || elapsed - state.lastUpdate >= update_interval(elapsed)
        state.lastUpdate = elapsed;
        state = print_logs(state, view);
        state = print_progress(state, view, info, elapsed, done);
        if view.progress || view.logs
            drawnow('limitrate');
        end
    end
end

statusRaw = calllib('nlolib', 'nlolib_propagate_finish', jobPtr.Value);
jobPtr.Value = uint64(0);
state = print_logs(state, view);
logTail = state.logTail;
end

function seconds = update_interval(elapsed)
% One second at first, then 1/120 of the elapsed time: about 120 updates in
% the first two minutes and 120 more each time the run length grows e-fold.
seconds = max(1.0, elapsed / 120);
end

function abandon_job(jobPtr, view)
if jobPtr.Value == 0
    return;
end
calllib('nlolib', 'nlolib_propagate_cancel', jobPtr.Value);
calllib('nlolib', 'nlolib_propagate_finish', jobPtr.Value);
jobPtr.Value = uint64(0);
if view.progress
    fprintf('\n[nlolib] propagation cancelled.\n');
end
end

function state = print_logs(state, view)
% Print what the library logged since the last call, within the run's budget.
if ~view.logs
    return;
end
text = char(nlolib.read_log_buffer(consume=true));
if isempty(text)
    return;
end
tail = [char(state.logTail), text];
state.logTail = string(tail(max(1, end - 8191):end));
if state.logBytesLeft <= 0
    return;
end

state = erase_progress_line(state);
if numel(text) <= state.logBytesLeft
    state.logBytesLeft = state.logBytesLeft - numel(text);
    fprintf('%s', text);
    if text(end) ~= newline
        fprintf('\n');
    end
    return;
end
% Over budget: keep whole lines up to the limit, then say so once.
text = text(1:state.logBytesLeft);
lastBreak = find(text == newline, 1, 'last');
if ~isempty(lastBreak)
    fprintf('%s', text(1:lastBreak));
end
state.logBytesLeft = 0;
fprintf(['[nlolib] further log output of this run is not shown here ' ...
         '(64 KiB limit); nlolib.set_log_file keeps the full log.\n']);
end

function state = print_progress(state, view, info, elapsed, done)
if ~view.progress
    return;
end
if double(info.z_end) == 0 && done
    % The run ended before its first step (an argument error): no line.
    state = erase_progress_line(state);
    return;
end
percent = min(max(double(info.percent), 0), 100);
complete = percent >= 100 - 1e-9;
if done
    label = 'aborted';
    if complete
        label = 'complete';
    end
else
    label = 'running';
end

eta = double(info.eta_seconds);
if percent <= 0
    eta = NaN;      % no step has finished yet
end
% Rejection rate over every step attempt so far, and the current step between
% the step bounds on a log scale (the bounds are usually decades apart). The
% finish event carries no step size, so the last one seen is kept.
attempts = double(info.accepted_steps) + double(info.rejected_steps);
rejectFraction = 0;
if attempts > 0
    rejectFraction = double(info.rejected_steps) / attempts;
end
if double(info.step_size) > 0
    state.stepSize = double(info.step_size);
end
minStep = double(info.min_step_size);
maxStep = double(info.max_step_size);
if state.stepSize <= 0
    stepFraction = 0;
    stepText = '--';
else
    stepText = sprintf('%.3g', state.stepSize);
    stepFraction = 1;
    if minStep > 0 && maxStep > minStep
        stepFraction = min(max(log(state.stepSize / minStep) / log(maxStep / minStep), 0), 1);
    end
end

barWidth = 30;
filled = round(percent / 100 * barWidth);
line = sprintf(['[nlolib] [%s] %6.2f%% |%s%s| step %d eta %s elapsed %s ' ...
                'rejected %.1f%% step size %s um'], ...
               label, percent, repmat('#', 1, filled), repmat('-', 1, barWidth - filled), ...
               double(info.step_index), format_duration(eta), ...
               format_duration(elapsed), 100 * rejectFraction, stepText);

started = double(info.z_end) ~= 0;
if strcmp(view.style, 'lines')
    % One line per milestone, from the first step on; the 100% line is the
    % final one.
    due = done || (started && percent >= state.nextMilestone && ~complete);
    while state.nextMilestone <= percent
        state.nextMilestone = state.nextMilestone + view.milestone_percent;
    end
    if due
        fprintf('%s\n', line);
    end
    return;
end

% Inline: backspace over the old line, then write the new one.
back = repmat(sprintf('\b'), 1, state.lineLength);
if usejava('desktop')
    % The desktop Command Window deletes on backspace and renders bold and
    % one accent colour, so the bar is drawn in the style of pip's.
    if ~started
        status = 'starting';
    elseif done
        status = sprintf('%s in %s', label, format_duration(elapsed));
    else
        status = sprintf('elapsed %s  eta %s', format_duration(elapsed), format_duration(eta));
    end
    % Three rows, each with its own bar, redrawn together: backspace deletes
    % across the line breaks as well.
    mainText = sprintf(' %5.1f%%  step %d  %s', percent, double(info.step_index), status);
    rejectText = sprintf(' %5.1f%%  %d of %d attempts', 100 * rejectFraction, ...
                         double(info.rejected_steps), attempts);
    sizeText = sprintf('  %s um  (min %.3g, max %.3g)', stepText, minStep, maxStep);
    fprintf('%s<strong>nlolib</strong>     %s%s\nrejected   %s%s\nstep size  %s%s', back, ...
            bar_text(percent / 100, 30), mainText, bar_text(rejectFraction, 30), rejectText, ...
            bar_text(stepFraction, 30), sizeText);
    state.lineLength = 3 * (11 + 30) + 2 + numel(mainText) + numel(rejectText) + numel(sizeText);
else
    % A terminal only moves the cursor on backspace: pad over what is left.
    padding = max(0, state.lineLength - numel(line));
    fprintf('%s%s%s%s', back, line, blanks(padding), repmat(sprintf('\b'), 1, padding));
    state.lineLength = numel(line);
end
if done
    fprintf('\n');
    state.lineLength = 0;
end
end

function text = bar_text(fraction, width)
% A bar of width cells: the filled part heavy and in the accent colour, the
% rest light.
filled = round(min(max(fraction, 0), 1) * width);
text = [accent(repmat(char(9473), 1, filled)), repmat(char(9472), 1, width - filled)];
end

function text = accent(text)
% The Command Window's accent colour (orange): text between "[\b" and "]\b".
if ~isempty(text)
    text = ['[', char(8), text, ']', char(8)];
end
end

function state = erase_progress_line(state)
% Back over the inline progress line so other text starts on a clean line.
if state.lineLength > 0
    fprintf('%s', repmat(sprintf('\b'), 1, state.lineLength));
    state.lineLength = 0;
end
end

function text = format_duration(seconds)
if ~(seconds >= 0) || ~isfinite(seconds)
    text = '--:--';
    return;
end
total = round(seconds);
hours = floor(total / 3600);
if hours > 0
    text = sprintf('%d:%02d:%02d', hours, mod(floor(total / 60), 60), mod(total, 60));
else
    text = sprintf('%02d:%02d', floor(total / 60), mod(total, 60));
end
end
