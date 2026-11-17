function err = relative_l2_intensity_error(prediction, reference)
%RELATIVE_L2_INTENSITY_ERROR || |pred|^2 - |ref|^2 ||_2 / || |ref|^2 ||_2.
%   The same metric as the Python examples' backend.metrics helper.
if ~isequal(size(prediction), size(reference))
    error('prediction and reference must have the same size.');
end
predIntensity = abs(prediction(:)).^2;
refIntensity = abs(reference(:)).^2;
refNorm = norm(refIntensity);
if ~isfinite(refNorm) || refNorm <= 0
    err = NaN;
    return;
end
err = norm(predIntensity - refIntensity) / refNorm;
end
