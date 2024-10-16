function [xdn,F,blsig,spike] = dbtDenoise(x,fs,bandwidth,varargin)

% Denoise using the demodulated band representation of a signal (see
% DBT). A threshold is computed on the coefficients using a threshold on
% kurtosis.
%
% Usage:
%
%   [xdn,filt,dbt] = dbtDenoise(x,Fs,bandwidth,[keyword],[value])
%
%    Inputs:
% 
%       x - signal
%       Fs - sampling frequency
%       bandwidth to use in the dbt (default = 0.05)
%
% 
%    Outputs:
% 
%       xdn   - denoised signal
%       filt  - filter used on DBT coefficients in denoising  
%       blsig - DBT of xdn
%
%    Keyword options:
%       
%       'remove spikes':  true - remove spikes at the default threshold (default)
%                                before applying dbt-based denoising.
%                         false - no spike removal
%                         n (scalar) - remove spikes at specified threshold
%                         Thresholding is applled iteratively to z-scores
%                         across all remaining time points none remain above the threshold.
%
%       'kthresh'      :  kurtosis threshold. Coefficients in frequency bands for which
%                         kurtosis over time falls above this value are
%                         thresholded at 'zlothreshold' and otherwise at
%                         'zhireshold'. This feature was added as
%                         kurtosis is useful for detecting frequency
%                         modulated line noise. Default = 10.
%                         
%      'zhithresh'     : Threshold for coefficient removal. (default=6)
%       
%      'zlothresh'     : Threshold for coefficient removal in frequency
%                        banbds that fall above 'kthresh'. (default = 3).
%       
% See also DBT

% C Kovach 2013
% ----------- SVN REVISION INFO ------------------
% $URL: https://saccade.neurosurgery.uiowa.edu/svn/KovachToolbox/devel/DBT/dbtDenoise.m $
% $Revision: 491 $
% $Date: 2014-05-06 17:57:17 -0500 (Tue, 06 May 2014) $
% $Author: ckovach $
% ------------------------------------------------

if nargin < 3 || isempty(bandwidth)
   bandwidth = .05; % This seems to work well for constant line noise. For FM line noise try .25 or so. 
end

kurtosis_threshold = 10; % Apply a lower Z threshold to frequency points that have kurtosis above this value
spike.remove_spikes = true;  % Zero out time points that exceed some threshold
spike.threshold = 10; % This is the threshold used in detecting spikes. 
                      % Z-score is computed iteratively until
                      % no points exceed this value. The threshold is set
                      % high by default because the main purpose here is to avoid
                      % distortion of kurtosis used in the
                      % kurtosis-threshold.
spike.smoothwindow = .2;% Apply hanning window of given duration to smooth the spike filter.
filter_above = 40; 
use_stft = false;
zhithresh = 6;
zlothresh = 3;
makeplots = false;
i = 1;
while i < length(varargin)
          switch lower(varargin{i})

              case {'stft'}  % use stft instead of bld
                  use_stft = true; 
                  varargin(i) = [];
                  i = i-1;
              case {'dbt'}  % use stft instead of dbt
                  use_stft = false;                        
                  varargin(i) = [];
                  i = i-1;
              case {'kurtosis','kthresh'}  % Apply a lower filter threshold for frequency values that have kurtosis exceeding this value
                  kurtosis_threshold = varargin{i+1};
                  varargin(i:i+1) = [];
                  i = i-1;
               case {'filter above'}  % use stft instead of dbt
                  
                  filter_above = varargin{i+1};
                  varargin(i:i+1) = [];
                  i = i-1;
               case {'remove spikes'}  % use stft instead of dbt
                  
                  spike.remove_spikes = varargin{i+1};
                  if ~islogical(spike.remove_spikes) && spike.remove_spikes~=1 && spike.remove_spikes~=0
                     spike.threshold = spike.remove_spikes; 
                  end
                  varargin(i:i+1) = [];
                  i = i-1;
                case {'zhithresh','high threshold'}  % coefficient threshold
                  zhithresh = varargin{i+1};
                  varargin(i:i+1) = [];
                  i = i-1;        
                case {'zlothresh','low threshold'}  % Apply a lower threshold to frequencies above the kurtosis threshold
                  zlothresh = varargin{i+1};
                  varargin(i:i+1) = [];
                  i = i-1;        
                case {'makeplots'} 
                  makeplots = varargin{i+1};
                  varargin(i:i+1) = []; 
                  i = i-1;                
              otherwise
