
load rawSensorData_test.mat
rawDataTest = table(total_acc_x, total_acc_y, total_acc_z, ...
                    body_gyro_x, body_gyro_y, body_gyro_z);

numSig_test  = size(rawDataTest,1);


[~, test_groups] = groupByActivity(rawDataTest, numSig_test, rawDataTest, numSig_test);


nSeq = size(test_groups,3);


expandFactor = 20;  
userData = repmat(test_groups,1,1,expandFactor);


permIdx = randperm(size(userData,3));
userData = userData(:,:,permIdx);


save('userData.mat','userData');

fprintf("Generated %d sequences (~%.1f hours of data)\n", ...
        size(userData,3), size(userData,3)*2.56/3600);


%[appendix]{"version":"1.0"}
%---
%[metadata:view]
%   data: {"layout":"onright"}
%---
