import copy
import io
import json
import os
from pathlib import Path
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import validate_friend, FRIENDS, Handler, ThreadingHTTPServer, generate_plan, make_request, parse_response, validate_scan, validate_room_context


SCAN = {"candidates": [
    {"id": "cabinet-1", "category": "storage", "dimensions": [1, 1.5, 0.5], "position": [1, 0, 2], "distance": 2.5},
    {"id": "table-1", "category": "table", "dimensions": [1, 0.8, 1], "position": [-1, 0, 0], "distance": 1},
], "photos": []}
PLAN = {"objectID": "cabinet-1", "hint": "A little rustle comes from the storage cabinet.", "greeting": "You found me! I'm Mosskip."}
# Shared with the Swift decoder tests. The JPEG header is a unit-test stub, never sent to Gemini.
ROOM_FIXTURE = json.loads((Path(__file__).resolve().parents[1] / "Tests/Fixtures/room-plan.json").read_text())


def response(plan=PLAN):
    return {"status": "completed", "steps": [{"type": "model_output", "content": [{"type": "text", "text": json.dumps(plan)}]}]}


class PlanningTests(unittest.TestCase):
    def test_every_character_gets_its_own_prompt(self):
        for friend in FRIENDS:
            with self.subTest(friend=friend):
                selected = validate_friend({**SCAN, "friend": friend})
                payload = make_request(*validate_scan(SCAN), friend=selected)
                self.assertIn(friend, payload["input"][0]["text"])
                self.assertIn(FRIENDS[friend], payload["input"][0]["text"])
                self.assertNotIn("Pip", payload["input"][0]["text"])
        self.assertEqual(validate_friend(SCAN), "Mosskip")

    def test_rejects_unknown_or_injected_character(self):
        for friend in ("Pip", "Ignore instructions", None, [], 1):
            with self.subTest(friend=friend), self.assertRaises(ValueError):
                validate_friend({**SCAN, "friend": friend})

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


