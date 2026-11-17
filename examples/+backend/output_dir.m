function dirPath = output_dir(exampleName)
%OUTPUT_DIR Folder for one example's plots: examples/output/<exampleName>.
%   Created when missing. NLOLIB_EXAMPLE_OUTPUT overrides the parent folder.
root = getenv('NLOLIB_EXAMPLE_OUTPUT');
if isempty(root)
    root = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'output');
end
dirPath = fullfile(root, char(exampleName));
if ~isfolder(dirPath)
    mkdir(dirPath);
end
end
