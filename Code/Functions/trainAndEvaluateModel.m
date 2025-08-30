
load('rawSensorData_train.mat');
rawDataTrain = table(total_acc_x, total_acc_y, total_acc_z, ...
                     body_gyro_x, body_gyro_y, body_gyro_z);

load('rawSensorData_test.mat');
rawDataTest = table(total_acc_x, total_acc_y, total_acc_z, ...
                    body_gyro_x, body_gyro_y, body_gyro_z);


numSig_train = size(rawDataTrain,1);
numSig_test  = size(rawDataTest,1);

[train_groups, test_groups] = groupByActivity(rawDataTrain, numSig_train, ...
                                              rawDataTest, numSig_test);


XTrain = squeeze(num2cell(train_groups, [1 2]));  
XTest  = squeeze(num2cell(test_groups, [1 2]));


YTrain = categorical(trainActivity);  
YTest  = categorical(testActivity);   


inputSize = 6;          
numHiddenUnits = 128;   
numClasses = 6;         

layers = [
    sequenceInputLayer(inputSize,'Name','sequence')
    bilstmLayer(numHiddenUnits,'OutputMode','last','Name','bilstm')
    fullyConnectedLayer(numClasses,'Name','fc')
    softmaxLayer('Name','softmax')
    classificationLayer('Name','classoutput')
];

lgraph = layerGraph(layers);   


options = trainingOptions('adam', ...
    'MaxEpochs',20, ...
    'MiniBatchSize',16, ...
    'Shuffle','every-epoch', ...
    'Plots','training-progress');


net = trainNetwork(XTrain, YTrain, lgraph, options);


YPred = classify(net, XTest);
accuracy = sum(YPred == YTest)/numel(YTest);
disp(['Test Accuracy: ', num2str(accuracy)]);


figure;
confusionchart(YTest, YPred);
title('Confusion Matrix: Test Set');


save('trainedHARNet.mat','net');


%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright"}
%---
