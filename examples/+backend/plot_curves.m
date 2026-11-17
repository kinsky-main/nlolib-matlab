function savedPath = plot_curves(x, curves, labels, outputPath, varargin)
%PLOT_CURVES Save a line plot of one or more curves against x.
%   savedPath = backend.plot_curves(x, {y1, y2}, ["a", "b"], path, ...
%                                   "x_label", ..., "y_label", ..., "title", ...)
p = inputParser;
addParameter(p, "x_label", "x");
addParameter(p, "y_label", "");
addParameter(p, "title", "");
addParameter(p, "log_y", false);
parse(p, varargin{:});
if ~iscell(curves)
    curves = {curves};
end
savedPath = char(string(outputPath));
fig = figure("Visible", "off");
ax = axes(fig);
hold(ax, "on");
for idx = 1:numel(curves)
    plot(ax, x, curves{idx}, "LineWidth", 1.4);
end
hold(ax, "off");
if p.Results.log_y
    set(ax, "YScale", "log");
end
grid(ax, "on");
xlabel(ax, p.Results.x_label);
ylabel(ax, p.Results.y_label);
title(ax, p.Results.title);
if ~isempty(labels)
    legend(ax, labels, "Location", "best");
end
print(fig, savedPath, "-dpng", "-r200");
close(fig);
end
