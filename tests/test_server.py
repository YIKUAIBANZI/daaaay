import http.client
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

spec = importlib.util.spec_from_file_location('server', Path(__file__).resolve().parents[1] / 'blocker/server.py')
server_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_module)


class ScheduleServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / 'schedule.json'
        self.path.write_text(json.dumps({'version':1,'windows':[
            {'id':'x','start':'2026-09-06T12:00:00+08:00','end':'2026-09-06T13:00:00+08:00','private_title':'never serve this'}
        ]}))
        self.server = ThreadingHTTPServer(('127.0.0.1',0),server_module.make_handler(self.path))
        self.thread = threading.Thread(target=self.server.serve_forever,daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.tmp.cleanup()

    def request(self,path='/schedule',headers=None,method='GET'):
        connection = http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=2)
        connection.request(method,path,headers=headers or {})
        response = connection.getresponse()
        status, data = response.status,response.read()
        connection.close()
        return status,data

    def test_serves_only_window_times_and_reads_updates_without_restart(self):
        status,data = self.request(headers={'Origin':'chrome-extension://test'})
        self.assertEqual(status,200)
        self.assertNotIn(b'never serve this',data)
        self.assertEqual(json.loads(data)['windows'][0]['id'],'x')
        self.path.write_text('{"version":1,"windows":[]}')
        self.assertEqual(json.loads(self.request()[1])['windows'],[])

    def test_rejects_website_origins_dns_rebinding_other_paths_and_writes(self):
        self.assertEqual(self.request(headers={'Origin':'https://douyin.com'})[0],403)
        self.assertEqual(self.request(headers={'Host':'evil.example'})[0],403)
        self.assertEqual(self.request('/../AGENTS.md')[0],404)
        self.assertEqual(self.request(method='POST')[0],501)

    def test_missing_or_corrupt_schedule_reports_unavailable(self):
        self.path.write_text('partial write')
        self.assertEqual(self.request()[0],503)
        self.path.unlink()
        self.assertEqual(self.request()[0],503)


if __name__ == '__main__':
    unittest.main()
