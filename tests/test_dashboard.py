import sys
import unittest
import tempfile
import json
import threading
import http.client
import copy
import queue
from datetime import datetime
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'web'))
import server
from server import validate_day, calendar_ics, Store, make_handler


class DashboardTest(unittest.TestCase):
    def task(self, **kw):
        return dict(dict(id='study-1', title='学习,Agent;第一课', category='AI 学习', color='#7466bd', start='14:00', end='15:30', nextDay=False, status='planned', note='先打开笔记\n写下一个问题', block=True), **kw)

    def test_rejects_ambiguous_and_reversed_times(self):
        for fields in ({'end':'13:00'}, {'start':'25:00'}, {'start':''}, {'color':'url(evil)'}, {'status':'unknown'}):
            task = self.task()
            task.update(fields)
            with self.assertRaises(ValueError):
                validate_day('2026-09-06', {'tasks':[task]})

    def test_validates_cross_midnight_and_untimed_tasks_without_inventing_times(self):
        task = self.task()
        task.update(start='23:30', end='00:30', nextDay=True)
        result = validate_day('2026-09-06', {'tasks':[task]})
        self.assertTrue(result['tasks'][0]['nextDay'])
        task.update(start='',end='',nextDay=False)
        self.assertEqual(validate_day('2026-09-06',{'tasks':[task]})['tasks'][0]['start'],'')

    def test_ics_has_correct_utc_escaping_stable_uid_and_excludes_paused_tasks(self):
        task=self.task()
        other=dict(task,id='paused',status='paused')
        data={'tasks':[task,other], 'revision':3}
        ics=calendar_ics('2026-09-06',data).decode()
        self.assertIn('DTSTART:20260906T060000Z\r\n',ics)
        self.assertIn('DTEND:20260906T073000Z\r\n',ics)
        self.assertIn('SUMMARY:学习\\,Agent\\;第一课',ics)
        self.assertIn('UID:2026-09-06-study-1@daaaay.local',ics)
        self.assertEqual(ics.count('BEGIN:VEVENT'),1)
        self.assertIn('SEQUENCE:3',ics)

    def test_ics_folds_utf8_without_splitting_characters(self):
        task=self.task()
        task['title']='学习人工智能'*40
        result=calendar_ics('2026-09-06',{'tasks':[task]})
        for line in result.split(b'\r\n'):
            self.assertLessEqual(len(line),75)
            line.decode('utf-8')

    def test_save_conflict_and_cancel_preserve_other_dates(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text(json.dumps({'version':1,'windows':[{'id':'2026-09-07-other','start':'2026-09-07T10:00:00+08:00','end':'2026-09-07T11:00:00+08:00'}]}))
            store=Store(root)
            task=self.task()
            result=store.save('2026-09-06',{'revision':0,'tasks':[task]})
            self.assertEqual(result['revision'],1)
            self.assertEqual(len(json.loads((root/'blocker/schedule.json').read_text())['windows']),2)
            with self.assertRaises(RuntimeError):
                store.save('2026-09-06',{'revision':0,'tasks':[]})
            task['status']='paused'
            store.save('2026-09-06',{'revision':1,'tasks':[task]})
            windows=json.loads((root/'blocker/schedule.json').read_text())['windows']
            self.assertEqual([w['id'] for w in windows],['2026-09-07-other'])
            self.assertEqual(store.read('2026-09-06')['events'][-1]['status'],'paused')

    def test_move_task_is_all_or_nothing_and_preserves_provenance(self):
        # Removing the source task, creating the target task, or losing native
        # provenance independently would make this cross-date move unsafe.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            store=Store(root)
            source=store.save('2026-09-09',{'revision':0,'tasks':[self.task()]})
            target=store.read('2026-09-10')
            moved=store.move_task(
                '2026-09-09','2026-09-10','study-1',source['revision'],target['revision'],
                dict(self.task(),start='09:00',end='10:00')
            )
            self.assertEqual(store.read('2026-09-09')['tasks'],[])
            self.assertEqual(store.read('2026-09-10')['tasks'][0]['id'],'study-1')
            self.assertEqual(moved['source']['revision'],source['revision']+1)
            self.assertEqual(moved['target']['revision'],target['revision']+1)
            self.assertEqual(moved['target']['events'][-1]['source'],'native_user')
            with self.assertRaises(RuntimeError):
                store.move_task('2026-09-10','2026-09-11','study-1',0,0,self.task())

    def test_http_reads_wait_for_a_cross_date_move_transaction(self):
        # Removing Store.read's transaction lock would let the two GETs read
        # the source-after / target-before state while the move is half-applied.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            store=Store(root)
            source_day,target_day='2026-09-09','2026-09-10'
            source=store.save(source_day,{'revision':0,'tasks':[self.task()]})

            observations=queue.Queue()
            observe_reads=threading.Event()
            source_replaced=threading.Event()
            continue_move=threading.Event()
            move_thread_id=[None]

            class ObservedLock:
                def __init__(self,inner): self.inner=inner
                def __enter__(self):
                    if observe_reads.is_set() and threading.get_ident()!=move_thread_id[0]:
                        observations.put(('lock',None))
                    self.inner.acquire()
                    return self
                def __exit__(self,*_): self.inner.release()

            store.lock=ObservedLock(store.lock)
            original_atomic=server.atomic_json
            original_exists=Path.exists
            day_paths={store.path(source_day),store.path(target_day)}

            def controlled_atomic(path,value):
                original_atomic(path,value)
                if path==store.path(source_day) and threading.get_ident()==move_thread_id[0]:
                    source_replaced.set()
                    if not continue_move.wait(5):
                        raise AssertionError('test did not release the controlled move window')

            def observed_exists(path):
                value=original_exists(path)
                if observe_reads.is_set() and threading.get_ident()!=move_thread_id[0] and path in day_paths:
                    observations.put(('file',path.name))
                return value

            srv=ThreadingHTTPServer(('127.0.0.1',0),make_handler(store,root/'index.html',False))
            server_thread=threading.Thread(target=srv.serve_forever,daemon=True)
            server_thread.start()
            move_errors=[]
            responses={}

            def move():
                move_thread_id[0]=threading.get_ident()
                try:
                    store.move_task(source_day,target_day,'study-1',source['revision'],0,
                                    dict(self.task(),start='09:00',end='10:00'))
                except Exception as error:
                    move_errors.append(error)

            def get_day(day):
                conn=http.client.HTTPConnection('127.0.0.1',srv.server_port,timeout=5)
                try:
                    conn.request('GET',f'/api/day?date={day}')
                    response=conn.getresponse()
                    responses[day]=(response.status,json.loads(response.read()))
                finally:
                    conn.close()

            mover=threading.Thread(target=move,name='move-worker')
            readers=[]
            observations_seen=[]
            try:
                with patch('server.atomic_json',side_effect=controlled_atomic), \
                     patch.object(Path,'exists',new=observed_exists):
                    mover.start()
                    self.assertTrue(source_replaced.wait(5),'move did not reach the controlled replace window')
                    observe_reads.set()
                    readers=[threading.Thread(target=get_day,args=(day,),name=f'get-{day}')
                             for day in (source_day,target_day)]
                    for reader in readers: reader.start()
                    observations_seen=[observations.get(timeout=5) for _ in readers]
                    continue_move.set()
                    mover.join(5)
                    for reader in readers: reader.join(5)
            finally:
                continue_move.set()
                mover.join(5)
                for reader in readers: reader.join(5)
                srv.shutdown(); srv.server_close(); server_thread.join(5)

            self.assertFalse(mover.is_alive())
            self.assertFalse(any(reader.is_alive() for reader in readers))
            self.assertEqual(move_errors,[])
            self.assertEqual([kind for kind,_ in observations_seen],['lock','lock'])
            self.assertEqual(responses[source_day][0],200)
            self.assertEqual(responses[target_day][0],200)
            self.assertEqual(responses[source_day][1]['tasks'],[])
            self.assertEqual(responses[target_day][1]['tasks'][0]['id'],'study-1')

    def test_store_recovers_pending_move_before_reads_are_served(self):
        # A crash after either write must restore both days from the journal,
        # never expose an ambiguous half-move to a new Store instance.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            source_before={'date':'2026-09-09','revision':3,'tasks':[self.task()], 'events':[]}
            target_before={'date':'2026-09-10','revision':4,'tasks':[], 'events':[]}
            (root/'days/2026-09-09.json').write_text(json.dumps({'date':'2026-09-09','revision':4,'tasks':[], 'events':[]}))
            (root/'days/2026-09-10.json').write_text(json.dumps({'date':'2026-09-10','revision':5,'tasks':[self.task()], 'events':[]}))
            journal=root/'transactions'/'move-task.json'; journal.parent.mkdir()
            journal.write_text(json.dumps({
                'sourceDay':'2026-09-09','targetDay':'2026-09-10',
                'sourceBefore':source_before,'targetBefore':target_before
            }))
            recovered=Store(root)
            self.assertEqual(recovered.read('2026-09-09'),source_before)
            self.assertEqual(recovered.read('2026-09-10'),target_before)
            self.assertFalse(journal.exists())

    def test_move_endpoint_requires_current_revisions_and_returns_both_days(self):
        # Routing stale input to a normal save (or accepting it) would allow a
        # native editor to overwrite a concurrent change on either day.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            store=Store(root)
            source=store.save('2026-09-09',{'revision':0,'tasks':[self.task()]})
            srv=ThreadingHTTPServer(('127.0.0.1',0),make_handler(store,root/'index.html',False))
            thread=threading.Thread(target=srv.serve_forever,daemon=True); thread.start()
            try:
                conn=http.client.HTTPConnection('127.0.0.1',srv.server_port)
                conn.request('GET','/api/bootstrap')
                token=json.loads(conn.getresponse().read())['token']; conn.close()
                headers={'Origin':f'http://127.0.0.1:{srv.server_port}','X-Daaaay-Token':token,'Content-Type':'application/json'}
                body={'sourceDate':'2026-09-09','targetDate':'2026-09-10','taskId':'study-1',
                    'sourceRevision':source['revision'],'targetRevision':0,
                    'task':dict(self.task(),start='09:00',end='10:00'),'source':'native_user'}
                conn=http.client.HTTPConnection('127.0.0.1',srv.server_port)
                conn.request('POST','/api/task/move',json.dumps(body),headers)
                response=conn.getresponse(); moved=json.loads(response.read()); self.assertEqual(response.status,200); conn.close()
                self.assertEqual(moved['source']['revision'],2)
                self.assertEqual(moved['target']['revision'],1)
                conn=http.client.HTTPConnection('127.0.0.1',srv.server_port)
                conn.request('POST','/api/task/move',json.dumps(body),headers)
                response=conn.getresponse(); self.assertEqual(response.status,409); conn.close()
            finally:
                srv.shutdown(); srv.server_close(); thread.join()

    def test_move_rejects_a_stale_target_revision(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            store=Store(root)
            source=store.save('2026-09-09',{'revision':0,'tasks':[self.task()]})
            target=store.save('2026-09-10',{'revision':0,'tasks':[self.task(id='already-there')]})
            with self.assertRaises(RuntimeError):
                store.move_task('2026-09-09','2026-09-10','study-1',source['revision'],target['revision']-1,self.task())

    def test_move_rejects_a_running_source_task(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            store=Store(root)
            source=store.save('2026-09-09',{'revision':0,'tasks':[self.task(status='running')]})
            with self.assertRaises(ValueError):
                store.move_task('2026-09-09','2026-09-10','study-1',source['revision'],0,self.task())

    def test_move_preserves_server_owned_timer_fields(self):
        # A client could otherwise convert a paused item into a running timer
        # or overwrite elapsed time while merely changing its date.
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            (root/'blocker/schedule.json').write_text('{"version":1,"windows":[]}')
            source_task=self.task(status='paused',startedAt=None,elapsedSeconds=42)
            (root/'days/2026-09-09.json').write_text(json.dumps({'date':'2026-09-09','revision':3,'tasks':[source_task],'events':[]}))
            store=Store(root)
            replacement=self.task(title='已改标题',start='09:00',end='10:00',status='running',
                                  startedAt='2026-09-10T09:00:00+08:00',elapsedSeconds=99999)
            result=store.move_task('2026-09-09','2026-09-10','study-1',3,0,replacement)
            moved=result['target']['tasks'][0]
            self.assertEqual(moved['title'],'已改标题')
            self.assertEqual(moved['status'],'paused')
            self.assertIsNone(moved['startedAt'])
            self.assertEqual(moved['elapsedSeconds'],42)

    def test_move_rolls_back_immediately_when_target_write_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            source_day,target_day='2026-09-09','2026-09-10'
            source={'date':source_day,'revision':3,'tasks':[self.task()],'events':[]}
            target={'date':target_day,'revision':2,'tasks':[self.task(id='target-task',block=False)],'events':[]}
            schedule={'version':1,'windows':[{'id':'2026-09-09-study-1','start':'2026-09-09T14:00:00+08:00','end':'2026-09-09T15:30:00+08:00'}]}
            (root/'days'/f'{source_day}.json').write_text(json.dumps(source))
            (root/'days'/f'{target_day}.json').write_text(json.dumps(target))
            (root/'blocker/schedule.json').write_text(json.dumps(schedule))
            store=Store(root); original_atomic=server.atomic_json; failed=[False]
            def fail_target(path,value):
                if path==store.path(target_day) and not failed[0]:
                    failed[0]=True
                    raise OSError('simulated target write failure')
                return original_atomic(path,value)
            with patch('server.atomic_json',side_effect=fail_target), self.assertRaises(OSError):
                store.move_task(source_day,target_day,'study-1',3,2,dict(self.task(),start='09:00',end='10:00'))
            self.assertEqual(store.read(source_day),source)
            self.assertEqual(store.read(target_day),target)
            self.assertEqual(json.loads((root/'blocker/schedule.json').read_text()),schedule)
            self.assertFalse(store.transaction_path().exists())

    def test_move_rolls_back_immediately_when_blocker_sync_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); (root/'days').mkdir(); (root/'blocker').mkdir()
            source_day,target_day='2026-09-09','2026-09-10'
            source={'date':source_day,'revision':3,'tasks':[self.task()],'events':[]}
            target={'date':target_day,'revision':2,'tasks':[self.task(id='target-task',block=False)],'events':[]}
            schedule={'version':1,'windows':[{'id':'2026-09-09-study-1','start':'2026-09-09T14:00:00+08:00','end':'2026-09-09T15:30:00+08:00'}]}
            (root/'days'/f'{source_day}.json').write_text(json.dumps(source))
            (root/'days'/f'{target_day}.json').write_text(json.dumps(target))
            (root/'blocker/schedule.json').write_text(json.dumps(schedule))
            store=Store(root); original_sync=Store._sync_blocker_days; failed=[False]
            def fail_once(instance,days):
                if not failed[0]:
                    failed[0]=True
                    raise OSError('simulated blocker synchronization failure')
                return original_sync(instance,days)
            with patch.object(Store,'_sync_blocker_days',new=fail_once), self.assertRaises(OSError):
                store.move_task(source_day,target_day,'study-1',3,2,dict(self.task(),start='09:00',end='10:00'))
            self.assertEqual(store.read(source_day),source)
            self.assertEqual(store.read(target_day),target)
            self.assertEqual(json.loads((root/'blocker/schedule.json').read_text()),schedule)
            self.assertFalse(store.transaction_path().exists())

    def test_http_requires_origin_and_token_for_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'days').mkdir()
            html=root/'index.html';html.write_text('planner')
            srv=ThreadingHTTPServer(('127.0.0.1',0),make_handler(Store(root),html,False))
            thread=threading.Thread(target=srv.serve_forever,daemon=True);thread.start()
            def request(path,body=None,headers=None):
                conn=http.client.HTTPConnection('127.0.0.1',srv.server_port)
                conn.request('POST' if body else 'GET',path,body,headers or {})
                response=conn.getresponse();data=response.read();code=response.status;conn.close()
                return code,data
            try:
                body=json.dumps({'date':'2026-09-06','revision':0,'tasks':[self.task()]})
                self.assertEqual(request('/api/day',body)[0],403)
                token=json.loads(request('/api/bootstrap')[1])['token']
                headers={'Origin':f'http://127.0.0.1:{srv.server_port}','X-Daaaay-Token':token,'Content-Type':'application/json'}
                self.assertEqual(request('/api/day',body,headers)[0],200)
                headers['Origin']='https://evil.example'
                self.assertEqual(request('/api/day',body,headers)[0],403)
                self.assertEqual(request('/../../AGENTS.md')[0],404)
            finally:
                srv.shutdown();srv.server_close();thread.join()

    def test_timer_accumulates_across_pause_resume_and_legacy_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            store=Store(tmp)
            def save_at(at, tasks, revision):
                with patch('server.datetime', wraps=datetime) as clock:
                    clock.now.return_value=datetime.fromisoformat(at)
                    return store.save('2026-09-07', {'revision':revision,'tasks':tasks,'source':'native_user'})
            t=self.task(status='running')
            a=save_at('2026-09-07T10:00:00+08:00',[t],0)
            self.assertEqual(a['tasks'][0].get('startedAt'),'2026-09-07T10:00:00+08:00')
            self.assertEqual(a['tasks'][0].get('elapsedSeconds'),0)
            t=copy.deepcopy(a['tasks'][0]);t.update(status='paused',startedAt=None)
            b=save_at('2026-09-07T10:00:10+08:00',[t],1)
            self.assertEqual(b['tasks'][0]['elapsedSeconds'],10)
            # An older web tab omits the new field, and cannot erase accrued time.
            t=copy.deepcopy(b['tasks'][0]);t.pop('elapsedSeconds');t['note']='改备注'
            c=save_at('2026-09-07T10:02:00+08:00',[t],2)
            self.assertEqual(c['tasks'][0]['elapsedSeconds'],10)
            t=copy.deepcopy(c['tasks'][0]);t['status']='running'
            d=save_at('2026-09-07T10:03:00+08:00',[t],3)
            # A same-status save must not restart a running interval.
            t=copy.deepcopy(d['tasks'][0]);t['startedAt']='2026-09-07T10:03:05+08:00'
            e=save_at('2026-09-07T10:03:05+08:00',[t],4)
            self.assertEqual(e['tasks'][0]['startedAt'],'2026-09-07T10:03:00+08:00')
            t=copy.deepcopy(e['tasks'][0]);t.update(status='done',startedAt=None,elapsedSeconds=99999)
            f=save_at('2026-09-07T10:03:20+08:00',[t],5)
            self.assertEqual(f['tasks'][0]['elapsedSeconds'],30)
            self.assertIsNone(f['tasks'][0]['startedAt'])
            self.assertEqual(f['events'][-1]['source'],'native_user')
            self.assertEqual(Store(tmp).read('2026-09-07')['tasks'][0]['elapsedSeconds'],30)

    def test_invalid_accumulated_time_rejected(self):
        for value in (-1, float('nan'), float('inf'), '12', True):
            with self.subTest(value=value), self.assertRaises(ValueError):
                validate_day('2026-09-07',{'tasks':[self.task(status='planned',elapsedSeconds=value)]})

    def test_timer_migration_and_switch_preserve_fixed_block_window(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'days').mkdir();(root/'blocker').mkdir()
            fixed={'id':'class-focus-2026-09-07','start':'2026-09-07T08:10:00+08:00','end':'2026-09-07T11:50:00+08:00'}
            (root/'blocker/schedule.json').write_text(json.dumps({'version':1,'windows':[fixed]}))
            old=self.task(status='running',startedAt='2026-09-07T10:00:00+08:00')
            (root/'days/2026-09-07.json').write_text(json.dumps({'date':'2026-09-07','revision':1,'tasks':[old],'events':[]}))
            first=dict(old,status='paused',startedAt=None)
            second=dict(old,id='second',status='running',startedAt=None)
            with patch('server.datetime', wraps=datetime) as clock:
                clock.now.return_value=datetime.fromisoformat('2026-09-07T10:01:00+08:00')
                result=Store(root).save('2026-09-07',{'revision':1,'tasks':[first,second]})
            self.assertEqual(result['tasks'][0].get('elapsedSeconds'),60)
            self.assertEqual(result['tasks'][1].get('elapsedSeconds'),0)
            self.assertIn(fixed,json.loads((root/'blocker/schedule.json').read_text())['windows'])


if __name__=='__main__':
    unittest.main()
