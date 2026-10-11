% This script analyzes shoreline change at Buffalo beach by loading transect
% data, estimating historical erosion/accretion trends, quantifying seasonal
% and interannual variability, evaluating sensitivity to sea-level rise, and
% projecting future shoreline position under multiple SLR scenarios.

%% Load Buffalo shoreline dataset
% read the shoreline intersection measurements
% each row is a survey date and each column after the first represents a
% transect shoreline position (m) for that date
s = readmatrix('nzd0176.xlsx', 'Sheet', 'Intersects', 'Range', 'B2:AQ339');

% read the survey dates as text from the first column.
t1 = readtable('nzd0176.xlsx', 'Sheet', 'Intersects', 'Range', 'A2:A339', ...
    'ReadVariableNames', false);

% convert the date strings into MATLAB serial date numbers so they can be
% plotted and converted to datetime later
t = zeros(338, 1);

for j = 1:338
    q = t1.Var1{j};          % Date string for the j th survey
    t(j) = datenum( ...
        str2double(q(1:4)), ...   % year
        str2double(q(6:7)), ...   % month
        str2double(q(9:10)));     % day
end

%% Plot shoreline position for the first transect
% this is a quick visual check of how shoreline position changes through time
% for transect 1.
hold off
plot(t, s(:, 1), 'o-')

datetick('x', 'yyyy')
xlabel('Year')
ylabel('Shoreline Position (m)')
title('Buffalo Shoreline Position')
grid on

%% Historical shoreline change trends
% convert the date vector to datetime for easier time-based calculations.
dt = datetime(t, 'ConvertFrom', 'datenum');

% convert dates to decimal years so linear regression slope is in m/yr.
years = year(dt) + (day(dt, 'dayofyear') - 1) ./ 365;

% number of transects in the dataset
ntran = size(s, 2);

