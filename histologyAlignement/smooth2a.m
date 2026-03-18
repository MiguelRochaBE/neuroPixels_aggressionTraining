function Z = smooth2a(X, k)
%SMOOTH2A Simple 2D moving-average smoothing (NaN-aware)
%   Z = smooth2a(X, k) smooths X using a (2k+1)-by-(2k+1) box filter.
%   NaNs are ignored (do not contaminate neighbors).

if nargin < 2 || isempty(k)
    k = 1;
end
k = round(k);
if k < 0
    error('k must be >= 0');
end
if k == 0
    Z = X;
    return;
end

X = double(X);

% Build box kernel
w = ones(2*k+1, 2*k+1);

% NaN-aware convolution: convolve data and a validity mask separately
mask = ~isnan(X);
X0 = X;
X0(~mask) = 0;

num = conv2(X0, w, 'same');
den = conv2(double(mask), w, 'same');

Z = num ./ den;
Z(den == 0) = NaN;
end