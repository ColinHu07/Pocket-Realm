# Pocket Realm

A native iPhone AR adventure with six original Blender characters. First scan your room: Gemini interprets its layout and snapshots, designs a Jungle treatment, and plans both quest locations. Review the room plan, then explore, meet your friend, and recover a glowing keepsake to earn a saved friendship badge.

![Mosskip, Glimlo, Pebblin, Bloopi, Nibbi, and Cindlet](Art/Creatures/friends-lineup.png)

| Friend | Personality | Quest | Badge |
| --- | --- | --- | --- |
| **Mosskip** | A mint-green sprout courier with a leaky seed satchel | Find a lost dew seed | Sprout Scout |
| **Glimlo** | A bashful peach moth with petal wings and a tiny lantern | Recover a lantern spark | Little Light |
| **Pebblin** | A sleepy lilac pebble snail with a crystal shell | Bring back a runaway dream pearl | Dream Keeper |
| **Bloopi** | A blue tide pup with rosy gills and a paddle tail | Find the perfect ripple stone | Puddle Pal |
| **Nibbi** | A strawberry bunny baker with floppy ears and a cookie pocket | Recover a sugar star for friendship cookies | Cookie Comrade |
| **Cindlet** | A honey-colored ember fox who keeps small wishes warm | Bring back a wish cinder | Cozy Guardian |

All geometry and materials were authored for this project in Blender. No external character models or textures are used. The app bundles the actual USDZ exports; portraits are Blender renders of those same models. One chosen friend appears per scan. You can tap them to pet, play together, hear their greeting, complete their quest, and chat afterward. The six-card roster opens a camera-free preview with Hello, Pet, Play, and Celebrate buttons; drag to turn the model. Previews do not award badges. The six quests share a find-and-return mechanic, with distinct keepsakes, dialogue, and rewards.

The in-game quest drawer can be tucked down with a swipe on its header, or opened again with a tap or upward swipe. Walking objectives start compact; puzzle controls scroll while their main action and Hint stay within reach. Choices and progress survive collapsing the drawer, and Bloopi’s demonstration pauses while it is hidden. Large-text layouts stack puzzle choices and actions vertically. Friend previews and practice quests scroll on smaller screens.

Nibbi, Cindlet, and Bloopi offer **Try the quest · no camera needed** from their friend preview. Practice uses the same puzzle rules and animation poses as the room encounter, without awarding friendship badges. After a successful scan, **Use saved room** restores the local room map and plan; **Room options** lets you scan again or forget the saved copy. No camera snapshots or credentials are stored in that saved-room file.

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

`GET /health` reports whether the server is running, whether a key is configured, the selected model, and `planningVersion: 3`. Restart the server after updating its code; the new app rejects an older quest-only response and asks you to restart. Health does not test the provider or reveal the key. The default server listens on the local network for hackathon testing, has no authentication, and should not be exposed to the public internet without authentication and rate limiting.

## Run the iPhone app

1. Open `PocketRealm.xcodeproj` in Xcode.
2. Select your development team under **Signing & Capabilities** if needed. Existing team settings are preserved.
3. Connect your LiDAR-equipped iPhone Pro, select it as the destination, and Run. The app targets iOS 17+.
4. Set the server address in **Connection settings**, choose a friend and theme, then tap **Scan my room** and allow camera access.
5. Slowly turn all the way around. Include visible walls and furniture; move enough to see the objects clearly. The progress bar measures viewing directions, not geometric completeness.
6. The scan finishes automatically once all 24 direction sectors have been observed, at least one usable furniture location is detected, and at least 12 seconds have elapsed. If the sweep is complete but no locations appear, keep looking at a cabinet, table, sofa, chair, bed, or refrigerator.
7. The app finalizes the room model and sends measured surface polygons, furniture, candidate locations, and up to six downsized snapshots labeled with camera positions and viewing directions. Gemini returns a room summary, Jungle treatments for each wall, and friend/keepsake locations. A failed request retains the scan for retry; exploration does not begin with a partial plan.
8. Review **Your room, understood**. Jungle is applied now if selected; **Preview the Jungle** also lets you switch from Original. Expand **Quest locations** to inspect the placement reasoning. Tap **Start exploring**, then follow the clue. First be at least 1.8 m from the chosen spawn point, then approach within 1.4 m for 0.8 seconds. If the spot was next to you when scanning finished, step back first. Tracking must be normal and the anchor resolved.
9. Your friend appears automatically and remains at that world position. Tap **Say hello** to hear the generated greeting and begin their quest. **Pet** triggers a happy wiggle.
10. Find the glowing keepsake by the furniture chosen by Gemini. Approach within 1.3 m and tap **Collect**. Gemini must choose a different observed furniture face when available; with only one usable location, the item floats just above your friend.
11. Return within 2 m of your friend and tap **Give it**. Their friendship badge is saved on the device; repeat turn-ins cannot award it twice. You can then **Chat**, **Pet**, or **Meet another friend**.
12. Use **Scan again** to reset the room and encounter. **Choose another friend** in the menu returns to the roster. Saved badges survive both actions.

