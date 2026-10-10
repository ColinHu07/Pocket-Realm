# Pocket Realm

A native iPhone AR adventure prototype. Start with a guided 360° room scan; Gemini chooses a real furniture location for Pip, a tiny forest spirit. Follow the generated clue and walk nearby to reveal Pip automatically. No placement or reveal button.

## Run the Gemini server

The server requires Python 3.10+ and a Gemini API key. It uses the standard library; no dependency installation is needed. Keep the key in your terminal environment, not in the app, source code, or chat.

From this repository in zsh:

```sh
read -s 'GEMINI_API_KEY?Gemini API key: '
export GEMINI_API_KEY
python3 server/server.py
```

The default port is 8787. The model defaults to `gemini-flash-latest`; override it with `GEMINI_MODEL` if your account uses another compatible model. The server uses Gemini's Interactions API with a constrained JSON schema.

Find your Mac's local hostname in another terminal:

```sh
scutil --get LocalHostName
```

If this prints `Colins-MacBook`, the app's **Connection settings** address is `http://Colins-MacBook.local:8787`. Put the phone and Mac on the same Wi-Fi and allow local-network access on the phone. Allow incoming Python connections in the Mac firewall if prompted. Alternatively, use an HTTPS deployment of this server. Enter the base address, without `/plan`.

`GET /health` reports whether the server is running and whether a key is configured. It does not test the provider or reveal the key. The default server listens on the local network for hackathon testing, has no authentication, and should not be exposed to the public internet without authentication and rate limiting.

## Run the iPhone app

1. Open `PocketRealm.xcodeproj` in Xcode.
2. Select your development team under **Signing & Capabilities** if needed. Existing team settings are preserved.
3. Connect your LiDAR-equipped iPhone Pro, select it as the destination, and Run. The app targets iOS 17+.
4. Set the server address in **Connection settings**, then tap **Scan my room** and allow camera access.
5. Slowly turn all the way around. Include furniture, walls, and floor; move enough to see the objects clearly. The progress bar measures viewing directions, not geometric completeness.
6. The scan finishes automatically once all 24 direction sectors have been observed, at least one usable furniture location is detected, and at least 12 seconds have elapsed. If the sweep is complete but no locations appear, keep looking at a cabinet, table, sofa, chair, bed, or refrigerator.
7. The app finalizes the room model and sends its candidate locations plus up to six downsized snapshots to the server. Gemini picks one existing object ID and writes the clue and greeting.
8. Follow the clue. First be at least 1.8 m from the chosen spawn point, then approach within 1.4 m for 0.8 seconds. If the spot was next to you when scanning finished, step back first. Tracking must be normal and the anchor resolved.
9. Pip appears automatically and remains at that world position. Tap **Say hello to Pip** for the generated dialogue and spoken greeting.
10. Use **Scan again** to reset the room and encounter.

Distances use the horizontal floor plane. The creature floats outside an observed furniture face; it does not follow moving furniture or a moving cabinet door. Opening detection and puzzle generation are not part of this milestone. Pip remains visible after being discovered, even when you move away.

## What is automatic

- **RoomPlan:** detects furniture categories and bounding boxes during the sweep.
- **ARKit:** measures the room and maintains a single world coordinate frame throughout scanning, generation, and play.
- **Gemini:** chooses one ID from the supplied furniture list and generates a clue and greeting. It cannot supply arbitrary coordinates or invent anchor IDs.
- **The app:** computes a spawn point outside a scanned furniture box, creates an initially empty anchor, and reveals the creature when proximity conditions are met.

The scan uses `RoomCaptureSession(arSession:)` with the same session as the RealityKit `ARView`. Scan completion calls `stop(pauseARSession: false)` and does not reset tracking. Results are finalized with `RoomBuilder`; the app uses native transforms directly, without exporting/reimporting USDZ.

Furniture with low classification confidence is excluded, as are stairs, appliances such as stoves/ovens, and other unsupported categories. Placement uses approximate bounding boxes and a side observed from a camera position during the scan. It is not a free-space/navigation solver; check placement in the demo room.

Broad snapshots help with room context but are not object-labeled crops. Gemini is instructed to use detected furniture categories and avoid guessing which image detail belongs to which ID.

## Reliability and privacy

- The app and server validate returned IDs and dialogue lengths.
- Old generation results cannot populate a restarted scan; requests are cancelled and tied to a scan generation ID.
- Leaving the reveal radius or losing tracking clears the proximity dwell timer.
- Backgrounding during scanning requires a fresh scan on return. During gameplay, the app attempts to resume tracking. **Scan again** is the recovery path if relocalization fails.
- Network/provider failures offer a retry using the same captured candidates. There is no silent local fallback pretending to be Gemini.
- Camera frames are sampled into at most six JPEGs with a maximum dimension of 640 pixels. They are held in memory and discarded after successful planning or rescan. Room data and images go to your configured server and Gemini. The proxy does not log or save those payloads and requests `store: false` from the provider; this is not a claim about provider-wide retention policies.
- The API key is only read by the server from `GEMINI_API_KEY`.

## Checks

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s server -v

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PocketRealm.xcodeproj -scheme PocketRealm \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The Swift tests cover scan coverage, progression, proximity dwell, tracking loss, and rejection of invented locations. Server tests cover scan validation, provider request/response contracts, missing credentials, and HTTP requests using mocked provider responses.

Actual room detection, scan-to-game coordinate alignment, placement outside furniture, interrupted-session recovery, and reveal behavior need the physical iPhone. The simulator cannot validate LiDAR/RoomPlan. A live Gemini smoke test requires your configured key and model access.

Validation for this update: Xcode 26.6 unsigned iPhone and arm64 simulator builds passed, the signed iPhone build passed, five Swift tests and nine server tests passed, and the updated app was installed on the connected iPhone 17 Pro Max. Live Gemini and physical room-scan behavior have not yet been verified.
