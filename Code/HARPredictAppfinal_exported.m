classdef HARPredictAppfinal_exported < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure                matlab.ui.Figure
        ResultTextArea          matlab.ui.control.TextArea
        ResultsTextAreaLabel    matlab.ui.control.Label
        UploadButton            matlab.ui.control.Button
        WeightEditField         matlab.ui.control.NumericEditField
        WeightKgEditFieldLabel  matlab.ui.control.Label
        HeightEditField         matlab.ui.control.NumericEditField
        HeightcmEditFieldLabel  matlab.ui.control.Label
    end

properties (Access = private)
    net   % Store trained network
end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: UploadButton
        function UploadButtonPushed(app, event)

try
    % === 1) Pick file ===
    [file, path] = uigetfile('*.mat','Select your sensor data file');
    if isequal(file,0); return; end
    S = load(fullfile(path,file));

    % === 2) Build XUser (cell array of [6 x 128]) from various accepted formats ===
    XUser = [];
    % Case A: already provided as cell array 'X'
    if isfield(S,'X') && iscell(S.X)
        % Validate each cell shape
        X = S.X;
        for i = 1:numel(X)
            seq = X{i};
            if size(seq,1) ~= 6 && size(seq,2) == 6
                X{i} = seq.'; % make [6 x T]
            end
        end
        XUser = X;
    end

    % Case B: provided as 3-D numeric array 'userData' in some permutation
    if isempty(XUser) && isfield(S,'userData')
        U = S.userData;
        if ~isnumeric(U)
            error('userData must be numeric.');
        end
        nd = ndims(U);
        if nd == 2
            % Single sequence: try to coerce to [6 x 128]
            if any(size(U) == 6) && any(size(U) == 128)
                if size(U,1) == 6 && size(U,2) == 128
                    XUser = {U};
                elseif size(U,1) == 128 && size(U,2) == 6
                    XUser = {U.'};
                else
                    error('2D userData must be 6x128 or 128x6.');
                end
            else
                error('2D userData must include dims 6 and 128.');
            end
        elseif nd == 3
            % Identify which dim is 6 (features) and 128 (time)
            dims = [size(U,1), size(U,2), size(U,3)];
            idx6   = find(dims == 6,   1, 'first');
            idx128 = find(dims == 128, 1, 'first');
            if isempty(idx6) || isempty(idx128)
                error('3D userData must contain a 6-dim (features) and a 128-dim (time).');
            end
            idxN = setdiff(1:3, [idx6 idx128]);
            U = permute(U, [idx6 idx128 idxN]);   % -> [6 x 128 x N]
            XUser = squeeze(num2cell(U, [1 2]));  % -> {N x 1}, each [6 x 128]
        else
            error('userData must be 2D or 3D.');
        end
    end

    % Case C: six raw channel matrices -> group into [6 x 128 x N]
    haveSix = all(isfield(S, {'total_acc_x','total_acc_y','total_acc_z', ...
                              'body_gyro_x','body_gyro_y','body_gyro_z'}));
    if isempty(XUser) && haveSix
        rawUser = table(S.total_acc_x, S.total_acc_y, S.total_acc_z, ...
                        S.body_gyro_x, S.body_gyro_y, S.body_gyro_z);
        numSig = size(rawUser,1);
        % Reuse your existing helper on path
        [user_group, ~] = groupByActivity(rawUser, numSig, rawUser, numSig);
        XUser = squeeze(num2cell(user_group, [1 2]));  % each [6 x 128]
    end

    if isempty(XUser)
        error(['Unsupported file format. Upload one of:\n' ...
               '• userData (6x128xN) numeric array\n' ...
               '• X (cell array), each cell [6xT] or [Tx6]\n' ...
               '• six channels: total_acc_*, body_gyro_* (2947x128 each)']);
    end

% Ensure numeric type & orientation
XUser = cellfun(@(x) double(x), XUser, 'UniformOutput', false);

for i = 1:numel(XUser)
    if size(XUser{i},1) ~= 6 && size(XUser{i},2) == 6
        XUser{i} = XUser{i}.';   % transpose to [6 x T]
    elseif size(XUser{i},1) ~= 6
        error('Each sequence must have 6 features.');
    end
end


    % === 3) Load network (simple + safe: load per run) ===
    tmp = load("trainedHARNet.mat");
    net = tmp.net;

    % === 4) Classify ===
    YPred = classify(net, XUser);   % categorical

    % === 5) Time per activity ===
    secPerSeq = 2.5; % each 128-sample window
    acts = categories(YPred);
    counts = countcats(YPred);
    hoursPerAct = containers.Map;
    for i = 1:numel(acts)
        hoursPerAct(char(acts{i})) = (counts(i)*secPerSeq)/3600;
    end

    % === 6) BMI from inputs ===
    height = app.HeightEditField.Value; % cm
    weight = app.WeightEditField.Value; % kg
    h = height/100;                      % m
    BMI = weight/(h*h);

    % === 7) Map predicted labels -> canonical names -> calorie rates ===
    % Dataset labels often: walking, walking_upstairs, walking_downstairs, sitting, standing, laying
    label2canon = containers.Map( ...
        {'walking','walking_upstairs','walking_downstairs','sitting','standing','laying'}, ...
        {'walking','stairsup','stairsdown','sitting','standing','laying'} );

    % Your rates (kcal/hour). Added 'sitting'≈60 to cover dataset label.
    ratePerCanon = containers.Map( ...
        {'walking','running','stairsup','stairsdown','laying','standing','sitting'}, ...
        [  275    ,  500   ,   530   ,    240    ,   40   ,   80    ,   60     ] );

    totalCals = 0;
    lines = strings(0,1);

    for i = 1:numel(acts)
        rawLbl = lower(strrep(char(acts{i}), ' ', '_')); % normalize
        canon = rawLbl;
        if isKey(label2canon, rawLbl)
            canon = label2canon(rawLbl);
        end
        hrs = hoursPerAct(char(acts{i}));
        rate = 0;
        if isKey(ratePerCanon, canon)
            rate = ratePerCanon(canon);
        end
        cals = hrs * rate;
        totalCals = totalCals + cals;
        lines(end+1,1) = sprintf('%s: %.2f hrs  →  %.0f kcal', canon, hrs, cals); %#ok<AGROW>
    end

    % === 8) Days to reach BMI 24.9 (simple kcal model) ===
    targetBMI = 24.9;
    targetWt  = targetBMI * (h^2);
    kgToLose  = max(0, weight - targetWt);
    kcalPerKg = 7700;
    kcalToLose = kgToLose * kcalPerKg;

    if totalCals > 0
        days = ceil(kcalToLose / totalCals);
        etaStr = sprintf('At this daily activity level: ~%d days to BMI %.1f.', days, targetBMI);
    else
        etaStr = 'No activity calories detected → can’t estimate days.';
    end

    % === 9) Show report ===
    header = sprintf('BMI: %.1f\nCalories burnt (total): %.0f kcal\n', BMI, totalCals);
    breakdown = strjoin(cellstr(lines), newline);
    tail = sprintf('\nTo reach healthy BMI (%.1f): need %.1f kg loss.\n%s', targetBMI, kgToLose, etaStr);

    app.ResultTextArea.Value = splitlines([header 'Activity breakdown:' newline breakdown newline tail]);

