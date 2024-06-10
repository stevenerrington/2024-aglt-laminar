
classdef xneon < handle 

% This class provides an interface for the neon cluster through which
% matlab batch jobs may be submitted.
%
% BASIC USE  
%
%       xne = xneon('/path/to/mfile.m')
% 
%   Creates a new xneon object to run the code in mfile.m. 
%   xne = xneon, without an argument, will bring up a file selection menu.
%
%   Once the job is established, it can be submitted with 
%            
%       xne.submit
%  
%   To check the status of a job use
%
%       xne.satus
%
%   To download the results of a finished job and close the request use
%
%       xne.finish()
%
%   Finally, to initiate a timer object that automatically monitors the
%   progress of the job and and executes xne.finish when it is done, use.
% 
%       xne.monitor()
%
%  For a job whose status is anything other than 'none' or 'idle',
%  xne.submit will throw an error. To force a resubmission in such cases,
%  use
%       xne.submit(true).
%
%  SCRIPT
%   
%   The file, mfile.m, can be a function or a script. If it is a function,
%   it should accept four arguments in the following order:
%
%       mfile(inputdir, outputdir,inputfiles,jobindex)
%   
%   inputdir will contain the path for the directory containing 
%   input data files used by your script, outputdir will be the
%   directory to which any output you wish to keep will be saved. When
%   multiple instances of the same script are run in parallel, jobindex 
%   will contain a unique index for each job.
%
%   If mfile.m is a script rather than a function, these variables will 
%   be visible within the workspace without having to be passed as arguments.
% 
%   Either way the code in mfile.m should look for input files it needs
%   in inputdir and save any output to outputdir. Data files you specifiy 
%   locally will automatically be copied to and from these directories.
%   Similarly, mfile.m as well as any external dependencies will be copied
%   to the server automatically, as long a shared folder is visible
%   locally, as described in NETWORK DIRECTORY.
%
%   Two additional files will be generated, a bash script submit.sh and an
%   m-file mwrapper.m. The bash script, submit.sh contains arguments and 
%   function calls that are passed to the job handler through qsub. For more
%   details on how this works see
%          https://wiki.uiowa.edu/display/hpcdocs/Basic+Job+Submission
%   These files can be edited to further customize the submission.
% 
% 
%  REQUESTING RESOURCES
%   
%   Submitted jobs are put into a queue where they wait until requested
%   resources (e.g. memory and compute cores) are available. The duration
%   of this wait depends on the resources requested and, naturally, the more
%   you request, the longer you can generally expect to wait. Using the
%   cluster efficiently is a matter of finding the sweet spot in which
%   the gain in processing speed isn't defeated by having to endure a long
%   wait in the queue. For more details see
%       https://wiki.uiowa.edu/display/hpcdocs/Queue+Usage+and+Policies
%
%   Resources are allocated as "slots" on separate nodes, where each node
%   is a computer. The processing nodes on the openly accessible queuess 
%   ("UI", "UI-HM", and "all.q") come in three flavors, "std_mem" (16 cores and 
%   64 GB ram), "mid_mem" (16 cores and 256 GB ram) and "high_mem" (24
%   cores and 512 GB). These set the upper limits on resources that can be
%   used by a single non-parallel process. 
%   
%   Each slot reserves 1 core and either 4GB (std_mem), 16GB (mid_mem), or
%   20GB (high_mem) depending on node type. 
%
%   With xneon, resource allocation is controlled in four ways. 
% 
%     1. The node type requested is set in xne.profile, which can be 
%        'std_mem', 'mid_mem' or 'high_mem'.
%     
%     2. The number of slots to be requested for each process can be set with 
%                   xne.nslots = N 
%   
%     3. Setting the minimum requested memory
%                   xne.minmem = M
%        will adjust the number of requested slots  so that at least M GB
%        are available for each process, depending on node type.
% 
%     4. Multiple processes can be run in parallel by setting
%                   xne.nparallel = n.
%        This will generate n separate requests with resources defined
%        above allocated to each. 
%       
%        On most queues there is a per-user limit on the number of processes 
%        allowed to run in parallel. For the default queue, UI, it is 10.  
%        One queue, however, doesn't have a hard limit: 'all.q'. Requests
%        on this queue are given lower priority and will be evicted if another
%        job requires more than remaining available resources for a given node. 
%        all.q is a good choice when you have a large number of relatively fast
%        low-demand jobs, which are less likely to be evicted. To select a
%        queue, set the value of xne.queue to 'UI','all.q', or 'UI-HM'. The
%        default is 'UI'.
%        
%
% 
%  NETWORK DIRECTORY
%
%   To use xneon, a shared directory on a neon login server must be mounted 
%   locally, for example, as a samba folder. Doing so requires an account
%   on the neon cluster, which you can request from ITS, here: 
%           
%             http://hpc.uiowa.edu/user-services/apply-account
%
%   Your neon home directory can be accessed by mounting the URL 
%
%               //neon-home.hpc.uiowa.edu/[YourHawkID]
%
%   after which it will be visible as a local directory (eg. "/path/to/neonshare")
%
%   The first time you submit a job after starting matlab, the location of 
%   the share ("/path/to/neonshare" in the example) will be requested if it
%   hasn't already been set.
%   
%   If it does not already exist, a subfolder "jobs" will be created 
%   ("/path/to/neonshare/jobs"). Requests will be uploaded to this folder.
%   Each new request generates a randomly named subfolder within "jobs" 
%   ("/path/to/neonshare/jobs/[request-uuid]/") and, within this, the 
%   subfolders, "mfiles", "bash", "log", "status", "assets" and "output". 
%   All matlab files needed to run the main script, mfile.m, will be uploaded
%   to mfiles; data files are copied to assets, and information on the process
%   status can be found in status.
%   
% 
%   SERVER SET UP
%
%   To initiate jobs, the script, scanjobs.sh, must be running on a neon login
%   node. It checks periodically for new requests in the jobs directory. When 
%   it finds a new request, it passes the request on to the cluster job handler. 
%   If scanjobs.sh isn't running or is scanning a different folder, the request
%   will not be processed. 
%   
% 
  