% create transect labels like T1, T2, ...
transects = arrayfun(@(x) sprintf('T%d', x), (1:ntran)', 'UniformOutput', false);

% preallocate arrays for regression results
rate = nan(ntran, 1);        % trend slope for each transect (m/yr)
rateSE = nan(ntran, 1);      % standard error of the slope
rateCI = nan(ntran, 2);      % 95% confidence interval for slope
intercept = nan(ntran, 1);   % regression intercept
R2 = nan(ntran, 1);          % coefficient of determination

% fit a robust linear model to each transect to estimate long-term change.
for k = 1:ntran
    y = s(:, k);
    idx = ~isnan(y) & ~isnan(years);   % use only valid shoreline observations

    % require enough data points to fit a meaningful line
    if nnz(idx) > 2
        mdl = fitlm(years(idx), y(idx), 'RobustOpts', 'on');

        % store regression outputs for later summary and plotting
        intercept(k) = mdl.Coefficients.Estimate(1);
        rate(k) = mdl.Coefficients.Estimate(2);
        rateSE(k) = mdl.Coefficients.SE(2);

        % confidence interval for the slope term only
        ci = coefCI(mdl);
        rateCI(k, :) = ci(2, :);

        % R^2 for goodness-of-fit reporting
        R2(k) = mdl.Rsquared.Ordinary;
    end
end

% identify the most erosive and least erosive transects from the fitted 
% trends
validRate = ~isnan(rate);
validRateIdx = find(validRate);

[~, iMostEroded] = min(rate(validRate));
[~, iLeastEroded] = max(rate(validRate));

mostEroded = validRateIdx(iMostEroded);
leastEroded = validRateIdx(iLeastEroded);

% print summary statistics for the historical trend analysis
fprintf('Mean shoreline trend = %.3f m/yr\n', mean(rate, 'omitnan'));
fprintf('Maximum accretion = %.3f m/yr\n', max(rate, [], 'omitnan'));
fprintf('Maximum erosion = %.3f m/yr\n', min(rate, [], 'omitnan'));
fprintf('Most eroded transect: %d\n', mostEroded);
fprintf('Least eroded transect: %d\n', leastEroded);

% plot the slope for each transect with its 95% confidence interval.
figure
bar(rate)
hold on

valid = ~isnan(rate);
errorbar(find(valid), rate(valid), ...
    rate(valid) - rateCI(valid, 1), ...
    rateCI(valid, 2) - rate(valid), ...
    'k.', 'LineWidth', 1)

xlabel('Transect')
ylabel('Rate (m yr^{-1})')
title('Historical Shoreline Change Trends with 95% CI')
grid on

%% Seasonal variability for all transects
% group observations by month to see how shoreline position changes within
% a year
monthNum = month(dt);

% seasonalMean(m, k) = mean shoreline position for month m at transect k.
seasonalMean = nan(12, ntran);

% seasonalRange(k) = range of monthly mean shoreline positions for 
% transect k
seasonalRange = nan(ntran, 1);

for k = 1:ntran
    for m = 1:12
        seasonalMean(m, k) = mean(s(monthNum == m, k), 'omitnan');
    end

    % Larger range means stronger within-year seasonal fluctuation.
    seasonalRange(k) = ...
        max(seasonalMean(:, k), [], 'omitnan') - ...
        min(seasonalMean(:, k), [], 'omitnan');
end

% plot seasonal variability across transects
figure
bar(seasonalRange)
xlabel('Transect')
ylabel('Seasonal Range (m)')
title('Seasonal Variability')
grid on

%% Inter-annual variability for all transects
% group data by year and compute annual mean shoreline position for 
% each transect
yr = year(dt);
uyr = unique(yr);

% annualMean(i, k) = mean shoreline position for year uyr(i) at transect k
annualMean = nan(length(uyr), ntran);

for i = 1:length(uyr)
    ind = (yr == uyr(i));
    annualMean(i, :) = mean(s(ind, :), 1, 'omitnan');
end

% Interannual range and spread across yearly means.
interannualRange = ...
    max(annualMean, [], 1, 'omitnan') - ...
    min(annualMean, [], 1, 'omitnan');

% Compute the standard deviation of annual mean shoreline positions for 
% each transect as an additional measure of interannual variability.

interannualSTD = std(annualMean, 0, 1, 'omitnan');

% plot interannual variability across transects
figure
bar(interannualRange)
xlabel('Transect')
ylabel('Range (m)')
title('Interannual Variability')
grid on

%% Shoreline sensitivity to sea-level rise
% Read beach slope metadata for each transect.
Tr = readtable('nzd0176.xlsx', 'Sheet', 'Transects');
tanBeta = Tr.beach_slope;   % beach slope used in the Bruun-rule-style
% estimate

% check that slope metadata and shoreline data have compatible dimensions
fprintf('Number of slopes = %d\n', length(tanBeta));
fprintf('Number of transects = %d\n', ntran);

% remove non-physical or invalid slope values before computing sensitivity.
tanBeta(tanBeta <= 0) = NaN;

% Bruun sensitivity:
% sensitivity = shoreline retreat per unit sea-level rise (m/m).
sensitivity = 1 ./ tanBeta;

% summary statistics for the sensitivity distribution
fprintf('\nBruun sensitivity statistics:\n')
fprintf('Mean = %.2f\n', mean(sensitivity, 'omitnan'))
fprintf('Min  = %.2f\n', min(sensitivity))
fprintf('Max  = %.2f\n', max(sensitivity))

% plot sensitivity for all transects
figure
bar(sensitivity)
xlabel('Transect')
ylabel('Sensitivity (m retreat per m SLR)')
title('Transect-Specific Bruun Sensitivity')
grid on

% rank transects from most sensitive to least sensitive
[sortedSensitivity, I] = sort(sensitivity, 'descend');

SensitivityTable = table( ...
    transects(I), ...
    tanBeta(I), ...
    sortedSensitivity, ...
    'VariableNames', ...
    {'Transect', 'BeachSlope', 'Sensitivity'});

disp(SensitivityTable)

%% Compare sensitivity with historical erosion
% use negative rate so larger values mean stronger erosion
figure
scatter(sensitivity, -rate, 80, 'filled')

xlabel('Sensitivity (m retreat per m SLR)')
ylabel('Historical Erosion Rate (m yr^{-1})')
title('Historical Erosion versus SLR Sensitivity')
grid on

% quantify the relationship with Pearson correlation.
[r, p] = corr(sensitivity, ...
    -rate, ...
    'Rows', 'complete', ...
    'Type', 'Pearson');

fprintf('\nSensitivity-Erosion Correlation\n')
fprintf('r = %.3f\n', r)
fprintf('p = %.4f\n', p)

%% Projection of future erosion under SLR scenarios
% Project shoreline position for three time horizons and three 
% sea-level rise
% scenarios (p17, p50, p83).
futureYears = [2050 2100 2150];

slrP17 = [0.11 0.36 0.66];
slrP50 = [0.28 0.71 1.23];
slrP83 = [0.45 1.08 1.84];

projectedP17 = nan(ntran, numel(futureYears));
projectedP50 = nan(ntran, numel(futureYears));
projectedP83 = nan(ntran, numel(futureYears));

% combine the historical linear trend with the SLR adjustment for each 
% transect
for k = 1:ntran
    B = tanBeta(k);

    if isnan(B) || isnan(rate(k)) || isnan(intercept(k))
        continue
    end

    for j = 1:numel(futureYears)
        % historical trend projection at the target year
        trendFuture = polyval([rate(k) intercept(k)], futureYears(j));

        % apply the sensitivity-based retreat adjustment for each SLR 
        % scenario
        projectedP17(k, j) = trendFuture - slrP17(j) / B;
        projectedP50(k, j) = trendFuture - slrP50(j) / B;
        projectedP83(k, j) = trendFuture - slrP83(j) / B;
    end
end

% select transects for the 4-panel summary:
% 1) most eroded, 2) least eroded, 3) most sensitive, 4) least sensitive
validRate = ~isnan(rate);
validRateIdx = find(validRate);
[~, iMostEroded] = min(rate(validRate));
[~, iLeastEroded] = max(rate(validRate));
mostEroded = validRateIdx(iMostEroded);
leastEroded = validRateIdx(iLeastEroded);

