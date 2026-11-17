function volume = tensor_record_view(record, nt, nx, ny)
%TENSOR_RECORD_VIEW Reshape one tensor-run record into an (nt, ny, nx) volume.
%   volume = nlolib.tensor_record_view(record, nt, nx, ny)
%
%   A tensor (t, x, y) propagation returns each record as one flat row of
%   nt*nx*ny samples, t fastest, then y, then x. This reshapes one such row
%   into a 3-D array indexed as volume(it, iy, ix).
%
%   Example:
%     result = nlolib.propagate(pulse, linearOp, nonlinearOp, ...
%                               propagation_distance=1.0, num_records=8);
%     final = nlolib.tensor_record_view(result.final, nt, nx, ny);
%     imagesc(abs(squeeze(final(ceil(nt / 2), :, :))).^2);
%
%   See also NLOLIB.PROPAGATE.
arguments
    record
    nt
    nx
    ny
end
nt = count_option(nt, 'nt', 1);
nx = count_option(nx, 'nx', 1);
ny = count_option(ny, 'ny', 1);
if ~isnumeric(record) || ~(isvector(record) || isempty(record))
    error('nlolib:invalidOption', ...
          'record must be one record, a vector; index result.records(k, :) first.');
end
expected = nt * ny * nx;
if numel(record) ~= expected
    error('nlolib:invalidOption', ...
          'record has %d samples but nt*nx*ny is %d.', numel(record), expected);
end
% Column-major reshape puts t fastest, then y, then x, matching the layout the
% solver wrote.
volume = reshape(record, nt, ny, nx);
end
