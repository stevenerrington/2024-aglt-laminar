clc
close all
clear all
[file,path,indx] = uigetfile('*.mat','Select LFP file');

load(fullfile(path,file))


% temp= [event.timestamp] - double(hdr.FirstTimeStamp);

for ind = 1:length(event)
    event(ind).timestampSeconds = (event(ind).timestamp - double(hdr.FirstTimeStamp)) *1e-6;
end

time = data.time{1,1}(end)
time_event = event(end).timestampSeconds
% %% using marker from the serial input
% temp = find([event.port]==2);
% 
% temp = event(temp);
% marker = dec2bin([temp.ttls]);
% marker = bin2dec(marker(:,2:8));
% trl = [temp.timestampSeconds]';
% trl = round(trl * hdr.TimeStampPerSample);
% 
% trl = [trl-1000 trl -500*ones(size(trl))];
%% using sound input
temp = find([event.port]==0);
sound = event(temp);
temp = diff([sound.timestampSeconds]);
temp = find(temp>0.8);
trl = [sound(temp).timestampSeconds];

trl = round(trl * hdr.TimeStampPerSample)';

trl = [trl-1000 trl -500*ones(size(trl))];
%%
cfg = [];
cfg.trl = trl;
lfp = ft_redefinetrial(cfg,data);

%%
cfg=  [];
figure(1)
cfg.layout = 'vertical';
cfg.xlim = [-0.2 inf];
% cfg.trials = [1:5];

subplot(2,2,1)
% ft_multiplotER(cfg,lfp)
ft_singleplotER(cfg,lfp)
xlabel('Time (s)')
ylabel('Voltage (uV)')
grid on
% hold on
% xline(0)
% legend('LFP','Sound Onset')
%%
% 
cfg_fft = [];
cfg_fft.method = 'mtmfft';
cfg_fft.foilim = [0 80];
cfg_fft.taper = 'dpss';
cfg_fft.tapsmofrq = 4;
cfg_fft.trials = [1:5];

freq = ft_freqanalysis(cfg_fft,lfp);

cfg = [];
cfg.layout = 'vertical';
figure(2)
subplot(2,1,1)
ft_singleplotER(cfg,freq)
grid on
% title('R1 Ref 02 as ref')

%%
    cfg_tf = [];
    cfg_tf.method = 'wavelet';
    cfg_tf.width = 7;
    cfg_tf.foi = [1:1:50];
%     cfg_tf.toi = [0:0.01:30];
    cfg_tf.toi = 'all';
    tfreq = ft_freqanalysis(cfg_tf,lfp);
    %%
    cfg = [];
%     cfg.layout = 'vertical';
    cfg.ylim = [0 50];
    figure(1)
    subplot(2,2,3)
       colormap(jet)
    ft_singleplotTFR(cfg,tfreq)
%% CSD calculation from LFP
    cfg = []; 
%     cfg.channel = {lfp.label{1:num_ch}};
    lfp_csd = ft_selectdata(cfg,lfp);
    
    [csd,icsd,time] = calculateCSD_nylx(lfp_csd);
%%
    figure(1)
    num_ch = 16;
    ch = 0:(num_ch+1)/200:(num_ch+1)-((num_ch+1)/200);
    subplot(2,2,[2 4])
    imagesc(time,ch,1.*(icsd))

    colormap(flipud(jet))
    colorbar
    xlabel('Time (seconds)')
    yt = get(gca,'YTick');
figure
%     saveas(gcf,[file '_csd_' my_datetimestr '.fig']) 
%     figure
    subplot(1,2,2)
    imagesc(time,[num_ch:1],(csd))
       colormap(flipud(jet))
    colorbar
    xlabel('Time (seconds)')
    yt = get(gca,'YTick');



% %% Plotting MUA
%     cfg = [];
%     cfg.layout = 'vertical';
%     cfg.baseline = [-0.1 0];
%     figure
%     ft_multiplotER(cfg,muax)