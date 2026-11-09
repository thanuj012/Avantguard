% ============================================
% Avantguard — Runtime Health Monitor
% runtime.m
% ============================================

fs           = 2000;
N            = 512;
winSize      = 128;
overlap      = 64;
hop          = winSize - overlap;
f0           = 50;
numHarmonics = 10;
masterFile   = 'avantguard_baselines.csv';
faultLog     = 'fault_log.csv';

% Fault detection thresholds
warningThreshold  = 15;   % % drift → warning
faultThreshold    = 30;   % % drift → fault
criticalThreshold = 50;   % % drift → critical

hannWin  = 0.5 * (1 - cos(2*pi*(0:winSize-1)/(winSize-1)));
freqAxis = [];

% ============================================
% STEP 1 — Load Master Baseline File
% ============================================
fprintf('============================================\n');
fprintf('      AVANTGUARD — RUNTIME MONITOR          \n');
fprintf('============================================\n\n');

if ~isfile(masterFile)
    error('Master baseline file not found. Run calibrate.m first.');
end

fprintf('Loading baselines from %s...\n', masterFile);

% Read full table as strings to handle mixed types
rawTable  = readtable(masterFile, 'VariableNamingRule', 'preserve');
allNames  = rawTable.Device;
allMetrics = rawTable.Metric;

% Get unique device names
deviceList = unique(allNames, 'stable');
numDevices = length(deviceList);

fprintf('Found %d devices:\n', numDevices);

% Build baseline structs for each device
baselines = struct();
for d = 1:numDevices
    dName = deviceList{d};
    dKey  = matlab.lang.makeValidName(dName);

    meanRow  = rawTable(strcmp(allNames, dName) & strcmp(allMetrics, 'mean'), :);
    stdRow   = rawTable(strcmp(allNames, dName) & strcmp(allMetrics, 'std'),  :);
    upperRow = rawTable(strcmp(allNames, dName) & strcmp(allMetrics, 'upper'),:);
    lowerRow = rawTable(strcmp(allNames, dName) & strcmp(allMetrics, 'lower'),:);

    % Extract harmonic columns (H1_50Hz to H10_500Hz)
    hCols = 3:3+numHarmonics-1;

    baselines.(dKey).name        = dName;
    baselines.(dKey).mean        = table2array(meanRow(1,  hCols));
    baselines.(dKey).std         = table2array(stdRow(1,   hCols));
    baselines.(dKey).upper       = table2array(upperRow(1, hCols));
    baselines.(dKey).lower       = table2array(lowerRow(1, hCols));
    baselines.(dKey).thd         = meanRow.THD;
    baselines.(dKey).rms         = meanRow.RMS_current;
    baselines.(dKey).reliability = meanRow.Reliability_Score;
    baselines.(dKey).failureProb = meanRow.Failure_Prob;
    baselines.(dKey).grade       = meanRow.Grade{1};

    fprintf('  [%d] %-20s | Reliability: %d | Failure prob: %d%% | Grade: %s\n', ...
            d, dName, baselines.(dKey).reliability, ...
            baselines.(dKey).failureProb, baselines.(dKey).grade);
end

% ============================================
% STEP 2 — Create Fault Log if not exists
% ============================================
if ~isfile(faultLog)
    flogID = fopen(faultLog, 'w');
    fprintf(flogID, 'Timestamp,Device,Severity,THD_Baseline,THD_Live,THD_Drift_pct,Harmonic_Pattern,Action\n');
    fclose(flogID);
    fprintf('\nCreated fault log: %s\n', faultLog);
end

% ============================================
% STEP 3 — Connect to ESP8266
% ============================================
fprintf('\nPress Enter to connect to ESP8266...\n');
pause;
comPort = input('Enter COM port (e.g. COM5): ', 's');
s = serialport(strtrim(comPort), 115200);
s.Timeout = 30;
configureTerminator(s, "LF");
flush(s);
fprintf('Connected. Starting live monitoring...\n');
fprintf('Press Ctrl+C to stop.\n\n');

% ============================================
% STEP 4 — Setup Live Plot
% ============================================
figure('Name', 'Avantguard Live Monitor', 'NumberTitle', 'off');

% STFT plot
subplot(2,2,[1 2]);
hSTFT = imagesc([], [], zeros(winSize/2+1, 7));
axis xy;
xlabel('Time (ms)'); ylabel('Frequency (Hz)');
title('Live STFT — Mains Signal');
colorbar; clim([-40 40]);

