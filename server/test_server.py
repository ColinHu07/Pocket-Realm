import copy
import io
import json
import os
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import Handler, ThreadingHTTPServer, generate_plan, make_request, parse_response, validate_scan


SCAN = {"candidates": [
    {"id": "cabinet-1", "category": "storage", "dimensions": [1, 1.5, 0.5], "position": [1, 0, 2], "distance": 2.5},
    {"id": "table-1", "category": "table", "dimensions": [1, 0.8, 1], "position": [-1, 0, 0], "distance": 1},
], "photos": []}
PLAN = {"objectID": "cabinet-1", "hint": "A little rustle comes from the storage cabinet.", "greeting": "You found me! I'm Pip."}


def response(plan=PLAN):
    return {"status": "completed", "steps": [{"type": "model_output", "content": [{"type": "text", "text": json.dumps(plan)}]}]}


class PlanningTests(unittest.TestCase):
    def test_valid_plan_selects_existing_furniture(self):
        self.assertEqual(parse_response(response(), SCAN["candidates"]), PLAN)

    def test_unknown_location_and_incomplete_generation_fail(self):
        with self.assertRaises(ValueError):
            parse_response(response({**PLAN, "objectID": "imaginary-door"}), SCAN["candidates"])
        with self.assertRaises(ValueError):
            parse_response({"status": "incomplete"}, SCAN["candidates"])

    def test_invalid_geometry_duplicate_ids_and_images_fail(self):
        for mutation in ("nan", "duplicate", "image", "empty"):
            scan = copy.deepcopy(SCAN)
            if mutation == "nan": scan["candidates"][0]["position"][0] = float("nan")
            if mutation == "duplicate": scan["candidates"][1]["id"] = "cabinet-1"
            if mutation == "image": scan["photos"] = [{"jpeg": "not a jpeg"}]
            if mutation == "empty": scan["candidates"] = []
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                validate_scan(scan)

    def test_output_schema_restricts_ids_and_disables_storage(self):
        payload = make_request(*validate_scan(SCAN))
        self.assertEqual(payload["response_format"]["schema"]["properties"]["objectID"]["enum"], ["cabinet-1", "table-1"])
        self.assertFalse(payload["store"])

    @patch.dict(os.environ, {"GEMINI_API_KEY": "test-only-key"})
    def test_provider_contract_without_live_api(self):
        with patch("server.urlopen", return_value=io.BytesIO(json.dumps(response()).encode())) as provider:
            self.assertEqual(generate_plan(SCAN), PLAN)
            request = provider.call_args.args[0]
            self.assertEqual(request.full_url, "https://generativelanguage.googleapis.com/v1beta/interactions")
            self.assertNotIn("test-only-key", request.data.decode())
            self.assertEqual(json.loads(request.data)["input"][0]["type"], "text")

    @patch.dict(os.environ, {}, clear=True)
    def test_missing_key_is_explicit(self):
        with self.assertRaisesRegex(RuntimeError, "GEMINI_API_KEY"):
            generate_plan(SCAN)


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.worker = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.worker.start()
        cls.base = f"http://127.0.0.1:{cls.httpd.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.worker.join()

    def test_health(self):
        with urlopen(self.base + "/health") as result:
            self.assertEqual(json.load(result)["status"], "ready")

    def test_phone_request_round_trip(self):
        with patch("server.generate_plan", return_value=PLAN):
            request = Request(self.base + "/plan", data=json.dumps(SCAN).encode(), headers={"Content-Type": "application/json"})
            with urlopen(request) as result:
                self.assertEqual(json.load(result), PLAN)

    def test_malformed_request_returns_json_error(self):
        with self.assertRaises(HTTPError) as caught:
            urlopen(Request(self.base + "/plan", data=b"not json"))
        self.assertEqual(caught.exception.code, 400)
        self.assertIn("error", json.load(caught.exception))
        caught.exception.close()


if __name__ == "__main__":
    unittest.main()