validSens = ~isnan(sensitivity);
validSensIdx = find(validSens);
[~, iMostSensitive] = max(sensitivity(validSens));
[~, iLeastSensitive] = min(sensitivity(validSens));
mostSensitive = validSensIdx(iMostSensitive);
leastSensitive = validSensIdx(iLeastSensitive);

transectList = [mostEroded, leastEroded, mostSensitive, leastSensitive];
panelNames = {'Most Eroded', 'Least Eroded', 'Most Sensitive', 'Least Sensitive'};

% define consistent colors for historical data, trend line, and projection
% band
bandColor = [1.0 0.6 0.6];
histColor = [0.0 0.45 0.74];
projColor = [0.85 0.0 0.0];

% use common y-limits across all panels so the four subplots are comparable
yMin = inf;
yMax = -inf;

for n = 1:numel(transectList)
    k = transectList(n);

    yMin = min(yMin, min(s(:, k), [], 'omitnan'));
    yMax = max(yMax, max(s(:, k), [], 'omitnan'));
    yMin = min(yMin, min(projectedP17(k, :), [], 'omitnan'));
    yMax = max(yMax, max(projectedP83(k, :), [], 'omitnan'));
end

if isfinite(yMin) && isfinite(yMax)
    pad = 0.05 * (yMax - yMin);
    if pad == 0
        pad = 1;
    end
    yLimits = [yMin - pad, yMax + pad];
else
    yLimits = [0 1];
end

% create the 2x2 summary figure
figure
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact')

ax = gobjects(1, numel(transectList));

for n = 1:numel(transectList)
    k = transectList(n);

    ax(n) = nexttile;
    hold on

    % historical observations.
    hObs = plot(years, s(:, k), '.', ...
        'Color', [0.7 0.7 0.7], ...
        'MarkerSize', 10, ...
        'DisplayName', 'Historical observations');

    % historical linear trend fitted from the survey record
    xHist = linspace(min(years), max(years), 500);
    yHist = polyval([rate(k) intercept(k)], xHist);

    hTrend = plot(xHist, yHist, '-', ...
        'Color', histColor, ...
        'LineWidth', 2, ...
        'DisplayName', 'Historical trend');

    % use the historical trend at the last observed year as the 
    % starting point for the future projection curves

    trendPresent = polyval([rate(k) intercept(k)], max(years));

    xProj = [max(years) futureYears];
    xFine = linspace(max(years), futureYears(end), 400);

    y17 = [trendPresent projectedP17(k, :)];
    y50 = [trendPresent projectedP50(k, :)];
    y83 = [trendPresent projectedP83(k, :)];

    % interpolate the discrete projection points to create smooth curves
    y17Fine = interp1(xProj, y17, xFine, 'linear');
    y50Fine = interp1(xProj, y50, xFine, 'linear');
    y83Fine = interp1(xProj, y83, xFine, 'linear');

    % shade the uncertainty envelope between p17 and p83
    hBand = fill([xFine fliplr(xFine)], ...
        [y17Fine fliplr(y83Fine)], ...
        bandColor, ...
        'FaceAlpha', 0.18, ...
        'EdgeColor', 'none', ...
        'DisplayName', 'p17-p83 uncertainty');

    % plot the median projection
    hP50 = plot(xFine, y50Fine, '-', ...
        'Color', projColor, ...
        'LineWidth', 2, ...
        'DisplayName', 'p50 projection');

    % mark the scenario values at the target years.
    plot(futureYears, projectedP50(k, :), 'o', ...
        'Color', projColor, ...
        'MarkerFaceColor', projColor, ...
        'HandleVisibility', 'off')

    % annotate the projection spread at each target year
    for j = 1:numel(futureYears)
        if ~isnan(projectedP17(k, j)) && ~isnan(projectedP50(k, j)) && ~isnan(projectedP83(k, j))
            text(futureYears(j), projectedP83(k, j), ...
                sprintf('  +%.2f/-%.2f', ...
                projectedP83(k, j) - projectedP50(k, j), ...
                projectedP50(k, j) - projectedP17(k, j)), ...
                'Color', projColor, ...
                'FontSize', 8, ...
                'VerticalAlignment', 'bottom');
        end
    end

    xlabel('Year')
    ylabel('Shoreline Position (m)')
    title(sprintf('Transect %d (%s) - %s', k, transects{k}, panelNames{n}))

    legend([hObs hTrend hBand hP50], 'Location', 'best')
    grid on
    box on
    xlim([min(years) 2150])
    ylim(yLimits)
end

% link y-axes so the four panels share the same vertical scale
linkaxes(ax, 'y')
sgtitle('Future Projections')
