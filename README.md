# Pocket Realm

A native iPhone AR adventure with three original Blender characters. Choose a friend, scan your room, follow Gemini's clue, and approach their hiding spot to reveal them. Say hello, recover a glowing keepsake, and return it to earn a saved friendship badge.

![Mosskip, Glimlo, and Pebblin](Art/Creatures/friends-lineup.png)

| Friend | Personality | Quest | Badge |
| --- | --- | --- | --- |
| **Mosskip** | A mint-green sprout courier with a leaky seed satchel | Find a lost dew seed | Sprout Scout |
| **Glimlo** | A bashful peach moth with petal wings and a tiny lantern | Recover a lantern spark | Little Light |
| **Pebblin** | A sleepy lilac pebble snail with a crystal shell | Bring back a runaway dream pearl | Dream Keeper |

All geometry and materials were authored for this project in Blender. No external character models or textures are used. The app bundles the actual USDZ exports; portraits are Blender renders of those same models. One chosen friend appears per scan. You can pet them, hear their greeting, complete their quest, and chat afterward. The three quests share a find-and-return mechanic, with distinct keepsakes, dialogue, and rewards.

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
4. Set the server address in **Connection settings**, choose a friend, then tap **Find [friend name]** and allow camera access.
5. Slowly turn all the way around. Include furniture, walls, and floor; move enough to see the objects clearly. The progress bar measures viewing directions, not geometric completeness.
6. The scan finishes automatically once all 24 direction sectors have been observed, at least one usable furniture location is detected, and at least 12 seconds have elapsed. If the sweep is complete but no locations appear, keep looking at a cabinet, table, sofa, chair, bed, or refrigerator.
7. The app finalizes the room model and sends its candidate locations plus up to six downsized snapshots to the server. Gemini picks one existing object ID and writes the clue and greeting.
8. Follow the clue. First be at least 1.8 m from the chosen spawn point, then approach within 1.4 m for 0.8 seconds. If the spot was next to you when scanning finished, step back first. Tracking must be normal and the anchor resolved.
9. Your friend appears automatically and remains at that world position. Tap **Say hello** to hear the generated greeting and begin their quest. **Pet** triggers a happy wiggle.
10. Find the glowing keepsake by the named furniture. Approach within 1.3 m and tap **Collect**. This uses another observed furniture face when available; with only one usable location, the item floats just above your friend.
11. Return within 2 m of your friend and tap **Give it**. Their friendship badge is saved on the device; repeat turn-ins cannot award it twice. You can then **Chat**, **Pet**, or **Meet another friend**.
12. Use **Scan again** to reset the room and encounter. **Choose another friend** in the menu returns to the roster. Saved badges survive both actions.

Distances use the horizontal floor plane. The creature floats outside an observed furniture face; it does not follow moving furniture or a moving cabinet door. Opening detection and generated puzzles are not implemented. Keepsake locations reuse observed furniture faces and never require opening furniture. Friends remain visible after discovery, even when you move away. Collecting and turning in require valid tracking and resolved anchors.

## What is automatic

- **RoomPlan:** detects furniture categories and bounding boxes during the sweep.
- **ARKit:** measures the room and maintains a single world coordinate frame throughout scanning, generation, and play.
- **Gemini:** receives a validated character name, chooses one ID from the supplied furniture list, and generates a clue and a greeting in that character's personality. It cannot supply arbitrary coordinates or invent anchor IDs.
- **The app:** computes a spawn point outside a scanned furniture box, creates an initially empty anchor, and reveals the creature when proximity conditions are met.

The scan uses `RoomCaptureSession(arSession:)` with the same session as the RealityKit `ARView`. Scan completion calls `stop(pauseARSession: false)` and does not reset tracking. Results are finalized with `RoomBuilder`; the app uses native transforms directly, without exporting/reimporting USDZ.

Furniture with low classification confidence is excluded, as are stairs, appliances such as stoves/ovens, and other unsupported categories. Placement uses approximate bounding boxes and a side observed from a camera position during the scan. It is not a free-space/navigation solver; check placement in the demo room.

Broad snapshots help with room context but are not object-labeled crops. Gemini is instructed to use detected furniture categories and avoid guessing which image detail belongs to which ID.

## Room themes

Tap **Room theme** on the welcome screen, or **Theme** while scanning or playing, to choose **Original** or **Jungle**. Jungle adds a moss carpet, grass tufts, ferns, pink/orange/lilac flowers, and hanging leafy vines. Your selection is saved on the device. Choosing a theme before scanning applies it when the room model finishes; switching afterward reuses that scan and leaves the friend, quest, and badges in place.

