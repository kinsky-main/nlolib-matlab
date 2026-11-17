function value = logical_option(value, optionName)
%LOGICAL_OPTION Check a true/false option and return it as a logical scalar.
%   Private. Raises nlolib:invalidOption.
if ~((islogical(value) || isnumeric(value)) && isscalar(value) && isreal(value) && ...
        ~isnan(double(value)))
    error('nlolib:invalidOption', '%s must be true or false.', optionName);
end
value = logical(value);
end
