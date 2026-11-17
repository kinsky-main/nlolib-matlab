function [expression, constants] = translate_runtime_handle(fn, context, bindings)
%TRANSLATE_RUNTIME_HANDLE Lower an operator function handle to a C runtime expression.
%   [expression, constants] = translate_runtime_handle(fn, context, bindings)
%
%   Private: the C API takes operators as expression strings, so
%   nlolib.propagate lowers each operator handle through this function.
%
%   Arguments bind to the context's symbols (core tests/api_surface.json,
%   operator_lowering.parameter_binding):
%     (a) an argument named after one of the context's symbols, or an alias
%         of one, binds to it, wherever it stands;
%     (b) the other arguments take, left to right, the next unbound symbol in
%         the parameter order below; more arguments than symbols is an error;
%     (c) an argument named after a runtime symbol the context does not
%         provide (kx in dispersion_factor) is an error, never rebound;
%     (d) two arguments resolving to one symbol are an error;
%     (e) w and wt are one symbol in the linear contexts, emitted in the
%         context's own spelling;
%     (f) runtime symbols enter only through arguments: a free name in the
%         body is a captured constant, whatever it is called.
%
%     context              parameters                          alias
%     "dispersion_factor"  @(A, w)                             wt = w
%     "dispersion"         @(A, D, h, w, V)                    wt = w
%     "linear_factor"      @(A, wt, kx, ky, x, y, t)           w = wt
%     "linear"             @(A, D, h, wt, kx, ky, x, y, t, V)  w = wt
%     "potential"          @(x, y, t)
%     "nonlinear"          @(A, I, V)
%
%   The body must be a single expression. Element-wise operators are
%   normalised (.* -> *, .^ -> ^, ./ -> /) and imaginary literals (1i, 0.5j)
%   become multiples of i. Any identifier that is not an argument, apart
%   from the intrinsics exp, log, sqrt, sin and cos and the unit i, is a real
%   scalar constant: the value in bindings (a struct
%   or containers.Map, the constant_bindings option) when it names one,
%   otherwise the value the handle captured from its workspace. constants(k)
%   is referenced as c<k-1>.
%
%   Every failure is nlolib:invalidOperator.
if ~isa(fn, 'function_handle')
    error('nlolib:invalidOperator', ...
          '%s operator must be a function handle, got %s. Pass e.g. @(A, w) 1i * beta2 * w.^2.', ...
          context, class(fn));
end
context = char(context);
switch context
    case 'dispersion_factor'
        params = {'A', 'w'};
        aliases = struct('wt', 'w');
    case 'dispersion'
        params = {'A', 'D', 'h', 'w', 'V'};
        aliases = struct('wt', 'w');
    case 'linear_factor'
        params = {'A', 'wt', 'kx', 'ky', 'x', 'y', 't'};
        aliases = struct('w', 'wt');
    case 'linear'
        params = {'A', 'D', 'h', 'wt', 'kx', 'ky', 'x', 'y', 't', 'V'};
        aliases = struct('w', 'wt');
    case 'potential'
        params = {'x', 'y', 't'};
        aliases = struct();
    case 'nonlinear'
        params = {'A', 'I', 'V'};
        aliases = struct();
    otherwise
        error('nlolib:invalidOperator', 'unknown operator context "%s"', context);
end
allSymbols = {'A', 'I', 'D', 'V', 'h', 'w', 'wt', 'kx', 'ky', 'x', 'y', 't'};
if nargin < 3 || isempty(bindings)
    bindings = struct();
end

handleText = char(func2str(fn));
[argNames, body] = parse_handle_text(handleText, context);
if numel(argNames) < 1 || numel(argNames) > numel(params)
    error('nlolib:invalidOperator', ...
          '%s operator must take 1 to %d arguments (%s).', ...
          context, numel(params), strjoin(params, ', '));
end

