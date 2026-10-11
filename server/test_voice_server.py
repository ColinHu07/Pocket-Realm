import http.client
import threading
import unittest
from unittest.mock import patch
from http.server import ThreadingHTTPServer
import voice_server

class VoiceServerTests(unittest.TestCase):
    def setUp(self):
        voice_server.Handler.state = {'agent_id': 'nibbi-test', 'pairing_code': 'test-pairing'}
        voice_server.Handler.last_session = float('-inf')
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), voice_server.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
    def request(self, code=None, path='/voice/session'):
        client = http.client.HTTPConnection(*self.server.server_address)
        client.request('POST', path, headers={'Authorization': 'Bearer '+code} if code else {})
        response = client.getresponse()
        status, data = response.status, response.read()
        client.close()
        return status, data
    @patch('voice_server.api')
    def test_unpaired_requests_never_reach_provider(self, api):
        self.assertEqual(self.request()[0], 401)
        self.assertEqual(self.request('wrong')[0], 401)
        api.assert_not_called()
    @patch('voice_server.api', return_value={'token': 'ephemeral-session'})
    def test_scoped_session_and_rate_limit(self, api):
        status, data = self.request('test-pairing')
        self.assertEqual(status, 200)
        self.assertIn(b'ephemeral-session', data)
        self.assertNotIn(b'test-pairing', data)
        api.assert_called_once_with('/v1/convai/conversation/token?agent_id=nibbi-test')
        self.assertEqual(self.request('test-pairing')[0], 429)
    @patch('voice_server.api', side_effect=RuntimeError('secret-in-error'))
    def test_provider_errors_do_not_leak_credentials(self, api):
        status, data = self.request('test-pairing')
        self.assertEqual(status, 503)
        self.assertNotIn(b'secret-in-error', data)
    @patch('voice_server.api')
    def test_no_arbitrary_endpoint(self, api):
        self.assertEqual(self.request('test-pairing', '/voice/other')[0], 404)
        api.assert_not_called()

if __name__ == '__main__':
    unittest.main()