% Harmonic bar chart
subplot(2,2,3);
hBar = bar(1:numHarmonics, zeros(1,numHarmonics));
xlabel('Harmonic'); ylabel('Amplitude');
title('Live Harmonic Amplitudes');
xticks(1:numHarmonics);
xticklabels(arrayfun(@(h) sprintf('H%d\n%dHz',h,h*f0), 1:numHarmonics, 'UniformOutput', false));
grid on;

% Status text
subplot(2,2,4);
axis off;
hStatus = text(0.05, 0.95, 'Initializing...', ...
    'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'FontSize', 10, 'FontName', 'Courier New');

% ============================================
% STEP 5 — Main Monitoring Loop
% ============================================
cycleNum  = 0;
startTime = tic;

while true
    cycleNum = cycleNum + 1;

    % ---- 5a. Collect samples ----
    data = zeros(1, N);
    for i = 1:N
        line = readline(s);
        data(i) = str2double(line);
    end
    data = data - mean(data);

    % ---- 5b. STFT ----
    numFrames = floor((N - winSize) / hop) + 1;
    numFreqs  = winSize/2 + 1;
    stftMatrix = zeros(numFreqs, numFrames);

    for frame = 1:numFrames
        startIdx  = (frame-1)*hop + 1;
        segment   = data(startIdx : startIdx+winSize-1);
        windowed  = segment .* hannWin;
        fftResult = fft(windowed, winSize);
        stftMatrix(:, frame) = abs(fftResult(1:numFreqs)) * 2 / winSize;
    end

    if isempty(freqAxis)
        freqAxis = (0:numFreqs-1) * (fs/winSize);
    end

    % ---- 5c. Extract mains harmonics ----
    mains_harmonics = zeros(1, numHarmonics);
    for h = 1:numHarmonics
        targetFreq = h * f0;
        [~, binIdx] = min(abs(freqAxis - targetFreq));
        mains_harmonics(h) = mean(stftMatrix(binIdx, :));
    end

    mains_thd = sqrt(sum(mains_harmonics(2:end).^2)) / mains_harmonics(1) * 100;
    mains_rms = mains_harmonics(1);

    % ---- 5d. Identify ON devices ----
    onDevices  = {};
    onKeys     = {};
    totalRMS   = 0;
    dKeys      = fieldnames(baselines);
    tolerance  = 0.10;   % 10% tolerance

    % try all 2^N combinations
    for combo = 1:(2^numDevices - 1)
        comboRMS  = 0;
        comboList = {};
        comboKeys = {};
        for d = 1:numDevices
            if bitand(combo, 2^(d-1))
                dKey     = dKeys{d};
                comboRMS  = comboRMS + baselines.(dKey).rms;
                comboList{end+1} = baselines.(dKey).name;
                comboKeys{end+1} = dKey;
            end
        end
        if abs(comboRMS - mains_rms) / max(mains_rms, 0.01) <= tolerance
            onDevices = comboList;
            onKeys    = comboKeys;
            totalRMS  = comboRMS;
            break;
        end
    end

    if isempty(onDevices)
        onDevices = {'Unknown combination'};
        onKeys    = {};
    end

    % ---- 5e. Build expected mains fingerprint ----
    expected_harmonics = zeros(1, numHarmonics);
    for d = 1:length(onKeys)
        dKey = onKeys{d};
        expected_harmonics = expected_harmonics + baselines.(dKey).mean;
    end

    % ---- 5f. System level residual THD check ----
    residual    = mains_harmonics - expected_harmonics;
    res_thd     = sqrt(sum(residual(2:end).^2)) / max(residual(1), 0.001) * 100;
    systemHealthy = res_thd <= warningThreshold;

    % ---- 5g. Device level scanning (if fault) ----
    faultFound   = false;
    faultMessages = {};

    if ~systemHealthy && ~isempty(onKeys)

        % sort ON devices by failure probability (highest first)
        failProbs = zeros(1, length(onKeys));
        for d = 1:length(onKeys)
            failProbs(d) = baselines.(onKeys{d}).failureProb;
        end
        [~, scanOrder] = sort(failProbs, 'descend');

        for idx = 1:length(scanOrder)
            d    = scanOrder(idx);
            dKey = onKeys{d};
            dName = baselines.(dKey).name;

            % extract device contribution
            otherSum = zeros(1, numHarmonics);
            for od = 1:length(onKeys)
                if od ~= d
                    otherSum = otherSum + baselines.(onKeys{od}).mean;
                end
            end
            deviceContrib = mains_harmonics - otherSum;

            % compare to baseline
            baseline_vec = baselines.(dKey).mean;
            drift_vec    = abs(deviceContrib - baseline_vec);
            drift_pct    = (drift_vec ./ max(baseline_vec, 0.001)) * 100;
            max_drift    = max(drift_pct);
            thd_live     = sqrt(sum(deviceContrib(2:end).^2)) / max(deviceContrib(1), 0.001) * 100;
            thd_drift    = abs(thd_live - baselines.(dKey).thd) / max(baselines.(dKey).thd, 0.001) * 100;

            % harmonic pattern analysis
            pattern = analysePattern(drift_pct, numHarmonics);

            % severity
            if max_drift >= criticalThreshold || thd_drift >= criticalThreshold
                severity = 'CRITICAL';
                action   = 'Immediate inspection required';
                faultFound = true;
            elseif max_drift >= faultThreshold || thd_drift >= faultThreshold
                severity = 'FAULT';
                action   = 'Schedule maintenance soon';
                faultFound = true;
            elseif max_drift >= warningThreshold || thd_drift >= warningThreshold
                severity = 'WARNING';
                action   = 'Monitor closely';
                faultFound = true;
            else
                severity = 'HEALTHY';
                action   = 'No action needed';
            end

            if ~strcmp(severity, 'HEALTHY')
                msg = sprintf('[%s] %s | Drift: %.1f%% | THD drift: %.1f%% | %s | %s', ...
                              severity, dName, max_drift, thd_drift, pattern, action);
                faultMessages{end+1} = msg;

                % write to fault log
                flogID = fopen(faultLog, 'a');
                fprintf(flogID, '%s,%s,%s,%.2f,%.2f,%.2f,%s,%s\n', ...
                        datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                        dName, severity, ...
                        baselines.(dKey).thd, thd_live, thd_drift, ...
                        pattern, action);
                fclose(flogID);
            end
        end

        % multiple fault check
        if length(faultMessages) > 1
            faultMessages{end+1} = 'WARNING: Multiple devices showing anomalies — physical inspection recommended';
        end
    end

    % ---- 5h. Update plots ----
    timeAxis = ((0:numFrames-1) * hop) / fs * 1000;
    fqAxis   = (0:numFreqs-1) * (fs/winSize);

    subplot(2,2,[1 2]);
    set(hSTFT, 'CData', 20*log10(stftMatrix + 1e-6), ...
               'XData', timeAxis, 'YData', fqAxis);
    ylim([0 600]);
    title(sprintf('Live STFT | Cycle %d | Mains THD: %.1f%%', cycleNum, mains_thd));

    subplot(2,2,3);
    set(hBar, 'YData', mains_harmonics);
    title(sprintf('Mains Harmonics | RMS: %.3f', mains_rms));

    % status panel
    onStr = strjoin(onDevices, ', ');
    if isempty(faultMessages)
        statusColor = [0 0.5 0];
        statusStr   = sprintf('Cycle: %d\nTime:  %.1fs\n\nON Devices:\n  %s\n\nSystem THD: %.1f%%\nResidual:   %.1f%%\n\nStatus: ALL HEALTHY', ...
                              cycleNum, toc(startTime), onStr, mains_thd, res_thd);
    else
        statusColor = [0.8 0 0];
        faultStr    = strjoin(faultMessages, '\n');
        statusStr   = sprintf('Cycle: %d\nTime:  %.1fs\n\nON Devices:\n  %s\n\nSystem THD: %.1f%%\nResidual:   %.1f%%\n\nFAULT DETECTED:\n%s', ...
                              cycleNum, toc(startTime), onStr, mains_thd, res_thd, faultStr);
    end

    subplot(2,2,4);
    set(hStatus, 'String', statusStr, 'Color', statusColor);
    drawnow;

    % ---- 5i. Popup alert for fault ----
    if faultFound
        alertMsg = strjoin(faultMessages, newline);
        uiwait(msgbox(alertMsg, 'AVANTGUARD FAULT ALERT', 'error'));
    end

end

clear s;

% ============================================
% Helper — Harmonic Pattern Analysis
% ============================================
function pattern = analysePattern(drift_pct, numHarmonics)
    if numHarmonics >= 3 && drift_pct(3) > 30
        pattern = 'H3_rising-bearing_wear';
    elseif numHarmonics >= 2 && drift_pct(2) > 30
        pattern = 'H2_appearing-winding_fault';
    elseif numHarmonics >= 6 && (drift_pct(2)+drift_pct(4)+drift_pct(6)) > 60
        pattern = 'Even_harmonics-capacitor_degradation';
    elseif drift_pct(1) > 30
        pattern = 'H1_drop-load_loss';
    elseif std(drift_pct) > 20
        pattern = 'Unstable_harmonics-intermittent_fault';
    else
        pattern = 'General_THD_rise-degradation';
    end
end