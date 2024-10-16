function [spkTable] = phyinfo2mat(ops)
%% Import spike information from Phy
sp = loadKSdir(ops.rootZ);
[spikeTimes, ~, ~, spikeSites] = ksDriftmap(ops.rootZ);

% clusterInfo_phy = tdfread([ops.rootZ '\cluster_info.tsv']);

ks_contamPct = tdfread([ops.rootZ '\cluster_ContamPct.tsv']);
ks_clusterAmp = tdfread([ops.rootZ '\cluster_Amplitude.tsv']);
ks_classification = tdfread([ops.rootZ '\cluster_KSLabel.tsv']);
phy_classification = tdfread([ops.rootZ '\cluster_group.tsv']);


%% Setup variable space for spike and waveform data
% Note: I've checked and it seems as though noise clusters are dropped from
% the import, and we don't need to include/exclude them manually.

unitList = double(unique(sp.clu));
nUnits = length(unitList);
% Find site for each ID'd cluster
for unitIdx = 1:nUnits
    unit = unitList(unitIdx);
    ks_cluster(unitIdx,1) = unit;
    site(unitIdx,1) = double(mode(spikeSites(sp.clu == unit)));
end

% Get labels for the output (e.g. DSP01a, WAV01a = first unit on ch 1)
for unitIdx = 1:nUnits
    unit_site = find(unitIdx == find(site == site(unitIdx,1)));
    dspString = num2str(site(unitIdx,1),'DSP%02i');
    wavString = num2str(site(unitIdx,1),'WAV%02i');
    clustLetter = char(unit_site+96); % 97 is the char code for 'a"
    unitDSP{unitIdx,1} = [dspString clustLetter];
    unitWAV{unitIdx,1} = [wavString clustLetter];
   
    
    spkTimes = []; spkTimes  = round((spikeTimes(sp.clu == unitList(unitIdx))./ops.fs).*1000);  
    ISI = []; ISI = diff(spkTimes);
    
    
    nSpikes(unitIdx,1) = length(spkTimes);
    ISI_2ms(unitIdx,1) = (mean(ISI < 2))*100;
    ISI_2_4_ratio(unitIdx,1) = sum(ISI < 2)/sum(ISI >= 2 & ISI <= 4);
    contamPct(unitIdx,1) = ks_contamPct.ContamPct(ks_contamPct.cluster_id ==  ks_cluster(unitIdx,1),:);
    amplitude(unitIdx,1) = ks_clusterAmp.Amplitude(ks_clusterAmp.cluster_id ==  ks_cluster(unitIdx,1),:);
    ksClass{unitIdx,1} = ks_classification.KSLabel(ks_classification.cluster_id ==  ks_cluster(unitIdx,1),:);
    phyClass{unitIdx,1} = phy_classification.group(phy_classification.cluster_id ==  ks_cluster(unitIdx,1),:);
   
    
%     
%     contamPct(unitIdx,1) = clusterInfo_phy.ContamPct(clusterInfo_phy.cluster_id ==  cluster(unitIdx,1),:);
%     amplitude(unitIdx,1) = clusterInfo_phy.Amplitude(clusterInfo_phy.cluster_id ==  cluster(unitIdx,1),:);
%     ksClass{unitIdx,1} = {clusterInfo_phy.KSLabel(clusterInfo_phy.cluster_id ==  cluster(unitIdx,1),:)};
end

spkTable = table(ks_cluster,site,unitDSP,unitWAV,contamPct,amplitude,ksClass,phyClass,nSpikes,ISI_2ms,ISI_2_4_ratio);
spkTable = sortrows(spkTable,'site');