The existing 360° camera sweep supplies RoomPlan's measured floor polygons, walls, furniture, doors, and windows. The app procedurally builds the Jungle preset in that same AR coordinate system, on the phone, without an additional server request. It does not generate or edit a 360° video. Floor meshes follow concave room outlines; plant positions are repeatable for each scanned surface. Plants avoid detected furniture and doorways, and vines avoid detected apertures. ARKit mesh occlusion lets real surfaces hide the virtual foliage. This remains approximate scan-based decoration, not a navigation map.

Geometry is batched into one model with nine materials, with budgets of 900 grass clusters, 36 flowers, 28 ferns, and 60 vines. A seamless moss texture is generated locally and tiled at a consistent world scale. Low-confidence surfaces are skipped, as are curved walls. If the scan has no usable floor, the theme picker asks you to rescan with the floor in view; it does not invent a floor height. Returning to Original removes the theme, and rescanning or choosing another friend clears the old room decoration. Only the selected preset is saved between launches; the room scan itself is not persisted.

On a LiDAR device, check an irregular room, furniture occlusion, doors/windows, and floor alignment; toggle Jungle → Original → Jungle during a quest, then rescan to check that old plants disappear. Also check background/resume tracking. The simulator can verify the picker, but cannot verify real-room placement or occlusion.

Theme validation: all 12 Swift tests passed, including concave-floor triangulation, edge clearance, stable scatter, and geometry budgets. Unsigned iPhone and simulator builds passed. Interactive picker verification was blocked by a stalled simulator launch; real-room placement and rendering still need a physical-device check.

## Reliability and privacy

- The app and server validate returned IDs and dialogue lengths.
- Old generation results cannot populate a restarted scan; requests are cancelled and tied to a scan generation ID.
- Leaving the reveal radius or losing tracking clears the proximity dwell timer.
- Backgrounding during scanning requires a fresh scan on return. During gameplay, the app attempts to resume tracking. **Scan again** is the recovery path if relocalization fails.
- Network/provider failures offer a retry using the same captured candidates. There is no silent local fallback pretending to be Gemini.
- Camera frames are sampled into at most six JPEGs with a maximum dimension of 640 pixels. They are held in memory and discarded after successful planning or rescan. Room data and images go to your configured server and Gemini. The proxy does not log or save those payloads and requests `store: false` from the provider; this is not a claim about provider-wide retention policies.
- The API key is only read by the server from `GEMINI_API_KEY`.

## Blender sources and exports

- `Art/Creatures/PocketRealm-Friends.blend`: editable scene with all three named characters, materials, camera, and studio lighting. Each character has a separate parent; the lineup positions are for presentation only.
- `Art/Creatures/*.glb`: individual portable models at the origin.
- `PocketRealm/Resources/Creatures/*.usdz`: app assets, in meters with Y up and faces pointing toward +Z. They are roughly 40–47 cm tall. The Xcode folder resource preserves the `Creatures` path.
- `Art/Creatures/*.png`: individual portraits and the lineup. The same portraits are copied into the app's asset catalog.
- `scripts/build_creatures.py`: reproducible Blender 4.5 authoring, export, and render script. Requires Blender, with no add-ons or Python dependencies. Run from this repository:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/build_creatures.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/inspect_creatures.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/validate_creatures.swift "$PWD/PocketRealm/Resources/Creatures"
```

The USDZs contain 28/42/27 mesh entities and about 13k/27k/24k triangles respectively. Materials use USD Preview Surface without textures. Idle floating, entrance scaling, and pet/reward wiggles are driven by RealityKit; the assets are not skeletal animation rigs. Quest keepsakes are small RealityKit primitives.

Restart the Python server after updating it so greetings use the new character identities. Requests without a character default to Mosskip; unknown character names are rejected.

## Checks

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s server -v

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PocketRealm.xcodeproj -scheme PocketRealm \
  -destination 'generic/platform=iOS' -configuration Debug \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The Swift tests cover scan coverage, progression, proximity dwell, tracking loss, rejection of invented locations, quest sequencing, and the one-location fallback. Server tests cover scan validation, per-character prompts, invalid character rejection, provider contracts, missing credentials, and mocked HTTP requests. The asset scripts verify geometry, dimensions, Y-up orientation, and actual RealityKit loading with materials.

Actual room detection, scan-to-game coordinate alignment, placement outside furniture, interrupted-session recovery, and reveal behavior need the physical iPhone. The simulator cannot validate LiDAR/RoomPlan. A live Gemini smoke test requires your configured key and model access.

Character update validation: seven Swift tests and eleven server tests passed. The unsigned iPhone and simulator builds passed, all three USDZs loaded in RealityKit with materials, and the Blender portraits and lineup were visually inspected. Live Gemini and physical room-scan/quest behavior still need verification on the LiDAR-equipped iPhone; this character update has not been installed on the phone.
