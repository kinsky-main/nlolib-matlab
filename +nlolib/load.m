function load(path)
%LOAD Load the nlolib shared library.
%   nlolib.load()        find the library (NLOLIB_LIBRARY, then the toolbox
%                        and build-tree locations, newest first)
%   nlolib.load(path)    load the library at path
%
%   Every other nlolib function loads the library on first use, so calling
%   this is needed only to pick a specific library. If a different library is
%   already loaded it is unloaded first. A staged loadlibrary prototype
%   (nlolib_proto.m and its thunk) is preferred, since it needs no C
%   compiler; the nlolib_matlab.h header is the fallback.
%
%   Raises nlolib:libraryLoadFailed when no candidate loads.
%
%   See also NLOLIB.UNLOAD, NLOLIB.LOADED_LIBRARY_PATH.
arguments
    path = ""
end
path = string(path);
if strlength(path) > 0 && ~isfile(path)
    error('nlolib:libraryLoadFailed', 'no shared library at %s', path);
end
if libisloaded('nlolib')
    if strlength(path) == 0 || strcmp(char(path), library_state("path"))
        return;
    end
    nlolib.unload();
end

interfaces = resolve_interfaces();
candidates = resolve_library_candidates(path);
loadErrors = strings(0, 1);
for kdx = 1:numel(interfaces)
    spec = interfaces{kdx};
    for idx = 1:numel(candidates)
        dllPath = candidates{idx};
        try
            prepend_library_dir_to_path(dllPath);
            [notfound, loadWarnings] = loadlibrary(dllPath, spec.arg, 'alias', 'nlolib');
            validate_load_result(notfound, loadWarnings, dllPath, spec.description);
            library_state("path", char(dllPath));
            ensure_types_loaded();
            return;
        catch ME
            loadErrors(end + 1, 1) = string(dllPath) + " [" + ...
                string(spec.description) + "] -> " + string(ME.message); %#ok<AGROW>
            if libisloaded('nlolib')
                unloadlibrary('nlolib');
            end
            library_state("path", '');
        end
    end
end
error('nlolib:libraryLoadFailed', 'Failed to load nlolib from candidates:\n  %s', ...
      strjoin(cellstr(loadErrors), '\n  '));
end

function interfaces = resolve_interfaces()
% A staged prototype is preferred: loadlibrary consumes it directly and never
% parses a header, the only step that needs a C compiler. The header is the
% fallback for build trees without a prototype, or a stale one.
interfaces = {};
protoFcn = resolve_prototype();
if ~isempty(protoFcn)
    interfaces{end + 1} = struct('arg', protoFcn, ...
                                 'description', 'prototype nlolib_proto (no compiler needed)');
end
headerPath = resolve_header();
if ~isempty(headerPath)
    interfaces{end + 1} = struct('arg', headerPath, ...
                                 'description', ['header ' headerPath ' (needs a C compiler)']);
end
if isempty(interfaces)
    error('nlolib:libraryLoadFailed', ...
          'Cannot locate nlolib_proto.m or nlolib_matlab.h next to the nlolib package.');
end
end

function protoFcn = resolve_prototype()
% A prototype resolves its thunk relative to its own folder, so one without a
% thunk for this architecture is skipped.
protoFcn = [];
roots = resolve_roots();
candidates = {};
for idx = 1:numel(roots)
    root = roots{idx};
    candidates{end + 1} = fullfile(root, 'lib', computer('arch'), 'nlolib_proto.m'); %#ok<AGROW>
    candidates{end + 1} = fullfile(root, 'nlolib_proto.m'); %#ok<AGROW>
    candidates{end + 1} = fullfile(root, 'lib', 'nlolib_proto.m'); %#ok<AGROW>
    candidates{end + 1} = fullfile(root, 'build', 'matlab_toolbox', 'nlolib_proto.m'); %#ok<AGROW>
end
candidates = unique(candidates, 'stable');
% MATLAB names the thunk 'pcwin64' on Windows, where computer('arch') is 'win64'.
archToken = computer('arch');
if strcmp(archToken, 'win64')
    archToken = 'pcwin64';
end
for idx = 1:numel(candidates)
    protoPath = candidates{idx};
    if ~isfile(protoPath)
        continue;
    end
    protoDir = fileparts(protoPath);
    thunks = dir(fullfile(protoDir, ['nlolib_thunk_' archToken '.*']));
    if isempty(thunks(~[thunks.isdir]))
        continue;
    end
    addpath(protoDir);
    protoFcn = str2func('nlolib_proto');
    return;
end
end