Distances use the horizontal floor plane. The creature floats outside an observed furniture face; it does not follow moving furniture or a moving cabinet door. Opening detection and generated puzzles are not implemented. Keepsake locations reuse observed furniture faces and never require opening furniture. Friends remain visible after discovery, even when you move away. Collecting and turning in require valid tracking and resolved anchors.

## What is automatic

- **RoomPlan:** detects floor/wall polygons, doors, windows, openings, furniture categories, and bounding boxes during the sweep.
- **ARKit:** measures the room and maintains a single world coordinate frame throughout scanning, generation, and play.
- **Gemini:** first interprets the room from geometry and snapshots. One response contains the room summary, Jungle palette, per-wall foliage, both quest locations, placement reasoning, clue, and greeting. It chooses only supplied surface/furniture IDs and cannot supply arbitrary coordinates.
- **The app:** validates the complete plan, renders its treatments on measured surfaces, and displays the review. After **Start exploring**, it anchors the friend and keepsake outside observed furniture faces; the creature reveals when proximity conditions are met.

The scan uses `RoomCaptureSession(arSession:)` with the same session as the RealityKit `ARView`. Scan completion calls `stop(pauseARSession: false)` and does not reset tracking. Results are finalized with `RoomBuilder`; the app uses native transforms directly, without exporting/reimporting USDZ.

Furniture with low classification confidence is excluded, as are stairs, appliances such as stoves/ovens, and other unsupported categories. Placement uses approximate bounding boxes and a side observed from a camera position during the scan. It is not a free-space/navigation solver; check placement in the demo room.

Broad snapshots include camera positions and forward vectors in the same coordinate frame as the measured room. They are not object-labeled crops. Gemini is instructed to describe uncertainty and avoid guessing which image detail belongs to which ID.

## Room themes

Tap **Room theme** on the welcome screen, or **Theme** while scanning or playing, to choose **Original** or **Jungle**. Jungle adds trailing vines, flowering vines, and fern clusters to visible wall patches. Floors and furniture remain uncovered. Your selection is saved on the device. The theme waits for Gemini's complete room plan; switching afterward reuses that plan and leaves the friend, quest, and badges in place.

The 360° sweep supplies measured geometry and up to six snapshots to Gemini. Gemini chooses a forest or tropical palette and no/light/lush foliage for every usable wall. Floor geometry remains room context but has no decoration treatment. The Jungle plan is generated even when Original is selected. This uses sampled frames rather than a recorded 360° video.

The app retains up to 72 local camera observations (intrinsics, poses, and 64×48 depth samples when available). A botanical's entire bounding footprint must fit inside a measured wall polygon and observed camera views, with a 7 cm placement-check grid. Depth must support the wall within 20 cm, when available; low-confidence samples are rejected. Sightlines also reject intervening measured walls and furniture. Full model footprints keep a margin around doors, windows, openings, furniture, and quest spots. These are conservative, approximate checks; unclassified objects and scan errors can still affect placement. ARKit mesh occlusion supplements the placement checks. Foliage hides while tracking is limited or lost.

