#!/usr/bin/env python3
"""Local daily planner. No remote service, external dependencies or background AI calls."""
import argparse
import copy
from datetime import date, datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import secrets
import subprocess
import threading
from urllib.parse import urlsplit, parse_qs
from zoneinfo import ZoneInfo

TZ = ZoneInfo('Asia/Shanghai')
STATES = {'planned','running','done','paused','cancelled'}


def validate_day(day, value):
    if date.fromisoformat(day).isoformat() != day:
        raise ValueError('日期格式无效')
    if not isinstance(value,dict) or not isinstance(value.get('tasks'),list) or len(value['tasks']) > 100:
        raise ValueError('日程格式无效，单日最多 100 项')
    tasks, ids = [], set()
    for item in value['tasks']:
        t = {k:item.get(k) for k in ['id','title','category','color','start','end','nextDay','status','note','block','startedAt']}
        if not isinstance(t['id'],str) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}',t['id']) or t['id'] in ids:
            raise ValueError('事项 ID 无效或重复')
        ids.add(t['id'])
        for key,limit in [('title',160),('category',30),('note',3000)]:
            if not isinstance(t[key],str) or len(t[key])>limit or (key!='note' and not t[key].strip()):
                raise ValueError('请填写有效的事项名称和类型')
        if not isinstance(t['color'],str) or not re.fullmatch(r'#[0-9a-fA-F]{6}',t['color']):
            raise ValueError('颜色无效')
        if t['status'] not in STATES or not isinstance(t['block'],bool) or not isinstance(t['nextDay'],bool):
            raise ValueError('状态无效')
        if not isinstance(t['start'],str) or not isinstance(t['end'],str):
            raise ValueError('时间无效')
        if t['start'] or t['end']:
            if not all(re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d',t[k]) for k in ('start','end')):
                raise ValueError('请同时填写开始与结束时间')
            start,end=task_times(day,t)
            if end <= start or end-start>timedelta(hours=24):
                raise ValueError('结束时间需晚于开始时间；跨午夜请勾选次日，时长不超过 24 小时')
        if t['startedAt'] is not None:
            try:
                d=datetime.fromisoformat(t['startedAt'])
                if d.tzinfo is None: raise ValueError()
            except (ValueError,TypeError):
                raise ValueError('计时信息无效')
        elapsed=item.get('elapsedSeconds',0)
        if isinstance(elapsed,bool) or not isinstance(elapsed,(int,float)) or not math.isfinite(elapsed) or not 0<=elapsed<=315360000:
            raise ValueError('累计用时无效')
        t['elapsedSeconds']=elapsed
        tasks.append(t)
    if sum(t['status']=='running' for t in tasks)>1:
        raise ValueError('同一天只能有一个正在进行的事项')
    return {'date':day,'tasks':tasks}


def task_times(day,t):
    start=datetime.fromisoformat(f"{day}T{t['start']}:00").replace(tzinfo=TZ)
    end=datetime.fromisoformat(f"{day}T{t['end']}:00").replace(tzinfo=TZ)
    if t['nextDay']: end+=timedelta(days=1)
    return start,end


def calendar_ics(day,data):
    def esc(s):
        return s.replace('\\','\\\\').replace('\r','').replace('\n','\\n').replace(';','\\;').replace(',','\\,')
    def stamp(dt): return dt.astimezone(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//daaaay//Daily planner//ZH','CALSCALE:GREGORIAN','X-WR-CALNAME:daaaay']
    for t in data['tasks']:
        if not t['start'] or t['status'] in ('paused','cancelled'): continue
        start,end=task_times(day,t)
        lines+=['BEGIN:VEVENT',f"UID:{day}-{t['id']}@daaaay.local",f"SEQUENCE:{data.get('revision',0)}",'DTSTAMP:'+stamp(datetime.now(timezone.utc)),'DTSTART:'+stamp(start),'DTEND:'+stamp(end),'SUMMARY:'+esc(t['title']),'DESCRIPTION:'+esc(t['note']),'CATEGORIES:'+esc(t['category']),'END:VEVENT']
    lines.append('END:VCALENDAR')
    folded=[]
    for line in lines:
        chunk=''
        for ch in line:
            if len((chunk+ch).encode())>75:
                folded.append(chunk)
                chunk=' '
            chunk+=ch
        folded.append(chunk)
    return ('\r\n'.join(folded)+'\r\n').encode()


def atomic_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.'+secrets.token_hex(4)+'.tmp')
    tmp.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
    os.replace(tmp,path)


class Store:
    def __init__(self,root):
        self.root=Path(root)
        self.lock=threading.RLock()
        self.recover_move()
    def path(self,day):
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}',day): raise ValueError('日期无效')
        date.fromisoformat(day)
        return self.root/'days'/f'{day}.json'
    def transaction_path(self):
        return self.root/'transactions'/'move-task.json'
    def recover_move(self):
        with self.lock:
            journal_path=self.transaction_path()
            if not journal_path.exists(): return
            journal=json.loads(journal_path.read_text())
            atomic_json(self.path(journal['sourceDay']),journal['sourceBefore'])
            atomic_json(self.path(journal['targetDay']),journal['targetBefore'])
            self._sync_blocker_days({journal['sourceDay'],journal['targetDay']})
            journal_path.unlink()
    def read(self,day):
        with self.lock:
            p=self.path(day)
            return json.loads(p.read_text()) if p.exists() else {'date':day,'revision':0,'tasks':[],'events':[]}
    def _sync_blocker_days(self,days):
        with self.lock:
            # Persist website restriction times; do not enable or modify Chrome here.
            block_path=self.root/'blocker'/'schedule.json'
            block=json.loads(block_path.read_text()) if block_path.exists() else {'version':1,'windows':[]}
            block['windows']=[w for w in block['windows'] if not any(w['id'].startswith(day+'-') for day in days)]
            for day in sorted(days):
                for t in self.read(day)['tasks']:
                    if t['block'] and t['start'] and t['status'] in ('planned','running'):
                        start,end=task_times(day,t)
                        block['windows'].append({'id':day+'-'+t['id'],'start':start.isoformat(),'end':end.isoformat()})
            atomic_json(block_path,block)
    def save(self,day,body):
        clean=validate_day(day,body)
        with self.lock:
            old=self.read(day)
            if body.get('revision')!=old['revision']: raise RuntimeError('另一处更新了日程，请刷新后再保存')
            now=datetime.now(TZ).isoformat(timespec='seconds')
            before={t['id']:t for t in old['tasks']}
            # The server owns timers, including requests from an older web tab.
            # Only explicit status transitions start/settle an interval.
            for t in clean['tasks']:
                prev=before.get(t['id'],{})
                elapsed=prev.get('elapsedSeconds',0)
                was_running=prev.get('status')=='running'
                if was_running and t['status']!='running' and prev.get('startedAt'):
                    elapsed+=max(0,(datetime.fromisoformat(now)-datetime.fromisoformat(prev['startedAt'])).total_seconds())
                t['elapsedSeconds']=elapsed
                t['startedAt']=(prev.get('startedAt') or now) if was_running and t['status']=='running' else now if t['status']=='running' else None
            timing=lambda tasks:[(t['id'],t['start'],t['end'],t['nextDay'],t['status'] in ('paused','cancelled','done'),t['block']) for t in tasks]
            changed=timing(old['tasks'])!=timing(clean['tasks'])
            events=old.get('events',[])
            source='native_user' if body.get('source')=='native_user' else 'web_user'
            for t in clean['tasks']:
                if before.get(t['id'])!=t:
                    events.append({'at':now,'source':source,'id':t['id'],'title':t['title'],'status':t['status']})
            for t in old['tasks']:
                if not any(n['id']==t['id'] for n in clean['tasks']):
                    events.append({'at':now,'source':source,'id':t['id'],'status':'deleted'})
            clean.update(revision=old['revision']+1,updatedAt=now,events=events[-500:],monitorSyncPending=changed or old.get('monitorSyncPending',False))
            atomic_json(self.path(day),clean)
            self._sync_blocker_days({day})
            return clean

    def move_task(self,source_day,target_day,task_id,source_revision,target_revision,replacement):
        with self.lock:
            if source_day==target_day: raise ValueError('来源日期和目标日期必须不同')
            source,target=self.read(source_day),self.read(target_day)
            if source['revision']!=source_revision or target['revision']!=target_revision:
                raise RuntimeError('另一处更新了日程，请刷新后再移动')
            index=next((i for i,t in enumerate(source['tasks']) if t['id']==task_id),None)
            if index is None: raise ValueError('要移动的事项不存在')
            if source['tasks'][index]['status']=='running':
                raise ValueError('请先暂停正在计时的事项，再修改日期')
            if any(t['id']==task_id for t in target['tasks']):
                raise ValueError('目标日期已存在同 ID 事项')
            moved=dict(source['tasks'][index])
            # Date edits never own an interval's state or accumulated time.
            # Preserve the source timer snapshot even if a stale client sends
            # status, startedAt, or elapsedSeconds in its replacement body.
            for field in ('title','category','color','start','end','nextDay','note','block'):
                if field in replacement: moved[field]=replacement[field]
            moved['id']=task_id
            source_clean=validate_day(source_day,{'tasks':source['tasks'][:index]+source['tasks'][index+1:]})
            target_clean=validate_day(target_day,{'tasks':target['tasks']+[moved]})
            now=datetime.now(TZ).isoformat(timespec='seconds')
            source_clean.update(revision=source_revision+1,updatedAt=now,
                events=(source.get('events',[])+[{'at':now,'source':'native_user','id':task_id,'status':'moved_out'}])[-500:],
                monitorSyncPending=True)
            target_clean.update(revision=target_revision+1,updatedAt=now,
                events=(target.get('events',[])+[{'at':now,'source':'native_user','id':task_id,'status':moved['status']}])[-500:],
                monitorSyncPending=True)
            journal={'sourceDay':source_day,'targetDay':target_day,
                'sourceBefore':source,'targetBefore':target}
            atomic_json(self.transaction_path(),journal)
            try:
                atomic_json(self.path(source_day),source_clean)
                atomic_json(self.path(target_day),target_clean)
                self._sync_blocker_days({source_day,target_day})
                self.transaction_path().unlink()
                return {'source':source_clean,'target':target_clean}
            except Exception:
                self.recover_move()
                raise


def make_handler(store,html_path,allow_calendar=True):
    token=secrets.token_urlsafe(32)
    class Handler(BaseHTTPRequestHandler):
        def respond(self,status,data,ctype='application/json; charset=utf-8',extra=None):
            raw=data if isinstance(data,bytes) else json.dumps(data,ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header('Content-Type',ctype)
            self.send_header('Content-Length',str(len(raw)))
            self.send_header('Cache-Control','no-store')
            self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('Content-Security-Policy',"frame-ancestors 'none'")
            for k,v in (extra or {}).items(): self.send_header(k,v)
            self.end_headers()
            self.wfile.write(raw)
        def allowed(self,write=False):
            expected=f'127.0.0.1:{self.server.server_port}'
            if self.headers.get('Host')!=expected: return False
            origin=self.headers.get('Origin')
            if origin and origin!='http://'+expected: return False
            if write and (origin!='http://'+expected or self.headers.get('X-Daaaay-Token')!=token): return False
            return True
        def do_GET(self):
            if not self.allowed(): return self.respond(403,{'error':'来源不允许'})
            url=urlsplit(self.path)
            query=parse_qs(url.query)
            try:
                if url.path=='/': return self.respond(200,html_path.read_bytes(),'text/html; charset=utf-8')
                if url.path=='/api/bootstrap':
                    days=sorted(p.stem for p in (store.root/'days').glob('????-??-??.json'))
                    return self.respond(200,{'token':token,'today':datetime.now(TZ).date().isoformat(),'days':days})
                day=query.get('date',[''])[0]
                if url.path=='/api/day': return self.respond(200,store.read(day))
                if url.path=='/api/calendar':
                    return self.respond(200,calendar_ics(day,store.read(day)),'text/calendar; charset=utf-8',{'Content-Disposition':f'attachment; filename="daaaay-{day}.ics"'})
                return self.respond(404,{'error':'页面不存在'})
            except (ValueError,KeyError,TypeError): return self.respond(400,{'error':'参数无效'})
        def do_POST(self):
            if not self.allowed(True): return self.respond(403,{'error':'来源或访问令牌无效'})
            if self.headers.get('Content-Type','').split(';')[0]!='application/json': return self.respond(415,{'error':'仅接受 JSON'})
            try:
                length=int(self.headers.get('Content-Length','0'))
                if length<=0 or length>262144: return self.respond(413,{'error':'请求过大'})
                body=json.loads(self.rfile.read(length))
                day=body.get('date','')
                if self.path=='/api/day': return self.respond(200,store.save(day,body))
                if self.path=='/api/task/move':
                    if body.get('source')!='native_user': raise ValueError('移动事项来源无效')
                    return self.respond(200,store.move_task(
                        body['sourceDate'],body['targetDate'],body['taskId'],
                        body['sourceRevision'],body['targetRevision'],body['task']
                    ))
                if self.path=='/api/calendar/open':
                    if not allow_calendar: return self.respond(403,{'error':'测试环境不打开日历'})
                    data=store.read(day)
                    if not any(t['start'] and t['status'] not in ('paused','cancelled') for t in data['tasks']):
                        raise ValueError('没有可导入的定时事项')
                    dest=store.root/'exports'/f'daaaay-{day}.ics'
                    dest.parent.mkdir(exist_ok=True)
                    dest.write_bytes(calendar_ics(day,data))
                    subprocess.run(['/usr/bin/open',str(dest)],check=True,timeout=10)
                    return self.respond(200,{'ok':True})
                return self.respond(404,{'error':'接口不存在'})
            except RuntimeError as e: return self.respond(409,{'error':str(e)})
            except (ValueError,KeyError,TypeError) as e: return self.respond(400,{'error':str(e)})
            except (OSError,subprocess.SubprocessError): return self.respond(500,{'error':'操作未完成，请重试或下载日历文件'})
        def log_message(self,*args): pass
    return Handler


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--port',type=int,default=18765)
    parser.add_argument('--no-calendar-open',action='store_true')
    args=parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1',args.port),make_handler(Store(args.root),Path(__file__).with_name('index.html'),not args.no_calendar_open)).serve_forever()
