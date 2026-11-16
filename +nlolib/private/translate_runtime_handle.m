function [expression, constants] = translate_runtime_handle(fn, context, runtime)
%TRANSLATE_RUNTIME_HANDLE Lower an operator function handle to a C runtime expression.
%   [expression, constants] = translate_runtime_handle(fn, context, runtime)
%
%   Private: the C API takes operators as expression strings, so the wrapper
%   lowers each operator handle through this function. Users pass function
%   handles only.
%
%   Each argument binds to a runtime symbol. An argument named after one of
%   the context's symbols binds to that symbol; any other name binds to the
%   next unused symbol in the context's order (as in the Python binding):
%
%     "dispersion_factor"  @(A, w, wt, kx, ky, x, y, t)
%     "dispersion"         @(A, D, h, w, wt, kx, ky, x, y, t, V)
%     "linear_factor"      @(A, wt, kx, ky, x, y, t)
%     "linear"             @(A, D, h, wt, kx, ky, x, y, t, V)
%     "nonlinear"          @(A, I, V)
%     "potential"          @(x, y, t, wt, kx, ky)
%
%   The body must be a single expression. Element-wise operators are
%   normalised (.* -> *, .^ -> ^, ./ -> /) and imaginary literals (1i, 0.5j)
%   become multiples of i. Any other identifier, apart from the intrinsics
%   exp, log, sqrt, sin and cos, is captured from the handle's closure as a
%   real scalar constant; constants(k) is referenced as c<k-1>.
%
%   runtime.constant_bindings (struct or containers.Map) pins values
%   explicitly; runtime.auto_capture_constants = false rejects closure
%   capture, so every identifier must then be bound.
if ischar(fn) || isstring(fn)
    error('nlolib:stringOperatorRemoved', ...
          ['%s operator must be a function_handle; string expressions are no ' ...
           'longer accepted. Pass e.g. @(A, w) 1i * beta2 * w.^2.'], context);
end
if ~isa(fn, "function_handle")
    error('nlolib:invalidOperatorSpec', ...
          '%s operator must be a function_handle, got %s.', context, class(fn));
end
context = char(context);
switch context
    case 'dispersion_factor'
        symbols = {'A', 'w', 'wt', 'kx', 'ky', 'x', 'y', 't'};
    case 'dispersion'
        symbols = {'A', 'D', 'h', 'w', 'wt', 'kx', 'ky', 'x', 'y', 't', 'V'};
    case 'linear_factor'
        symbols = {'A', 'wt', 'kx', 'ky', 'x', 'y', 't'};
    case 'linear'
        symbols = {'A', 'D', 'h', 'wt', 'kx', 'ky', 'x', 'y', 't', 'V'};
    case 'nonlinear'
        symbols = {'A', 'I', 'V'};
    case 'potential'
        symbols = {'x', 'y', 't', 'wt', 'kx', 'ky'};
    otherwise
        error('nlolib:invalidOperatorSpec', 'unknown operator context "%s"', context);
end
if nargin < 3
    runtime = struct();
end

handleText = char(func2str(fn));
[argNames, body] = parse_handle_text(handleText);
if numel(argNames) < 1 || numel(argNames) > numel(symbols)
    error('nlolib:invalidOperatorSpec', ...
          '%s handle must take 1 to %d arguments (%s)', ...
          context, numel(symbols), strjoin(symbols, ', '));
end

symbolMap = containers.Map("KeyType", "char", "ValueType", "char");
used = false(1, numel(symbols));
for idx = 1:numel(argNames)
    hit = find(strcmp(symbols, argNames{idx}) & ~used, 1);
    if isempty(hit)
        hit = find(~used, 1);
    end
    symbolMap(argNames{idx}) = symbols{hit};
    used(hit) = true;
end

body = strrep(body, ".^", "^");
body = strrep(body, ".*", "*");
body = strrep(body, "./", "/");
% Imaginary literals: 1i / 1.0j -> i, other magnitudes -> (k*i). MATLAB
% double-quoted strings do not process escapes, so single backslashes here.
body = regexprep(body, "(?<![A-Za-z0-9_.])1(\.0+)?[iIjJ]\>", "i");
body = regexprep(body, "(?<![A-Za-z0-9_.])(\d+\.?\d*([eE][+-]?\d+)?)[iIjJ]\>", "($1*i)");

