
function blkdat = get_protocol_labwiki(blocksubject,user,passwd)

%Retrieves protocol data from the labwiki site
%
% See also mwapi_old

baseurl = 'https://saccade.neurosurgery.uiowa.edu/labwiki/';

defuser = 'Lab';


persistent password  uid


if nargin >1
    defuser = user;
    uid = user;
end
if nargin > 2
    password = passwd;    
end

re={};
if nargin > 0
    if ~iscell(blocksubject)
        blocksubject = {blocksubject};
    end
    re = regexp(blocksubject,'(\d*)','tokens');
    re = cat(1,re{:});
  
end


if ~isempty(password)
    [~,noerr] = urlread(baseurl,'Authentication','Basic','Username',deblank(uid),'Password',deblank(password));
    getpasswd = ~noerr;
else
    getpasswd = true;
 
end

while getpasswd
    uid = input(sprintf('\nEnter labwiki username [%s]: ',defuser),'s');
    if isempty(uid)
        uid=defuser;
    end
    try
        password = getpw('Enter password: ');
        noerr=true;
    catch
        fprintf('\nEnter password: ')
        [~,password] = system('read'); 
        [~,noerr] = urlread(baseurl,'Authentication','Basic','Username',deblank(uid),'Password',deblank(password));
        if ~noerr
            warning('Password, username or other error.');
        end
    end
    getpasswd = ~noerr;
     
end

if nargin==0;
%     url = sprintf('%sindex.php/Category:Subject',baseurl);
%     subjs = ask_labwiki('[[Category:Subject]]');
  subjs = mwapi_old(struct('action','ask','query','[[Category:Subject]]|limit=5000|link=none'),uid,password);
  subjs = regexp(subjs,'"results":{(.*)}','tokens','once');
%   htxt = urlread(url,'Authentication','Basic','Username',deblank(uid),'Password',deblank(password));
%     selist = regexp(htxt,'>Subject/(\d*)<','tokens');
    selist = regexp(subjs,'"Subject/([^"]*)":','tokens');    
    selist = [selist{:}]; selist = [selist{:}];
    sub = listdlg('liststring',selist,'promptstring','Choose a subject...');
    re = selist(sub)';
    re = regexp(re{1},'(.*)','tokens');
end

 rep = @(tx)regexprep(tx,'<.*?>','');
if size(re,2)==1
    
%     questr = ['+%3A%3A+',re{1},sprintf('+%%7C%%7C+%s',re{:})];
%     tbs3={}; 
        questr=cellfun(@(x)sprintf('[[Category:Recording Block]][[Has subject::Subject/%s]]|?Has protocol|?Has subprotocol|?Has event start',x),[re{:}],'uniformoutput',false);
%         tab = mwapi_old(struct('action','ask','query',questr));
        tab = ask_labwiki_old(questr,uid,password);
    %    url = sprintf('%sindex.php/Subject/%s',baseurl,re{1});
%              url = sprintf('%sindex.php?title=Special:Ask&offset=0&limit=500&q=%%5B%%5BCategory%%3ARecording+Block%%5D%%5D%%5B%%5BHas+subject%s%%5D%%5D&p=format%%3Dbroadtable&po=%%3FHas+protocol%%0A%%3FHas+subprotocol%%0A%%3FHas+event+start%%0A',...
%                     baseurl,questr);            
%         htxt = urlread(url,'Authentication','Basic','Username',deblank(uid),'Password',deblank(password));
%           tbs = regexp(htxt,'<tr class="row(.*?)</tr>','tokens');
%           tbs2 = regexp([tbs{:}],'<td.*?>(.*?)</td>','tokens');
%           tbs3 = cat(1,tbs3,tbs2{:});
        if ~isfield(tab,'Has_event_start')
            for k = 1:length(tab)
                tab(k).Has_event_start = '';
            end
      else
            for k = 1:length(tab)
                tab(k).Has_event_start = datestr(str2double(tab(k).Has_event_start)/3600/24 +datenum('1/1/1970'),'yyyy/mm/dd HH:MM:SS');
            end
        end
          fmtstr = '%-15s%-20s%-30s%-50s';
          head = sprintf(fmtstr,'Block','Protocol','Subprotocol','time');
%           liststr = [head,cellfun(@(a,b,c,d) sprintf(fmtstr,rep(a),rep(b),rep(c),rep(d)),[tbs3{:,1}],[tbs3{:,2}],[tbs3{:,3}],[tbs3{:,4}],'uniformoutput',false)];
          liststr = [head,cellfun(@(a,b,c,d) sprintf(fmtstr,rep(a),rep(b),rep(c),rep(d)),{tab.main},{tab.Has_protocol},{tab.Has_subprotocol},{tab.Has_event_start},'uniformoutput',false)];
          blk = listdlg('liststring',liststr,'promptstring','Choose a Block...','listsize',[500 400]);
          blk(blk==1)=[];
          blocks = {tab(blk-1).main};
else
     blocks = cellfun(@(a,b)sprintf('%s-%s',a,b),[re{:,1}],[re{:,2}],'uniformoutput',false);
end
rep2= @(x)regexprep(deblank(rep(x)),'^[\s]*','');
rep3= @(x)regexprep(rep2(x),'[\s]','_');
rep4= @(x)regexprep(rep3(x),'[:.]','');
fldns = {'subject_id','protocol','subprotocol','notes','montage','url','date','block','record_id','subject','tdt_tank','cruprotocol_url','protocol_recnum','lozchannels','hizchannels','tables','identifier','time','failed','error','system','recording_system','properties'};
for k = 1:length(blocks)
   try
    block=blocks{k};
    url = sprintf('%sindex.php/%s', baseurl,block);         
    q = mwapi_old(struct('action','parse','page',block,'prop','wikitext'),uid,password);
    q = regexprep(q,'\\u','\\\\u');
    blktxt = sprintf(q);
    props = regexp(blktxt,'{{#set:.*}}','match','once');
    blktxt = regexprep(blktxt,'{{#set:.*}}','');
    
