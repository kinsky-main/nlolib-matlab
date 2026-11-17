function value = count_option(value, optionName, minimum)
%COUNT_OPTION Check a whole-number option and return it as a double.
%   value = count_option(value, optionName, minimum)
%
%   Private. Raises nlolib:invalidOption unless value is a real integer scalar
%   of at least minimum.
if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && ...
        double(value) == floor(double(value)) && double(value) >= minimum)
    error('nlolib:invalidOption', '%s must be an integer >= %d.', optionName, minimum);
end
value = double(value);
end