bindings = struct();
if isfield(runtime, "constant_bindings") && ~isempty(runtime.constant_bindings)
    bindings = runtime.constant_bindings;
end
autoCapture = true;
if isfield(runtime, "auto_capture_constants")
    autoCapture = logical(runtime.auto_capture_constants);
end
workspaceScope = resolve_workspace_scope(fn);

constants = [];
constantsByName = containers.Map("KeyType", "char", "ValueType", "double");
function token = addConstant(name, value)
    if ~isfinite(value)
        error('nlolib:invalidOperatorSpec', "captured constant '%s' must be finite", name);
    end
    if isKey(constantsByName, name)
        idxLocal = constantsByName(name);
    else
        idxLocal = numel(constants);
        constantsByName(name) = idxLocal;
        constants(end + 1) = value; %#ok<AGROW>
    end
    token = sprintf('c%d', idxLocal);
end

% One pass over the identifiers, so an argument mapped to a symbol is never
% remapped (e.g. @(w, A) ...). The lookbehind skips the exponent of number
% literals such as 1e-5.
[names, gaps] = regexp(body, "(?<![\w.])[A-Za-z_]\w*", "match", "split");
for idx = 1:numel(names)
    name = names{idx};
    if isKey(symbolMap, name)
        names{idx} = symbolMap(name);
        continue;
    end
    % Symbols and intrinsics understood by the runtime expression compiler
    % (parse_primary in src/physics/operator_program_compile.c) pass through.
    if ismember(name, {'w', 'wt', 'kx', 'ky', 't', 'x', 'y', ...
                       'A', 'I', 'D', 'V', 'h', 'i', ...
                       'exp', 'log', 'sqrt', 'sin', 'cos'})
        continue;
    end

    [hasBinding, boundValue] = lookup_binding(bindings, name);
    if hasBinding
        if ~(isnumeric(boundValue) && isscalar(boundValue) && isreal(boundValue))
            error('nlolib:invalidOperatorSpec', ...
                  "constant binding '%s' must be a real scalar", name);
        end
        names{idx} = addConstant(['binding:' name], double(boundValue));
        continue;
    end

    if autoCapture && isfield(workspaceScope, name)
        value = workspaceScope.(name);
        if ~(isnumeric(value) && isscalar(value) && isreal(value))
            error('nlolib:invalidOperatorSpec', ...
                  "captured variable '%s' must be a real scalar", name);
        end
        names{idx} = addConstant(name, double(value));
        continue;
    end

    error('nlolib:invalidOperatorSpec', ...
          "unknown identifier '%s' in %s handle", name, context);
end

pieces = [gaps; [names, {''}]];
expression = char(strjoin(pieces(:).', ''));
end

function [argNames, body] = parse_handle_text(handleText)
tokenized = regexp(handleText, "^@\(([^)]*)\)\s*(.+)$", "tokens", "once");
if ~isempty(tokenized)
    argsRaw = strtrim(tokenized{1});
    body = strtrim(tokenized{2});
    if strlength(argsRaw) == 0
        argNames = {};
        return;
    end
    parts = split(string(argsRaw), ",");
    argNames = cellstr(strtrim(parts)).';
    return;
end

tokenized = regexp(handleText, "^@([A-Za-z_]\w*)\s*(.+)$", "tokens", "once");
if ~isempty(tokenized)
    argNames = {strtrim(tokenized{1})};
    body = strtrim(tokenized{2});
    return;
end

error('nlolib:invalidOperatorSpec', "unable to parse operator handle text '%s'", handleText);
end

function scope = resolve_workspace_scope(fn)
scope = struct();
info = functions(fn);
if isfield(info, "workspace") && ~isempty(info.workspace)
    firstScope = info.workspace{1};
    if isstruct(firstScope)
        scope = firstScope;
    end
end
end

function [found, value] = lookup_binding(bindings, name)
found = false;
value = [];
if isempty(bindings)
    return;
end
if isstruct(bindings) && isfield(bindings, name)
    found = true;
    value = bindings.(name);
    return;
end
if isa(bindings, "containers.Map") && isKey(bindings, name)
    found = true;
    value = bindings(name);
end
end