% Arguments named after a symbol (or an alias of one) bind to it first; the
% others then take the unused symbols in parameter order, so @(B, A) binds A
% to A and B to the next symbol.
symbolMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
used = false(1, numel(params));
for idx = 1:numel(argNames)
    name = argNames{idx};
    target = name;
    if isfield(aliases, name)
        target = aliases.(name);
    end
    hit = find(strcmp(params, target), 1);
    if isempty(hit)
        if ismember(name, allSymbols)
            error('nlolib:invalidOperator', ...
                  '%s operator: ''%s'' is a runtime symbol %s operators do not have; they take %s.', ...
                  context, name, context, strjoin(params, ', '));
        end
        continue;
    end
    if used(hit)
        % e.g. @(A, w, wt) in a tensor run, where w is wt. Binding the second
        % one elsewhere would silently rename every later argument.
        error('nlolib:invalidOperator', ...
              '%s operator: arguments ''%s'' and ''%s'' both name %s.', ...
              context, symbol_owner(symbolMap, target), name, target);
    end
    symbolMap(name) = target;
    used(hit) = true;
end
for idx = 1:numel(argNames)
    name = argNames{idx};
    if ~isKey(symbolMap, name)
        hit = find(~used, 1);
        symbolMap(name) = params{hit};
        used(hit) = true;
    end
end

body = strrep(body, ".^", "^");
body = strrep(body, ".*", "*");
body = strrep(body, "./", "/");
% Imaginary literals: 1i / 1.0j -> i, other magnitudes -> (k*i). MATLAB
% double-quoted strings do not process escapes, so single backslashes here.
body = regexprep(body, "(?<![A-Za-z0-9_.])1(\.0+)?[iIjJ]\>", "i");
body = regexprep(body, "(?<![A-Za-z0-9_.])(\d+\.?\d*([eE][+-]?\d+)?)[iIjJ]\>", "($1*i)");

workspaceScope = resolve_workspace_scope(fn);
constants = [];
constantsByName = containers.Map('KeyType', 'char', 'ValueType', 'double');
function token = addConstant(key, value)
    if isKey(constantsByName, key)
        idxLocal = constantsByName(key);
    else
        idxLocal = numel(constants);
        constantsByName(key) = idxLocal;
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
    if ismember(name, {'i', 'exp', 'log', 'sqrt', 'sin', 'cos'})
        continue;
    end

    [hasBinding, value] = lookup_binding(bindings, name);
    if hasBinding
        names{idx} = addConstant(['binding:' name], real_constant(value, name, 'constant_bindings'));
        continue;
    end
    if isfield(workspaceScope, name)
        names{idx} = addConstant(name, real_constant(workspaceScope.(name), name, 'captured'));
        continue;
    end
    error('nlolib:invalidOperator', ...
          'unknown identifier ''%s'' in the %s operator; define it before the handle or pass it in constant_bindings.', ...
          name, context);
end

pieces = [gaps; [names, {''}]];
expression = char(strjoin(pieces(:).', ''));
end

function name = symbol_owner(symbolMap, symbol)
names = keys(symbolMap);
name = names{find(strcmp(values(symbolMap), symbol), 1)};
end

function [argNames, body] = parse_handle_text(text, context)
tokens = regexp(text, '^@\(([^)]*)\)\s*(.+)$', 'tokens', 'once');
if isempty(tokens)
    error('nlolib:invalidOperator', ...
          '%s operator must be an anonymous function such as @(A, w) ..., got %s.', context, text);
end
argNames = strtrim(strsplit(tokens{1}, ','));
argNames = argNames(~cellfun(@isempty, argNames));
body = strtrim(tokens{2});
end

function value = real_constant(value, name, source)
if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
    error('nlolib:invalidOperator', ...
          '%s constant ''%s'' must be a finite real scalar.', source, name);
end
value = double(value);
end

function scope = resolve_workspace_scope(fn)
scope = struct();
try
    info = functions(fn);
catch
    return;
end
if ~isfield(info, 'workspace') || isempty(info.workspace)
    return;
end
workspace = info.workspace;
if iscell(workspace)
    for idx = 1:numel(workspace)
        if isstruct(workspace{idx})
            scope = merge_structs(scope, workspace{idx});
        end
    end
elseif isstruct(workspace)
    scope = merge_structs(scope, workspace);
end
end

function out = merge_structs(base, extra)
out = base;
names = fieldnames(extra);
for idx = 1:numel(names)
    out.(names{idx}) = extra.(names{idx});
end
end

function [found, value] = lookup_binding(bindings, name)
found = false;
value = [];
if isa(bindings, 'containers.Map')
    if isKey(bindings, name)
        found = true;
        value = bindings(name);
    end
elseif isstruct(bindings) && isfield(bindings, name)
    found = true;
    value = bindings.(name);
end
end