% Christopher Kovach 2016
    properties 
        title='"xneon_job"';  % Label for the job.
        mfile = ''; % The script or function to be run.       
    end
    properties (Dependent = true)
       status; % Status of the job: submitted, waiting, running, suspended, error
       minmem; % Amount of memory requested 
       nslots; % Number of compute slots requested
       profile; % Node type: std_mem, mid_mem, or high_mem
       nparallel; % Number of instances to run
       mailer;  % Whether and where to send mail about changes in the job status
       qsub_opts; % List of options passed to the qsub command       
       qsub_opts_add; % Additional options added nby the user.
       datafiles  % Data files needed to run the script
       jobid ; % Numeric identifier for the the job on the neon server.
       finish; % Contains a function handle that is executed by the timer 
               % when the job is complete.
       qacct;
       neonpath;
       overquota; %True of if the storage quota is exceeded    
       jobindices;
       submission_attempts = 0; % Number of times this job has been submitted
    end
    
    properties
        
        path = ''; % Path to the job folder
        subpaths = struct('mfiles','','bash','','assets','','log','','status','','output',''); % Paths to the different sub folders for the job
        queue = 'UI';  %Queue to which the request will be send: 'UI','UI-HM' or 'all.q'
        neon_matlab_bin = 'matlab'; %location of matlab binary used to run the script
        use_matlab_version = '';
        neon_jobs_path = '~/xneon_submit/jobs'; %Path to the jobs folder as seen on the neon server.
        rerun_if_aborted = 'no';  %Request that the job be resubmitted if it is aborted.
        local_save_dir % Local directory to which the output data will be copied.
        dependencies = {}; % List of matlab file dependencies for the job
        tempdir = '';
        quotalimit = 80;% Don't upload data files if usage exceeds this level (percent of quota)
     end
     
    properties (SetAccess = private)
        
  %      compiled = false;
%         ready = false;
%         running = false;
%         finished = false; 
        uuid = ''; % A unique identifier
        profiles; % Available node types
        bash = struct([]); % Fields (eg bash.submit) contain the content of generated bash script(s).
        mcode = struct([]); % Fields (eg mcode.mwrapper) contain generated matlab code.
        timer; % A timer object that can be used to execute the finish command when the job is finished.
    end
    
    properties (SetAccess = private, Hidden = true)
        
       avail_profiles = {'std_mem',4,16,64
                       'mid_mem',16,16,256
                       'high_mem',20,24,512};
       
        curr_neonpath = '~/neon/xneon_submit';   %Path to network folder shared from neon.     
        curr_profile = 'std_mem';
        curr_minmem = 4;  % Minimum memory to reserve in GB
                          % Proess may use more memory than this but it will
                          % be aborted if the node runs out.
        curr_nslots = 1;
        nnodes = 1; 
        jindices = [];
        created = false;