%     htxt = urlread(url,'Authentication','Basic','Username',deblank(uid),'Password',deblank(password));
%     blktxt = regexp(htxt,'.*id="Contacts','match','once');
%     tb = regexp(blktxt,'<th>(.*?)</th>\s*<td>(.*?)</td>','tokens');

     notes = regexpi(blktxt,'\|Notes=([^\|]*?)[\|\}]','tokens','once');
     blktxt = regexprep(blktxt,'\|Notes=[^\|]*?[\|\}]','');
     tb = regexp(blktxt,'|([^\n|=]*?)=([^\n]*)','tokens');
    tb= [cellfun(@(x)rep2(x),cat(1,tb{:})','uniformoutput',false),{'notes';notes}];
    tb(1,:) = rep4(tb(1,:));
    tb(:,cellfun(@isempty,tb(1,:)))=[];
    tb(cellfun(@isempty,tb))={''};
    table = struct(tb{:});
    
%     blkdat(k).subject_id = table.Subject;
    if k >1
        fldns = fieldnames(blkdat)';
    end
    fldns(2,:)={''};
    blk = struct(fldns{:});
    if ~isempty(props)
        tb = regexp(props,'|([^\n|=]*?)=([^\n]*)','tokens');
        tb= cellfun(@(x)rep2(x),cat(1,tb{:})','uniformoutput',false);
        tb(1,:) = rep4(tb(1,:));
        tb(:,cellfun(@isempty,tb(1,:)))=[];
        tb(cellfun(@isempty,tb))={''};
        blk.properties= struct(tb{:});
    end
%     blk = struct('subject_id',table.subject,'protocol','','subprotocol','','notes','','montage','','url','','date','');
%     blkdat(k).block = sprintf('%s-%s',table.Subject,table.Block);
 
%     blkdat(k).record_id = 'labwiki';
    blk.record_id = 'labwiki';
    fldns=fieldnames(table);
    for kk = 1:length(fldns)
        blk.(lower(fldns{kk}))=table.(fldns{kk});
    end
    blk.subject_id = blk.subject;
    blk.block = sprintf('%s-%s',table.subject,table.block);
    if isfield(blk,'tdt_tank')
        blk.tank = blk.tdt_tank;
    end
    blkdat(k) = blk;
%     blkdat(k).protocol = table.Protocol;
%     blkdat(k).subprotocol = table.Subprotocol;
% %     memo = regexp(blktxt,'id="Notes".*?</h2>(.*?)<h2>','tokens','once');
% %     blkdat(k).memo = rep(regexprep(memo{1},'<br\s*/>','\n'));
%     blkdat(k).memo = table.Notes;
%     blkdat(k).Montage = table.Montage;
%     blkdat(k).url = url;
%     blkdat(k).date = date;
    if isempty(blkdat(k).montage)
        blkdat(k).montage = sprintf('Subject/%s/Montage',blkdat(k).subject);
    end
    montage = sprintf(mwapi_old(struct('action','parse','page',blkdat(k).montage,'prop','wikitext'),uid,password));
  

    %%% Channel data
%     chntxt = regexp(htxt,'id="Contacts.*','match','once');
%     chgrp = regexp(chntxt,'<th.*?Group [lL]abel.*?</table>','match');
    chgrp = regexp(montage,'{{Contact group[^}]*}}','match');
    
    himp = [];
    limp =[];
    offset = 0;
    lastlabel='';
    for kk = 1:length(chgrp)
%           tb = regexp(chgrp{kk},'<th>(.*?)</th>(.*?)</tr>','tokens');
          tb = regexp(chgrp{kk},'\|(.*?)=([^\n|]*)','tokens');            
          tb = rep2(cat(1,tb{:}))';
          tb(1,:) = rep4(rep3(tb(1,:)));
          chntable = struct(tb{:});
          if ~isequal(chntable.label,lastlabel)
              offset = 0;
          end
          lastlabel = chntable.label;
%           chans = str2num(chntable.Recording_channels);
%           contacts = str2num(chntable.Contact_numbers);
          chans = str2num(chntable.channels);
          contacts = str2num(chntable.contacts);
          number = (1:length(chans))+offset;
          n = length(number);
%           chstruct = struct('label',chntable.Group_label,'number',num2cell(number),'channel',num2cell(chans)','contact',num2cell(contacts)');
          chstruct = struct('label',chntable.label,'number',num2cell(number),'channel',num2cell(chans),'contact',num2cell(contacts));
%           switch chntable.Impedance
          switch chntable.impedance
              case 'Low'
                  limp = [limp,chstruct];
              case 'High'
                  himp = [himp,chstruct];
                  
          end
          offset = number(end);
    end
    blkdat(k).lozchannels = limp;
    blkdat(k).hizchannels = himp;
    blkdat(k).tables = table;
    blkdat(k).identifier = blkdat(k).block;
%     blkdat(k).date = table.Date;    
%     blkdat(k).time = table.Time;
    blkdat(k).date = table.date;    
    if isfield(table,'time')
        blkdat(k).time = table.time;
    else
        blkdat(k).time = datestr(datenum(table.date),'HH:MM:SS');
    end
    if isfield(table,'tdttank')
%     blkdat(k).tank = table.Data_tank;
        blkdat(k).tank = table.tdttank;
    end
    blkdat(k).failed=false;
    blkdat(k).error ='';
   catch err
       blkdat(k).failed=true;
       blkdat(k).error =err;
   end
   
end

    