The six original Blender USDZs have curved, smooth-shaded leaves with fine thickness, tubular stems, petal geometry, and 1024px leaf color/roughness textures. Each cluster is one model with two to four material batches. Runtime placement caps the scene at 20 clusters and a conservative 350,000-triangle budget, reusing model resources. Low-confidence and curved walls are skipped. Without a usable viewed wall patch, the app asks for more open wall space; it never invents floor coverage. Rescanning clears all geometry and local observation/depth data. Room scans are not persisted.

On a LiDAR device, scan visible wall areas without deliberately aiming at the floor. Check doors, windows, furniture occlusion, and close-up leaf silhouettes; toggle Jungle → Original → Jungle to confirm stable placement. Rescan to check old foliage disappears, and test background/resume tracking. Studio previews verify the asset geometry and materials, but live room placement still needs a fresh scan on the updated app/server.

Validation includes the shared Swift/server JSON contract, mandatory review, surface IDs, quest locations, camera frustums, depth occlusion, rotated furniture sightlines, and complete foliage footprints. `scripts/validate_jungle.swift` loads all six exported assets in RealityKit to verify orientation, scale, mesh count, and imported leaf textures.

## Reliability and privacy

- The app and server validate returned IDs, treatment choices, complete surface coverage, distinct quest locations, and text lengths. No theme is applied and no quest begins before a valid room plan returns.
- Old generation results cannot populate a restarted scan; requests are cancelled and tied to a scan generation ID.
- Leaving the reveal radius or losing tracking clears the proximity dwell timer.
- Backgrounding during scanning requires a fresh scan on return. During gameplay, the app attempts to resume tracking. **Scan again** is the recovery path if relocalization fails.
- Network/provider failures offer a retry using the same captured geometry and snapshots. There is no silent local fallback pretending to be Gemini. Quota and provider-unavailable errors explain the retry condition.
- Camera frames are sampled into at most six JPEGs with a maximum dimension of 640 pixels. They are held in memory and discarded after successful planning or rescan. Room data and images go to your configured server and Gemini. The proxy does not log or save those payloads and requests `store: false` from the provider; this is not a claim about provider-wide retention policies.
- The API key is only read by the server from `GEMINI_API_KEY`.

## Blender sources and exports

- `Art/Jungle/PocketRealm-Jungle.blend`: editable botanicals with packed textures and a studio wall preview.
- `Art/Jungle/jungle-botanicals.png`: rendered asset preview; this is not a screenshot of live AR.
- `Art/Jungle/manifest.json`: triangle counts, dimensions, material counts, and sizes for each export.
- `PocketRealm/Resources/Jungle/*.usdz`: Y-up botanicals, upper attachment at the origin, foliage extending down -Y and outward +Z. Xcode preserves the `Jungle` resource folder.
- Rebuild with `/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/build_jungle.py`. Validate with `swift scripts/validate_jungle.swift "$PWD/PocketRealm/Resources/Jungle"`.



