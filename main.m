% ============================================
% Avantguard — Main Menu
% main.m
% Run this file to access all features
% ============================================

clc;

while true

    % ============================================
    % DISPLAY MENU
    % ============================================
    fprintf('\n');
    fprintf('============================================\n');
    fprintf('           AVANTGUARD v1.0                  \n');
    fprintf('    Device Health Monitoring System          \n');
    fprintf('============================================\n');
    fprintf('\n');
    fprintf('  [1]  Calibrate new device\n');
    fprintf('  [2]  Start live monitoring\n');
    fprintf('  [3]  Update device baseline\n');
    fprintf('  [4]  View device database\n');
    fprintf('  [5]  View fault log\n');
    fprintf('  [6]  Delete device from database\n');
    fprintf('  [0]  Exit\n');
    fprintf('\n');
    fprintf('============================================\n');

    choice = input('  Enter choice: ');

    switch choice

        % ============================================
        case 1   % Calibrate new device
        % ============================================
            clc;
            fprintf('Launching calibration...\n\n');
            calibrate;

        % ============================================
        case 2   % Live monitoring
        % ============================================
            clc;
            % check baseline file exists first
            if ~isfile('avantguard_baselines.csv')
                fprintf('\n[ERROR] No baseline file found.\n');
                fprintf('Please calibrate at least one device first (Option 1).\n');
                input('\nPress Enter to return to menu...');
            else
                fprintf('Launching live monitor...\n\n');
                runtime;
            end

        % ============================================
        case 3   % Update baseline
        % ============================================
            clc;
            if ~isfile('avantguard_baselines.csv')
                fprintf('\n[ERROR] No baseline file found.\n');
                fprintf('Please calibrate at least one device first (Option 1).\n');
                input('\nPress Enter to return to menu...');
            else
                fprintf('Launching baseline updater...\n\n');
                update_baseline;
            end

        % ============================================
        case 4   % View device database
        % ============================================
            clc;
            fprintf('\n============================================\n');
            fprintf('           DEVICE DATABASE                  \n');
            fprintf('============================================\n\n');

            if ~isfile('avantguard_baselines.csv')
                fprintf('No devices calibrated yet.\n');
            else
                rawTable   = readtable('avantguard_baselines.csv', ...
                                       'VariableNamingRule', 'preserve');
                allNames   = rawTable.Device;
                allMetrics = rawTable.Metric;
                deviceList = unique(allNames, 'stable');
                numDevices = length(deviceList);

                fprintf('Total devices: %d\n\n', numDevices);
                fprintf('%-5s %-20s %-10s %-10s %-10s %-10s %-25s\n', ...
                        'No.', 'Device', 'THD(%)', 'RMS', 'Reliability', 'Fail Prob', 'Grade');
                fprintf('%s\n', repmat('-', 1, 85));

                for d = 1:numDevices
                    meanRow = rawTable(strcmp(allNames, deviceList{d}) & ...
                                      strcmp(allMetrics, 'mean'), :);
                    fprintf('%-5d %-20s %-10.2f %-10.4f %-10d %-10d %-25s\n', ...
                            d, deviceList{d}, ...
                            meanRow.THD, ...
                            meanRow.RMS_current, ...
                            meanRow.Reliability_Score, ...
                            meanRow.Failure_Prob, ...
                            meanRow.Grade{1});
                end

                fprintf('\n');

                % ask if user wants harmonic detail
                detail = input('View harmonic detail for a device? (y/n): ', 's');
                if strcmpi(strtrim(detail), 'y')
                    dNum = input('Enter device number: ');
                    if dNum >= 1 && dNum <= numDevices
                        dName = deviceList{dNum};
                        fprintf('\n--- Harmonic Baseline: %s ---\n', dName);
                        fprintf('%-10s %-12s %-12s %-12s %-12s\n', ...
                                'Harmonic', 'Mean', 'Std', 'Upper', 'Lower');
                        fprintf('%s\n', repmat('-', 1, 55));

                        meanRow  = rawTable(strcmp(allNames,dName) & strcmp(allMetrics,'mean'),  :);
                        stdRow   = rawTable(strcmp(allNames,dName) & strcmp(allMetrics,'std'),   :);
                        upperRow = rawTable(strcmp(allNames,dName) & strcmp(allMetrics,'upper'), :);
                        lowerRow = rawTable(strcmp(allNames,dName) & strcmp(allMetrics,'lower'), :);

                        hCols = 3:3+9;
                        for h = 1:10
                            colName = rawTable.Properties.VariableNames{hCols(h)};
                            fprintf('H%-9d %-12.4f %-12.4f %-12.4f %-12.4f\n', ...
                                    h, ...
                                    meanRow.(colName),  ...
                                    stdRow.(colName),   ...
                                    upperRow.(colName), ...
                                    lowerRow.(colName));
                        end
                    else
                        fprintf('Invalid device number.\n');
                    end
                end
            end

            input('\nPress Enter to return to menu...');

        % ============================================
        case 5   % View fault log
        % ============================================
            clc;
            fprintf('\n============================================\n');
            fprintf('              FAULT LOG                     \n');
            fprintf('============================================\n\n');

            if ~isfile('fault_log.csv')
                fprintf('No faults logged yet.\n');
            else
                faultTable = readtable('fault_log.csv', ...
                                       'VariableNamingRule', 'preserve');
                numFaults  = height(faultTable);

                if numFaults == 0
                    fprintf('Fault log is empty.\n');
                else
                    fprintf('Total fault events: %d\n\n', numFaults);
                    fprintf('%-22s %-20s %-10s %-12s %-12s %-30s\n', ...
                            'Timestamp', 'Device', 'Severity', 'THD Base', 'THD Live', 'Pattern');
                    fprintf('%s\n', repmat('-', 1, 110));

                    for i = 1:numFaults
                        fprintf('%-22s %-20s %-10s %-12.2f %-12.2f %-30s\n', ...
                                faultTable.Timestamp{i}, ...
                                faultTable.Device{i}, ...
                                faultTable.Severity{i}, ...
                                faultTable.THD_Baseline(i), ...
                                faultTable.THD_Live(i), ...
                                faultTable.Harmonic_Pattern{i});
                    end

                    fprintf('\n');

                    % filter by device
                    filterChoice = input('Filter by device? (y/n): ', 's');
                    if strcmpi(strtrim(filterChoice), 'y')
                        devFilter = input('Enter device name: ', 's');
                        devFilter = strtrim(devFilter);
                        filtered  = faultTable(strcmp(faultTable.Device, devFilter), :);
                        if height(filtered) == 0
                            fprintf('No faults found for %s.\n', devFilter);
                        else
                            fprintf('\nFaults for %s (%d events):\n\n', devFilter, height(filtered));
                            for i = 1:height(filtered)
                                fprintf('[%s] Severity: %-10s | THD drift: %.1f%% | %s\n', ...
                                        filtered.Timestamp{i}, ...
                                        filtered.Severity{i}, ...
                                        filtered.THD_Drift_pct(i), ...
                                        filtered.Action{i});
                            end
                        end
                    end
                end
            end

            input('\nPress Enter to return to menu...');

        % ============================================
        case 6   % Delete device
        % ============================================
            clc;
            fprintf('\n============================================\n');
            fprintf('           DELETE DEVICE                    \n');
            fprintf('============================================\n\n');

            if ~isfile('avantguard_baselines.csv')
                fprintf('No baseline file found.\n');
                input('\nPress Enter to return to menu...');
            else
                rawTable   = readtable('avantguard_baselines.csv', ...
                                       'VariableNamingRule', 'preserve');
                allNames   = rawTable.Device;
                deviceList = unique(allNames, 'stable');
                numDevices = length(deviceList);

                fprintf('Devices in database:\n\n');
                for d = 1:numDevices
                    fprintf('  [%d] %s\n', d, deviceList{d});
                end

                fprintf('\n');
                dNum = input('Enter device number to delete (0 to cancel): ');

                if dNum == 0
                    fprintf('Cancelled.\n');
                elseif dNum >= 1 && dNum <= numDevices
                    dName   = deviceList{dNum};
                    confirm = input(sprintf('Delete %s? This cannot be undone. (y/n): ', dName), 's');

                    if strcmpi(strtrim(confirm), 'y')
                        % remove all rows for this device
                        keepRows = ~strcmp(allNames, dName);
                        newTable = rawTable(keepRows, :);
                        writetable(newTable, 'avantguard_baselines.csv');
                        fprintf('\n%s deleted from database.\n', dName);

                        % also delete raw file if exists
                        rawFile = ['raw_' dName '.csv'];
                        if isfile(rawFile)
                            delete(rawFile);
                            fprintf('Raw file %s also deleted.\n', rawFile);
                        end
                    else
                        fprintf('Cancelled.\n');
                    end
                else
                    fprintf('Invalid choice.\n');
                end

                input('\nPress Enter to return to menu...');
            end

        % ============================================
        case 0   % Exit
        % ============================================
            clc;
            fprintf('\n============================================\n');
            fprintf('         AVANTGUARD SHUTDOWN                \n');
            fprintf('         Goodbye.                           \n');
            fprintf('============================================\n\n');
            break;

        % ============================================
        otherwise
        % ============================================
            fprintf('\n[ERROR] Invalid choice. Enter 0-6.\n');
            pause(1);
    end

    clc;

end