%                  error('Unrecognized keyword %s',varargin{i})
          end
          i = i+1;
end
  

shoulder  = 1; %This is overridden if passed as an argument in varargin

if spike.remove_spikes    
    [x,spike] = spikefilter(x,fs,spike);
%     spks = false(size(x));
%     newspks = true;
%     while any(newspks)
%        z = (x-mean(x(~spks)))/std(x(~spks));
%        newspks = abs(z)>spike.threshold &~spks; 
%        spks = newspks | spks;
%     end
%     win = hanning(ceil(spike.smoothwindow.*fs));
%     spike.filter = exp(convn(log(1-spks+eps),win,'same'));
%     spike.filter(spike.filter<0)=0;
%     x = x.*spike.filter;
end

if ~use_stft
    blsig = dbt(x,fs,bandwidth,'padding','time','shoulder',shoulder,varargin{:}); % Band limited representation of the signal (see dbt)
else
    blsig = stft(x,fs,bandwidth,'shoulder',shoulder,varargin{:}); % Band limited representation of the signal (see dbt)    
end
w = blsig.frequency;

kt = kurtosis(abs(blsig.blrep));
nsig = rmbaseline(blsig,w>=filter_above & kt<kurtosis_threshold); %takes out the baseline by fitting a polynomial

mn = mean(abs(nsig));


%%% Compute z-score for mean power
nzsc = @(x)(x-nanmean(x))./nanstd(x);
z = nzsc(mn);

%%% exclude points that exceed a threshold from the score computation
z(w<filter_above) = nan;
z(kt>kurtosis_threshold) = nan;
while any(abs(z)>zlothresh)
    
    z(abs(z)>zlothresh) = nan;
    
    z = nzsc(z);
    
end
    
z = (mn-mean(mn(~isnan(z))))./std(mn(~isnan(z)));
ln = z>zlothresh;  %%% Threshold the adjusted z

P = abs(nsig);
P(:,w<filter_above) = nan;
P(:,ln) = nan;

%Compute zscore over all time-frequency points without including the potentially contaminated frequencies in the variance estimate
Z = (abs(nsig)-mean(abs(nsig(~isnan(P)))))./std(abs(nsig(~isnan(P))));

% Exclude frequencies below 40
Z(:,w<filter_above) = 0;
%Set threshold 
LN = isnan(P) & Z > zlothresh | Z >zhithresh ;

% % Smooth edges a little to reduce time-domain artifacts 
% g = gausswin(ceil(.5./blsig.sampling_rate));
% g = g./max(g);
% LN = convn(LN,g./sum(g),'same');

F = 1-LN;

if makeplots
   [orig,bl] = rmbaseline(blsig,w>=filter_above & kt<kurtosis_threshold); %takes out the baseline by fitting a polynomial
   orig = 20*log10(abs(nanmean(abs(orig).^2)))';
end

blsig.blrep = blsig.blrep.*F;

xdn = blsig.signal;

xdn = xdn(1:length(x));


if makeplots
   dnnsig = blsig.blrep.*repmat(exp(-bl),length(blsig.time),1); %takes out the baseline by fitting a polynomial
   pl = plot(blsig.frequency,[orig,20*log10(nanmean(abs(dnnsig).^2))']);
   set(pl(1),'color','r');
   set(pl(2),'color','b');
   xlabel('Freq (hz)')
   ylabel('dB');
   grid on
   legend({'Baseline normalized power','After denoising'})
   xlim([filter_above 800])
end