%         submitted = false;
        mailobj = struct('email','','mail_events','beas'); % b - begin, e - end, a - abort, s - suspend       
        qopts={};
        qopts_extra = {};
        data_file_list = struct('local','','remote','','orig','');
        usage_url='http://neon-head.hpc.uiowa.edu/ganglia/';
        finish_handle;
    end
     
    methods
        
        function me = xneon(varargin)
            %
            % Constructor for the xneon object
            %
            
           for k =1:size(me.avail_profiles,1)
               me.profiles.(me.avail_profiles{k,1}).memPerSlot = me.avail_profiles{k,2};
               me.profiles.(me.avail_profiles{k,1}).coresPerNode = me.avail_profiles{k,3};
               me.profiles.(me.avail_profiles{k,1}).memPerNode = me.avail_profiles{k,4};
            end
           if nargin <1 || isempty(varargin{1})
               [file,pth] = uigetfile('*.m','Pick m-file to run');
               [~,fn,ext] = fileparts(file);
           elseif isa(varargin{1},'xneon')
               fld = setdiff(fieldnames(varargin{1}),{'uuid','datafiles','jobid','subpaths','status','profiles','timer','minmem','qacct','tempdir'});
               try
                   for k = 1:length(fld)
                  me.(fld{k}) = varargin{1}.(fld{k}); 
                   end
               catch
               end
               file = varargin{1}.mfile;
               [pth,fn,ext] = fileparts(file);
               
           else
               file = varargin{1};
               [pth,fn,ext] = fileparts(file);
               if isempty(pth)
                   pth = cd;
               end
           end
           
           me.tempdir = tempname;
           mkdir(me.tempdir);
           
      %     [pth,fn,ext] = fileparts(me.mfile);
%            pth = me.path;
           if ispc
             me.neonpath = '\\sharedstorage02.hpc.uiowa.edu\hbrl2\HBRL_Upload\xneon_submit'; 
           end
           
%            me.use_matlab_version = sprintf('R%s',version('-release'));
      
           me.mfile = fullfile(pth,[fn,ext]);
           me.local_save_dir = fullfile(pwd,[fn,'_out']);
           
           me.mailer = [];
           
%            me.path= cd;
           
         
            
            fldn = fieldnames(me.subpaths);
            pthstruc = struct('local','','remote','');
            for k = 1:length(fldn)
                me.subpaths.(fldn{k})=pthstruc;
            end
            me.finish = @(varargin)default_finish(me,varargin{:});
            
            me.neonpath='';
        end
         
        %%%%%%
        function create_path(me,varargin)
            
            % Creates subdirectories in the neon jobs directory
            persistent npath
            
            if ( nargin < 2 || isempty(varargin{1}) ) && isempty(npath)
                me.neonpath = uigetdir(me.neonpath,'Locate xneon submit directory.');
                npath = me.neonpath;
            elseif nargin == 2
                me.neonpath = varargin{1};
                npath = me.neonpath;
            else
                me.neonpath = npath;
            end
            if ~me.checkscan;
                dd = dir(fullfile(me.neonpath,'.bridge'));
                if isempty(dd) || (now-dd.datenum)*24*60 < 30  
