function report_metric(label, value)
%REPORT_METRIC Print one shared-example metric.
%   backend.report_metric(label, value) prints "label: value" with value in
%   %.6e, the same label and format as the Python and Julia examples.
fprintf('%s: %.6e\n', char(label), double(value));
end