catch ME
    uialert(app.UIFigure, ME.message, 'Error');
end
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 640 480];
            app.UIFigure.Name = 'MATLAB App';

            % Create HeightcmEditFieldLabel
            app.HeightcmEditFieldLabel = uilabel(app.UIFigure);
            app.HeightcmEditFieldLabel.FontWeight = 'bold';
            app.HeightcmEditFieldLabel.Position = [12 356 71 22];
            app.HeightcmEditFieldLabel.Text = 'Height (cm)';

            % Create HeightEditField
            app.HeightEditField = uieditfield(app.UIFigure, 'numeric');
            app.HeightEditField.HorizontalAlignment = 'left';
            app.HeightEditField.FontWeight = 'bold';
            app.HeightEditField.Position = [82 356 100 22];

            % Create WeightKgEditFieldLabel
            app.WeightKgEditFieldLabel = uilabel(app.UIFigure);
            app.WeightKgEditFieldLabel.FontWeight = 'bold';
            app.WeightKgEditFieldLabel.Position = [12 390 72 22];
            app.WeightKgEditFieldLabel.Text = 'Weight (Kg)';

            % Create WeightEditField
            app.WeightEditField = uieditfield(app.UIFigure, 'numeric');
            app.WeightEditField.HorizontalAlignment = 'left';
            app.WeightEditField.FontWeight = 'bold';
            app.WeightEditField.Position = [82 390 100 22];

            % Create UploadButton
            app.UploadButton = uibutton(app.UIFigure, 'push');
            app.UploadButton.ButtonPushedFcn = createCallbackFcn(app, @UploadButtonPushed, true);
            app.UploadButton.FontWeight = 'bold';
            app.UploadButton.Position = [34 312 128 22];
            app.UploadButton.Text = 'Upload and Analyze';

            % Create ResultsTextAreaLabel
            app.ResultsTextAreaLabel = uilabel(app.UIFigure);
            app.ResultsTextAreaLabel.FontSize = 18;
            app.ResultsTextAreaLabel.FontWeight = 'bold';
            app.ResultsTextAreaLabel.Position = [242 400 70 23];
            app.ResultsTextAreaLabel.Text = 'Results';

            % Create ResultTextArea
            app.ResultTextArea = uitextarea(app.UIFigure);
            app.ResultTextArea.HorizontalAlignment = 'center';
            app.ResultTextArea.FontSize = 18;
            app.ResultTextArea.Position = [311 31 322 394];

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = HARPredictAppfinal_exported

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end