- `Art/Creatures/PocketRealm-Friends.blend`: editable scene with all six named characters, materials, camera, and studio lighting. After the reaction-preview step below, frames 1–168 contain an animated demonstration with labeled cues. Each character has a separate parent; the lineup positions are for presentation only.
- `Art/Creatures/*.glb`: individual portable models at the origin.
- `PocketRealm/Resources/Creatures/*.usdz`: app assets, in meters with Y up and faces pointing toward +Z. They are roughly 35–48 cm tall. The Xcode folder resource preserves the `Creatures` path.
- `Art/Creatures/*.png`: individual portraits and the lineup. The same portraits are copied into the app's asset catalog.
- `Art/Creatures/Textures/*.png`: original baked skin, wing, and shell paint. These textures are also packed into the Blender scene and individual exports.
- `scripts/build_creatures.py`: reproducible Blender 5.2 authoring, export, and render script. Uses Blender's bundled Python and NumPy; no add-ons or extra dependencies. Run from this repository:

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/build_creatures.py
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/inspect_creatures.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift scripts/validate_creatures.swift "$PWD/PocketRealm/Resources/Creatures" "$PWD/Art/Creatures/manifest.json"
```

Each character has one closed, continuous body: the main volumes are voxel-fused, relaxed, subdivided, and reduced for export. Face and belly colors are painted onto the surface; Glimlo has continuous wing membranes, and Pebblin's spiral is fused into its shell. Eyes and accessories remain separate. The six USDZs contain 10–18 mesh entities and about 51k–90k triangles each, with embedded 1024-pixel base-color maps and USD Preview Surface materials. Blender's soft subsurface shading is a studio-render enhancement; runtime lighting can look different. RealityKit drives blinking, breathing, speech nods, pet squishes with hearts, play dances, and star celebrations from `FriendMotion` through named eye, mouth, wing/leaf/ear, tail, and shell pivots. These are procedural transforms, not skeletal animation rigs. Camera-free previews use SceneKit, independently of the room’s RealityKit renderer; both use the same `FriendMotion` pose sampler and named model controls. Absolute poses prevent drift, rapid taps are debounced, and earned celebrations finish before another reaction. AR reactions pause during tracking loss or suspension; Reduce Motion removes hops, spins, appendage motion, and particles. Quest keepsakes are small RealityKit primitives.

Create the playable Blender timeline and a small MP4 using the exact app pose sampler (requires Xcode command-line tools and FFmpeg):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc \
  PocketRealm/Core/RealmFriend.swift PocketRealm/Core/FriendMotion.swift \
  scripts/export_motion_preview.swift -o build/export-motion-preview
build/export-motion-preview "$PWD/build/friend-motion-preview.json"
/Applications/Blender.app/Contents/MacOS/Blender --background --python scripts/build_reaction_preview.py
```

Run this after `build_creatures.py`, which creates the neutral scene. To re-render an already-keyframed scene, append `-- --render-only`. The reel is saved as `Art/Creatures/friends-reactions.mp4`; it demonstrates the same motions under Blender lighting, not a phone recording. The live app computes continuous poses at its frame rate; the reel samples them at 12 fps.

The runtime animation integration check loads every USDZ and exercises all six reactions, checking attachment points, bounded transforms, and particle cleanup:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc \
  PocketRealm/Core/RealmFriend.swift PocketRealm/Core/FriendMotion.swift \
  PocketRealm/AR/CreatureAnimator.swift scripts/validate_friend_animations.swift \
  -o build/validate-friend-animations
build/validate-friend-animations "$PWD/PocketRealm/Resources/Creatures"
```

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

The Swift tests cover scan coverage, progression, mandatory room review, proximity dwell, tracking loss, surface/quest validation, and the one-location case. Server tests cover spatial snapshot validation, room-grounded prompts and schemas, partial-plan rejection, backward compatibility, provider contracts, missing credentials, and mocked HTTP round trips. Both suites read `Tests/Fixtures/room-plan.json`; its image is a test-only JPEG header stub, never a live API input. The asset scripts verify closed connected bodies, geometry budgets, dimensions, Y-up orientation, embedded paint textures, and actual RealityKit loading with textured materials.

Actual room detection, scan-to-game coordinate alignment, placement outside furniture, interrupted-session recovery, and reveal behavior need the physical iPhone. The simulator cannot validate LiDAR/RoomPlan. A live Gemini smoke test requires your configured key and model access.

Character update validation: seven Swift tests and eleven server tests passed. The unsigned iPhone and simulator builds passed, all three USDZs loaded in RealityKit with materials, and the Blender portraits and lineup were visually inspected. Live Gemini and physical room-scan/quest behavior still need verification on the LiDAR-equipped iPhone; this character update has not been installed on the phone.

Sculpt revision validation: all three exported bodies passed connectivity and closed-surface checks, embedded textures resolved and loaded in RealityKit, and the unsigned iPhone build passed. Updated portraits and the lineup were rendered and visually inspected, and the revised scene was opened in Blender. Physical-device appearance and performance remain unverified.

Six-friend commit validation: 24 Swift tests and 20 server tests passed, the unsigned iPhone build passed, and all six bundled USDZs matched the checked exports. The character assets and all six reaction types also passed the RealityKit loading/animation checks. A development build containing these six characters was installed and launched on the iPhone 17 Pro Max; full room-scan interaction and device appearance still need hands-on verification.
