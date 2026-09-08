import sys
import unittest
import tempfile
import json
import threading
import http.client
import copy
from datetime import datetime
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'web'))
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