%                     warndlg(sprintf('The folder\n\n    %s\n\nhas not been recently scanned.\n\nIs scanpath.sh running on the server?',fullfile(npath,'jobs')))
                    warning('The folder\n\n    %s\n\nhas not been recently scanned.\n\nIs scanpath.sh running on the server?',fullfile(npath,'jobs'))
                else
                    warndlg(sprintf('The folder\n\n    %s\n\nhas not been recently synchronized.\n\nIs xneonbridge.sh running?',fullfile(npath,'jobs')))
                    warning('The folder\n\n    %s\n\nhas not been recently synchronized.\n\nIs xneonbridge.sh running?',fullfile(npath,'jobs'))
                    
                end
            end
            if isempty(me.uuid) 
                me.uuid = char(java.util.UUID.randomUUID);
            end
            
            if ~exist(fullfile(me.neonpath,'jobs'),'dir')
                try
                    mkdir(fullfile(me.neonpath,'jobs'))
                catch err
                    npath = '';
                        rethrow(err)
                end            
            end
            
            me.path.local = fullfile(me.neonpath,'jobs',me.uuid);
            mkdir(me.path.local)
            
            me.path.remote= [me.neon_jobs_path,'/',me.uuid];
            
            pthnames = fieldnames(me.subpaths);
            for k = 1:length(pthnames)
                mkdir(fullfile(me.path.local,pthnames{k}))
                me.subpaths.(pthnames{k}).local= fullfile(me.path.local,pthnames{k});
                me.subpaths.(pthnames{k}).remote= sprintf('%s/%s',me.path.remote,pthnames{k});
            end
            
            if ~isempty(me.datafiles)
               me.datafiles ={me.datafiles.orig}; 
            end
            fid = fopen(fullfile(me.subpaths.status.local,'current'),'w');
            fprintf(fid,'idle');
            fclose(fid);
            save(fullfile(me.subpaths.log.local,'xobject'),'me');
        end
        
        %%%%%%
        function scandep(me)
            
            % Get the file dependencies for the main script 
            
            fprintf(sprintf('\nScanning dependencies...\n'))
            me.dependencies = matlab.codetools.requiredFilesAndProducts(me.mfile);
            [pth,fns,exts] = cellfun(@(x)fileparts(x),me.dependencies,'uniformoutput',false);    
            

            %%% Make sure classes stay within a classdef folder
            cldef = regexp(pth,sprintf('(.*)([+@][^%s]*)',regexprep(filesep,'\\','\\\\')),'tokens','once');
            nise = ~cellfun(@isempty,cldef);
            cldef = cat(1,cldef{nise});                       
            
            if ~isempty(cldef)
                cldeffull = fullfile(cldef(:,1),cldef(:,2));
                unq =unique(cldeffull); 
    %             nise = ~cellfun(@isempty,unq);
                me.dependencies(nise) = [];
                me.dependencies=[me.dependencies,unq'];
            end    
            %%% Check to make sure mex files compiled for linux are
            %%% available
            ismex = cellfun(@(x)~isempty(strfind(lower(x),'mex')) & isempty(strfind(lower(x),'mexa')) ,exts);
            for k = find(ismex)
                dd = dir(fullfile(pth{k},[fns{k},'.mexa*']));
                if ~isempty(dd)
                    me.dependencies = [me.dependencies,fullfile(pth{k},{dd.name})];
                else
                   warning('A MEX file\n\t%s\nis listed as a dependency, but I can''t find a version compiled for linux.',fns{k})
                end
            end
            
                
            
            
        end
        
        %%%%%%
        function submit(me,force)
           
            % Submit the request. Use submit(true) to force a resubmit of a
            % previously submitted request.
            if nargin < 2
                force = false;
            end
            switch lower(me.status)
                case {'idle','none','deferred',''}
                otherwise
                    if ~force
                        warning('\n\nJob status is currently %s. Change the status if you really want to resubmit',upper(me.status))
                        return          
                    end
            end
               
            if ~me.created ||~exist(me.subpaths.status.local,'dir')|| force
                deferred = me.create_job(force);
            else
                deferred=me.overquota;
            end
            fid = fopen(fullfile(me.subpaths.status.local,'current'),'w+');
            if ~deferred 
                fprintf(fid,'open');
            else
                fprintf(fid,'deferred');
            end
            fclose(fid);
%             me.submission_attempts = submission_attempts+1;
            save(fullfile(me.subpaths.log.local,'xobject'),'me');
            
        end
        
        %%%%%%
        
        function deferred=create_job(me,force)
            
            % Create the job, generating scripts and copying files to the
            % server without submitting the request.
            if nargin < 2 
                force = false;
            end
            
            if isempty(me.subpaths.mfiles.local) || ~exist(me.subpaths.status.local,'dir')
                me.create_path;
            end
            if isempty(me.dependencies)
                me.scandep
            end
            flist = me.dependencies;
            for k = 1:length(flist)
                
                % Copyfile appears to have problems with directories that
                % start with "@"
                if isdir(flist{k});
                     cldir = regexp(flist{k},sprintf('[+@][^%s]*',regexprep(filesep,'\\','\\\\')),'match','once');           
                     system(sprintf('chmod -R 777 %s',fullfile(me.subpaths.mfiles.local,cldir)));
                    copyfile(flist{k},fullfile(me.subpaths.mfiles.local,cldir),'f')
                else
                
                    copyfile(flist{k},me.subpaths.mfiles.local,'f')
                end
            end
            
            if isempty(me.datafiles) || isempty(me.datafiles(1).orig)
                me.datafiles(:)=[];
            end
            deferred=me.overquota;
            if ~deferred
                for k = 1:length(me.datafiles)
                    if ~isempty(me.datafiles(k).orig) && ~exist(me.datafiles(k).local,'file')
                        fprintf('\nCopying %s',me.datafiles(k).orig)               
                        copyfile(me.datafiles(k).orig,me.datafiles(k).local,'f')                
                    end
                end
            end
            % Create bash script that will be submitted
            fldn = fieldnames(me.bash);
            if isempty(fldn) || force
                me.make_bash_script(false);
                fldn = fieldnames(me.bash);
            end
            
            for k = 1:length(fldn)
                fid = fopen(fullfile(me.subpaths.bash.local,[fldn{k},'.sh']),'w');
                fwrite(fid,me.bash.(fldn{k}));
                fclose(fid);
            end
            
            % Create  wrapper mfiles
            fldn = fieldnames(me.mcode);
            if isempty(fldn) || force
                me.make_matlab_wrapper(false);
                fldn = fieldnames(me.mcode);
            end
            
            for k = 1:length(fldn)
                fid = fopen(fullfile(me.subpaths.bash.local,[fldn{k},'.m']),'w');
                fwrite(fid,me.mcode.(fldn{k}));
                fclose(fid);
            end

            me.created = true;
        end
            
        function a = get.datafiles(me)
            a = me.data_file_list;
        end
        %%%%
        function set.datafiles(me,a)
            me.data_file_list = struct('local','','remote','','orig','');
            if isempty(a)
                 [~,fn] = fileparts(me.mfile);
                fprintf('\nLocate data files used by %s.\n',fn');
                [files,pth] = uigetfile('*.mat;*.kov;*.txt;*.csv',sprintf('Select data files for %s',fn),'Data files','MultiSelect','on');
                if ischar(files)
                    files = {files};
                end
                if ~isequal(files,0)
                    for k = 1:length(files)
                        me.data_file_list(k).orig = fullfile(pth,files{k});
                        me.data_file_list(k).remote = sprintf('%s/%s',me.subpaths.assets.remote,files{k});                    
                        me.data_file_list(k).local= sprintf('%s/%s',me.subpaths.assets.local,files{k});                    
                    end
                end
            elseif isstruct(a)
                for k = 1:length(a)
                    me.data_file_list(k) = a(k);
                end
            else
                if ~iscell(a)
                     a = {a};
                end
                
                for k = 1:length(a)
                    [pth,fn,ext] =fileparts(a{k});
                   me.data_file_list(k).orig = fullfile(pth,[fn,ext]);
                   me.data_file_list(k).remote = sprintf('%s/%s',me.subpaths.assets.remote,[fn,ext]);
                   me.data_file_list(k).local= sprintf('%s/%s',me.subpaths.assets.local,[fn,ext]);
                end
            end
        end
        
                
        %%%%%%
           
        function set.profile(me,a)
           if ~ismember(a,me.avail_profiles(:,1));
               error('Profile must be one of %s\b',sprintf(' %s,',me.avail_profiles{:,1}))
           end
           me.curr_profile = a;
           if strcmp(a,'high_mem') && isequal(me.queue,'UI')
               warning('UI queue has no high mem nodes, switching to UI-HM')
               me.queue = 'UI-HM';
           end   
           me.curr_nslots = 0;
           me.minmem = [];
        end
        
        
        %%%%%%
        function a = get.profile(me)
           a = me.curr_profile; 
           
        end
        
        %%%%%%
        function set.minmem(me,a)
            if ~isempty(a)
                nodelim = me.profiles.(me.curr_profile).memPerNode;
                if a > nodelim
                    error('\n\nMemory for %s nodes is limited to %iGB. Try a different profile.',upper(me.curr_profile),nodelim)
                end
                me.curr_minmem = a;
            end
            mperslot = me.profiles.(me.curr_profile).memPerSlot;
            minslots = ceil(me.curr_minmem./mperslot);
            me.curr_nslots = max(minslots,me.curr_nslots);                
        end
        
        %%%%%%
        function a = get.minmem(me)
            a = me.curr_minmem;
        end
        %%%%%%
        function a = get.status(me)
           a = 'none'; 
            
           if ~isempty(me.subpaths.status.local)
                fn = fullfile(me.subpaths.status.local,'current');
                if ~exist(fn,'file')
                   return
                end
                fid = fopen(fn,'r');
                a = deblank(fread(fid,'uchar=>char')');
                fclose(fid);
            end
        end
         %%%%%%
        function a = get.jobid(me)
           a = 0; 
            
           if ~isempty(me.subpaths.status.local)
                fn = fullfile(me.subpaths.status.local,'jobid');
                if ~exist(fn,'file')
                   return
                end
                fid = fopen(fn,'r');
                a = deblank(fread(fid,'uchar=>char')');
                fclose(fid);
            end
        end
        %%%%%%
        function a = get.nslots(me)
            a = me.curr_nslots;
        end
        %%%%
        function set.nslots(me,a)
            %%% Set number of slots to request
            if ~isempty(a)
               nodelim = me.profiles.(me.curr_profile).coresPerNode;
                if a > nodelim
                    error('\n\n %s nodes have only %i cores. Try a different profile.',upper(me.curr_profile),nodelim)
                end
         
                me.curr_nslots = a;
            end
            me.minmem = [];
        end
            
        %%%%%%
        function a = get.nparallel(me)
            a = me.nnodes;
        end
        
        %%%%%%
        function set.nparallel(me,a)
            me.nnodes = a;
            me.jindices = 1:a;
        end
        %%%%%
        function set.jobindices(me,a)
            me.jindices = a;
            me.nnodes = length(a);
        end
        %%%%%
        function b = get.jobindices(me)
            b = me.jindices;            
        end
        %%%%%%
    
        function a = get.mailer(me)
           a = me.mailobj; 
        end
        %%%%%%
        function set.mailer(me,a)
            
            persistent mailobj
            if isempty(a) && ~isempty(mailobj)
                me.mailobj = mailobj;
            elseif isempty(a)
                return
            elseif all(ismember(fieldnames(a),fieldnames(me.mailobj)))
                me.mailobj = a;
                mailobj = me.mailobj;
            else
                error('Incorrect field(s)')
            end
            
        end
        
        %%%%%%
        function make_bash_script(me,recreate)
            
            if nargin < 2
                recreate = true;
            end
            if ~exist(me.tempdir,'dir')
                mkdir(me.tempdir);
            end
           % This makes the bash script to submit the job   
           fid = fopen(fullfile(me.tempdir,'temp.sh'),'w+');
           fprintf(fid,'#!/bin/bash\n#\n#Created %s\n#',datestr(now));
           for k = 1:size(me.qsub_opts,1)
               fprintf(fid,'\n#$%s %s',me.qsub_opts{k,:});
           end
%            fprintf(fid,'BASEPATH=%s',me.path.remote);
           fprintf(fid,'\n');
           fprintf(fid,'\nexport MATLABPATH=%s',me.subpaths.mfiles.remote);
           fprintf(fid,'\n\n# Make SGE_TASK_ID empty if set to "undefined"\n[ ${SGE_TASK_ID:-NULL} == undefined ] && SGE_TASK_ID=\n');
%            fprintf(fid,'\nexport OUTPUTDIR=%s\n',me.subpaths.output.remote);
           fprintf(fid,'\ncd %s\n',me.subpaths.bash.remote);
           
           [~,fn] = fileparts(me.mfile);
%          fprintf(fid,'\n\nmodule load matlab/%s',me.use_matlab_version);
           fprintf(fid,'\n\nmodule load matlab');
           fprintf(fid,'\n\n# wrapper function for %s\n%s -r "mwrapper($SGE_TASK_ID)" \n',fn,me.neon_matlab_bin);
           frewind(fid);
           me.bash(1).submit = fread(fid,'uchar=>char')';
           fclose(fid);
           
           if me.created && recreate
               me.create_job;
           end
%            delete('temp.sh')
           
        end
          
        %%%%%%
        function make_matlab_wrapper(me,recreate)
            
            if nargin < 2
               recreate=true; 
            end
                
            % This makes the matlab wrapper script
            fid = fopen(fullfile(me.tempdir,'tempwrap.m'),'w+');
            fprintf(fid,'function mwrapper(jobindexi)\n\n');
            
            fprintf(fid,'%%\n%% This is a wrapper for %s',me.title);
            fprintf(fid,'\n%%\n%% Created %s\n%%\n\n',datestr(now));
            fprintf(fid,'\n\nif nargin < 1, jobindexi=0; end\n\n');
            
            fprintf(fid,'jobindices = [');
            fprintf(fid,'%i ',me.jobindices);
            fprintf(fid,'];\n\n');            
            fprintf(fid,'if jobindexi > 0\n\tjobindex = jobindices(jobindexi);\nelseif length(jobindices)>0\n\tjobindex=jobindices;\nelse\n\tjobindex=0;\nend\n\n');
            fprintf(fid,'inputdir = ''%s'';\n',me.subpaths.assets.remote);
            fprintf(fid,'outputdir = ''%s'';\n',me.subpaths.output.remote);
            fprintf(fid,'statusdir = ''%s'';\n',me.subpaths.status.remote);
            fprintf(fid,'jobsdir = ''%s'';\n',me.neon_jobs_path);
            
            [~,fnames,exts] = arrayfun(@(x)fileparts(x.remote),me.datafiles,'uniformoutput',false);
            fnames = cat(1,fnames,exts);
            fprintf(fid,'\ninputfiles = {\n%s\t\t};\n',sprintf('\t\t\t''%s%s''\n',fnames{:}));
           
            fprintf(fid,'\nsystem(sprintf(''echo "$(date "+%%%%Y%%%%m%%%%d %%%%T %%%%z") START $(cat %%s/jobid) %%i %s  %s" >> %%s/jobs.log'',statusdir,jobindex,jobsdir));\n',me.title,me.uuid);
            
            [pth,fn,~] = fileparts(me.mfile);
            addpath(pth);
            argsin = {'inputdir','outputdir','inputfiles','jobindex'};
            fprintf(fid,'\ntry\n\n');
            fprintf(fid,'\t%s',fn);
            
            try
                nin = nargin(me.mfile);
                if nin==-1, nin = length(nargsin);end
                if nin >0
                    fprintf(fid,'(%s%s)',argsin{1},sprintf(',%s',argsin{2:nin}) );                    
                end
            catch err
                if ~strcmp(err.identifier,'MATLAB:nargin:isScript')
                    error('The m-file must be a script or a function')
                end
            end
            fprintf(fid,'\n\tsystem(sprintf(''echo "$(date "+%%%%Y%%%%m%%%%d %%%%T %%%%z") FINISHED $(cat %%s/jobid) %%i %s  %s" >> %%s/jobs.log'',statusdir,jobindex,jobsdir));\n',me.title,me.uuid);
         
            fprintf(fid,'\n\ncatch err\n');
            fprintf(fid,'\n\tsystem(sprintf(''echo  "$(date "+%%%%Y%%%%m%%%%d %%%%T %%%%z") ERROR $(cat %%s/jobid) %%i %s  %s %%s" >> %%s/jobs.log'',statusdir,jobindex,err.message,jobsdir));\n',me.title,me.uuid);
            fprintf(fid,'\n\tsystem(sprintf(''echo error > %%s/current'',statusdir))\n');
            fprintf(fid,'\tsave(fullfile(outputdir,''error''),''err'')\n');
            fprintf(fid,'\nend');
            
            fprintf(fid,'\n');
            frewind(fid);
            me.mcode(1).mwrapper= fread(fid,'uchar=>char')';
            fclose(fid);
%            delete('tempwrap.m')
            if me.created && recreate
               me.create_job;
           end

         end
              %%%%%%%
        function a = get.qsub_opts(me)
            %%% Get options for q sub
            
            me.qopts=  {'-N ',me.title
                     '-q ',me.queue
                     '-l ',me.profile
                     '-r ',me.rerun_if_aborted 
                       '-o ',fullfile(me.subpaths.log.remote,'output')
                       '-e ',fullfile(me.subpaths.log.remote,'error')};
            if me.nnodes == 1
                     me.qopts(end+1,:) = {'-pe ',sprintf('smp %i',me.nslots)};
%             else
%                 error('distributed parallel not implemented yet')
            else
                 me.qopts(end+1,:) = {'-pe ',sprintf('smp %i',me.nslots)};
                me.qopts(end+1,:) = {'-t ',sprintf('1-%i',me.nnodes)};
                
            end
            if ~isempty(me.mailer(1).email)
               me.qopts(end+1,:) = {'-M ',me.mailer(1).email}; 
               me.qopts(end+1,:) = {'-m ',me.mailer(1).mail_events}; 
            end
            
            a = cat(1,me.qopts,me.qopts_extra);
            
        end
        %%%%%
        
        function a=get.qacct(me)
            
            fn = fullfile(me.subpaths.status.local,'qacct');
            if exist(fn,'file')
                fid = fopen(fn,'r');
                a = fread(fid,'uchar=>char')';
                fclose(fid);
            else
                a='';
            end
        end

        %%%%%%
        function close(me)
            % Close the request. Files on the neon server will be deleted.
            if ~isempty(me.subpaths.status.local) && exist(me.subpaths.status.local,'dir')
                fid = fopen(fullfile(me.subpaths.status.local,'current'),'w');
                fprintf(fid,'closed');
                fclose(fid);
            end
        end
        
        %%%%%%%    
        function set.qsub_opts_add(me,a)
            me.qopts_extra = a;
        end
        %%%%%%%
        function a = get.qsub_opts_add(me)
            a = me.qopts_extra;
        end
        %%%%%%%
        function cluster_usage(me)
            % Open the web page that shows current data about the cluster processing lod 
           web(me.usage_url) 
        end
        %%%%%%%
        function isscanned = checkscan(me)
            %%% Make sure the jobs directory has been scanned by
            %%% scanjobs.sh
           agelimit = 30; % maximum age in minutes
           scf = dir(fullfile(me.neonpath,'jobs','scanned'));
            
           isscanned = ~isempty(scf) && (now - scf.datenum)*24*60 < agelimit;
                        
           
        end
          %%%%%%%
        function overquota = get.overquota(me)
         
            if exist(fullfile(me.neonpath,'jobs','scanned'),'file')
               fid = fopen(fullfile(me.neonpath,'jobs','scanned'),'r');
               txt = fread(fid,'uchar=>char')';
               fclose(fid);
               re = regexp(txt,'disk use:\s*(\d*)\%','tokens','once');
               try
                    use = str2double(re{1});
                    overquota = use >= me.quotalimit;
               catch
                   overquota=false;
               end
            else
                overquota=false;
            end                          
           
        end 
        
        %%%%%%
        
        function a = get.finish(me)
           a = me.finish_handle;           
        end
        %%%%%%
        
        function set.finish(me,fun)
           
            if isa(fun,'function_handle')
                me.finish_handle = fun;      
            elseif ~isempty(fun)
                error('The finish object must be a function handle.')
            end
            
        end
        %%%%%%
        
        function monitor(me)
            % Create and run a timer that will check on the state of the
            % process intermittently
            period = 10; %Period of timer events in seconds
            me.timer = timer('Period',period,...
                              'ExecutionMode','FixedRate',...
                              'TimerFcn',@(varargin)me.checkstatus(varargin{:})); %#ok<CPROP>
            start(me.timer)
            
        end
        %%%%%%%%
        
        function set.neonpath(me,a)
            
            persistent xnepath
            if isempty(a) 
                a = xnepath;
            else 
                me.curr_neonpath=a;
            end
            xnepath = a;
        end
        function a = get.neonpath(me)
            a = me.curr_neonpath;
        end
        %%%%%%%%
        function default_finish(me,varargin)
            % Finish the job: Copy output files to a local directory and
            % close the request.
            dd = dir(fullfile(me.subpaths.output.local,'*'));
            ddlog = dir(fullfile(me.subpaths.log.local,'*'));
            if ~isempty(me.local_save_dir) &&~exist(me.local_save_dir,'dir')
                mkdir(me.local_save_dir)
%                 copyfile(me.subpaths.log.local,fullfile(me.local_save_dir,'log'))
%                 copyfile(me.subpaths.status.local,fullfile(me.local_save_dir,'log'))
            end
            if ~isempty(me.local_save_dir) &&~exist(fullfile(me.local_save_dir,'log'),'dir')
                mkdir(fullfile(me.local_save_dir,'log'))
            end
            if ~isempty(ddlog(3:end))
                copyfile(fullfile(me.subpaths.log.local,'*'),fullfile(me.local_save_dir,'log'),'f')
            end
            if ~isempty(dd(3:end))
                copyfile(fullfile(me.subpaths.output.local,'*'),me.local_save_dir,'f')
            end
            me.close;
            if ~isempty(me.timer) && isvalid(me.timer)
                stop(me.timer);
            end
            delete(me.timer);
        end
        
        function delete(me)
            if ~isempty(me.timer) && isvalid(me.timer)
                stop(me.timer)
            end
            delete(me.timer)
        end
      
        
    end    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    methods ( Access = protected )
        
        function checkstatus(me,varargin)
            % Callback function for the timer.
            switch me.status
                case 'finished'
                   me.finish(me);
            %        delete(timer)
                case 'error'
                    stop(me.timer);
                otherwise
                    return
            end
        end
    end


end
 