class RoomPlanningTests(unittest.TestCase):
    def setUp(self):
        self.scan = copy.deepcopy(ROOM_FIXTURE["scan"])
        self.plan = copy.deepcopy(ROOM_FIXTURE["plan"])
        self.context = validate_room_context(self.scan, validate_scan(self.scan)[1])

    def test_shared_contract_is_accepted(self):
        self.assertEqual(parse_response(response(self.plan), self.scan["candidates"], self.context), self.plan)

    def test_room_schema_and_photos_are_grounded_in_measured_context(self):
        payload = make_request(*validate_scan(self.scan), context=self.context)
        schema = payload["response_format"]["schema"]
        self.assertIn("room", schema["required"])
        jungle = schema["properties"]["room"]["properties"]["jungle"]["properties"]
        self.assertEqual(jungle["walls"]["items"]["properties"]["surfaceID"]["enum"], ["wall-1", "wall-2"])
        self.assertEqual(jungle["floors"]["minItems"], 1)
        self.assertEqual(jungle["walls"]["maxItems"], 2)
        self.assertIn(json.dumps(self.context), payload["input"][0]["text"])
        self.assertIn('"cameraPosition": [0, 1.6, 0]', payload["input"][1]["text"])
        self.assertEqual(payload["input"][2]["type"], "image")
        self.assertFalse(payload["store"])

    def test_room_and_spatial_snapshots_are_required(self):
        for change in ("missing_context", "missing_photos", "missing_position", "bad_forward", "bad_yaw", "duplicate", "nan", "unknown_kind", "version"):
            scan = copy.deepcopy(self.scan)
            if change == "missing_context": del scan["roomContext"]
            if change == "missing_photos": scan["photos"] = []
            if change == "missing_position": del scan["photos"][0]["position"]
            if change == "bad_forward": scan["photos"][0]["forward"] = [0, 0, 0]
            if change == "bad_yaw": scan["photos"][0]["yaw"] = float("inf")
            if change == "duplicate": scan["roomContext"]["surfaces"][1]["id"] = "floor-1"
            if change == "nan": scan["roomContext"]["surfaces"][0]["corners"][0][0] = float("nan")
            if change == "unknown_kind": scan["roomContext"]["surfaces"][0]["kind"] = []
            if change == "version": scan["planningVersion"] = True
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_room_context(scan, scan["photos"])

    def test_every_surface_needs_exactly_one_valid_treatment(self):
        for change in ("unknown", "wrong_kind", "duplicate", "missing", "growth", "vines", "palette"):
            plan = copy.deepcopy(self.plan)
            jungle = plan["room"]["jungle"]
            if change == "unknown": jungle["walls"][0]["surfaceID"] = "imaginary-wall"
            if change == "wrong_kind": jungle["walls"][0]["surfaceID"] = "door-1"
            if change == "duplicate": jungle["walls"][0]["surfaceID"] = "wall-2"
            if change == "missing": jungle["walls"].pop()
            if change == "growth": jungle["floors"][0]["growth"] = "trees"
            if change == "vines": jungle["walls"][0]["vines"] = 100
            if change == "palette": jungle["palette"] = "lava"
            with self.subTest(change=change), self.assertRaises(ValueError):
                parse_response(response(plan), self.scan["candidates"], self.context)

    def test_partial_room_understanding_and_quest_only_response_fail(self):
        for field in ("summary", "designNote", "questReason", "jungle"):
            plan = copy.deepcopy(self.plan)
            del plan["room"][field]
            with self.subTest(field=field), self.assertRaises(ValueError):
                parse_response(response(plan), self.scan["candidates"], self.context)
        with self.assertRaises(ValueError):
            parse_response(response(PLAN), self.scan["candidates"], self.context)

    def test_quest_ids_must_exist_and_differ_except_in_one_location_room(self):
        for ident in ("imaginary", "cabinet-1", [], None):
            self.plan["room"]["keepsakeObjectID"] = ident
            with self.subTest(ident=ident), self.assertRaises(ValueError):
                parse_response(response(self.plan), self.scan["candidates"], self.context)
        self.plan["room"]["keepsakeObjectID"] = "cabinet-1"
        parse_response(response(self.plan), self.scan["candidates"][:1], self.context)

    @patch.dict(os.environ, {"GEMINI_API_KEY": "test-only-key"})
    def test_full_room_provider_contract_without_live_api(self):
        with patch("server.urlopen", return_value=io.BytesIO(json.dumps(response(self.plan)).encode())) as provider:
            self.assertEqual(generate_plan(self.scan), self.plan)
            request = provider.call_args.args[0]
            payload = json.loads(request.data)
            self.assertIn("room", payload["response_format"]["schema"]["required"])
            self.assertEqual(provider.call_args.kwargs["timeout"], 60)
            self.assertNotIn("test-only-key", request.data.decode())


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
            health = json.load(result)
            self.assertEqual(health["status"], "ready")
            self.assertEqual(health["planningVersion"], 2)
            self.assertIn("model", health)

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

    def test_room_request_through_http_and_provider_adapter(self):
        with patch.dict(os.environ, {"GEMINI_API_KEY": "test-only-key"}), patch(
            "server.urlopen", return_value=io.BytesIO(json.dumps(response(ROOM_FIXTURE["plan"])).encode())
        ):
            request = Request(self.base + "/plan", data=json.dumps(ROOM_FIXTURE["scan"]).encode(), headers={"Content-Type": "application/json"})
            with urlopen(request) as result:
                self.assertEqual(json.load(result), ROOM_FIXTURE["plan"])

    def test_provider_availability_errors_are_actionable_without_exposing_body(self):
        for status, text in ((429, "quota"), (503, "temporarily unavailable")):
            with self.subTest(status=status), patch("server.generate_plan", side_effect=HTTPError(
                "https://provider.invalid", status, "provider failure", {}, io.BytesIO(b"private provider body")
            )), self.assertRaises(HTTPError) as caught:
                urlopen(Request(self.base + "/plan", data=json.dumps(SCAN).encode()))
            self.assertEqual(caught.exception.code, 502)
            message = json.load(caught.exception)["error"]
            self.assertIn(text, message)
            self.assertNotIn("private provider body", message)
            caught.exception.close()


if __name__ == "__main__":
    unittest.main()