function headerPath = resolve_header()
headerPath = '';
roots = resolve_roots();
for idx = 1:numel(roots)
    root = roots{idx};
    % A standalone checkout of this repository keeps the core sources in
    % ./core (tools/fetch_core.sh).
    candidates = {fullfile(root, 'lib', 'nlolib_matlab.h'), ...
                  fullfile(root, 'src', 'nlolib_matlab.h'), ...
                  fullfile(root, 'core', 'src', 'nlolib_matlab.h'), ...
                  fullfile(root, 'build', 'matlab_toolbox', 'lib', 'nlolib_matlab.h')};
    for jdx = 1:numel(candidates)
        if isfile(candidates{jdx})
            headerPath = candidates{jdx};
            return;
        end
    end
end
end

function candidates = resolve_library_candidates(userPath)
if strlength(userPath) > 0
    candidates = {char(userPath)};
    return;
end
envPath = getenv('NLOLIB_LIBRARY');
if ~isempty(envPath) && isfile(envPath)
    candidates = {envPath};
    return;
end

if ispc
    libFile = 'nlolib.dll';
    searchTail = {fullfile('lib', 'win64'), 'lib', fullfile('build', 'matlab_toolbox', 'lib', 'win64'), ...
                  fullfile('build', 'matlab_toolbox', 'lib'), ...
                  fullfile('build', 'src', 'Release'), fullfile('build', 'src', 'Debug'), ...
                  fullfile('build', 'src', 'RelWithDebInfo'), fullfile('build', 'src'), ...
                  fullfile('src', 'Release'), fullfile('src', 'Debug'), ...
                  fullfile('src', 'RelWithDebInfo'), 'src', ...
                  fullfile('python', 'Release'), fullfile('python', 'Debug'), 'python'};
elseif ismac
    libFile = 'libnlolib.dylib';
    searchTail = {fullfile('lib', 'maci64'), 'lib', fullfile('build', 'matlab_toolbox', 'lib', 'maci64'), ...
                  fullfile('build', 'matlab_toolbox', 'lib'), ...
                  fullfile('build', 'src'), 'src', 'python'};
else
    libFile = 'libnlolib.so';
    searchTail = {fullfile('lib', 'glnxa64'), 'lib', fullfile('build', 'matlab_toolbox', 'lib', 'glnxa64'), ...
                  fullfile('build', 'matlab_toolbox', 'lib'), ...
                  fullfile('build', 'src'), 'src', 'python'};
end

roots = resolve_roots();
foundPaths = {};
foundDatenum = [];
for idx = 1:numel(roots)
    for jdx = 1:numel(searchTail)
        candidate = fullfile(roots{idx}, searchTail{jdx}, libFile);
        if isfile(candidate) && ~ismember(candidate, foundPaths)
            info = dir(candidate);
            foundPaths{end + 1} = candidate; %#ok<AGROW>
            foundDatenum(end + 1) = info.datenum; %#ok<AGROW>
        end
    end
end
if isempty(foundPaths)
    error('nlolib:libraryLoadFailed', ...
          'Cannot locate %s. Set NLOLIB_LIBRARY or call nlolib.load(path).', libFile);
end
[~, order] = sort(foundDatenum, 'descend');
candidates = foundPaths(order);
end

function roots = resolve_roots()
% Candidate roots for the source and the staged toolbox layouts.
packageDir = fileparts(mfilename("fullpath"));     % .../+nlolib
containerDir = fileparts(packageDir);              % .../matlab OR .../matlab_toolbox
parentDir = fileparts(containerDir);               % repo root OR .../build
[~, leaf] = fileparts(containerDir);
if strcmpi(leaf, 'matlab_toolbox')
    roots = unique({containerDir, parentDir, fileparts(parentDir)}, 'stable');
elseif strcmpi(leaf, 'matlab')
    roots = unique({parentDir, containerDir}, 'stable');
else
    roots = unique({containerDir, parentDir}, 'stable');
end
end

function prepend_library_dir_to_path(dllPath)
% Windows resolves the DLL's own dependencies through PATH.
if ~ispc
    return;
end
dllDir = fileparts(char(string(dllPath)));
if isempty(dllDir) || ~isfolder(dllDir)
    return;
end
currentPath = string(getenv('PATH'));
if any(lower(strtrim(split(currentPath, ';'))) == lower(string(dllDir)))
    return;
end
setenv('PATH', char(strjoin([string(dllDir), currentPath(strlength(currentPath) > 0)], ';')));
end

function validate_load_result(notfound, loadWarnings, dllPath, interfaceDescription)
if ~isempty(notfound)
    error('nlolib:libraryLoadFailed', ...
          ['loadlibrary could not resolve one or more symbols.\n' ...
           'Library  : %s\nInterface: %s\nMissing symbols:\n%s'], ...
          dllPath, interfaceDescription, char(join(string(notfound), newline)));
end
warningText = strtrim(char(join(string(loadWarnings), newline)));
if ~isempty(warningText)
    warning('%s', sprintf(['nlolib: loadlibrary produced parser warnings. These are ' ...
                           'often non-fatal; unresolved types fail fast later.\n' ...
                           'Library  : %s\nInterface: %s\n\n%s'], ...
                          dllPath, interfaceDescription, warningText));
end
end
