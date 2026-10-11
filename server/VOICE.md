# Nibbi's conversational quest

Nibbi uses ElevenLabs Agents for two-way speech, interruptions, and live captions. The iOS app uses the official ElevenLabs Swift SDK (3.4.0). Nibbi receives the current quest step and dialogue, but no room mesh or camera images. Ordinary chat gives hints. The separate AABB rhyme quest uses a client tool and local pronunciation rules to validate the player’s lines, save their poem, and award Sugar-star Poet. The cookie and memory games retain their existing controls.

## Direct connection on a personal iPhone

In Character voices, enter your ElevenLabs API key and the Nibbi agent ID, then save and check the connection. The key is stored in the iPhone Keychain with WhenUnlockedThisDeviceOnly protection. The app requests ephemeral session tokens directly over HTTPS; a Mac server and shared Wi-Fi are unnecessary. Remove saved key switches back to the optional server mode. No key is embedded in source or the app bundle.

## Voices, narration, and poetry

Enable Text to Speech Access in addition to ElevenAgents Write and Voices Read. Character voices lists your ElevenLabs voices, previews the selected voice, and saves a separate choice for each character. Add favorites in ElevenLabs Voices → Explore, then refresh the list in the app. Nibbi applies her selected voice on the next call.

Run `/usr/bin/python3 server/configure_nibbi.py` once after provisioning to configure the calmer persona, voice override permission, and poem client tool. It reuses the agent and tool IDs in the ignored state file.

Quest objectives are spoken automatically when a puzzle starts, including camera-free practice, and can be repeated with Hear the objective. Narration uses ElevenLabs without a microphone; unavailable narration falls back to the iPhone voice. Memory playback and leaving the screen cancel pending narration.

Choose Rhyme quest beside Nibbi or Try Nibbi’s rhyme quest in Character voices. She gives lines 1 and 3; you speak lines 2 and 4. Rhymes use CMU pronunciation-derived word sets for night and day, not spelling suffixes or syllable counts. An unrecognized ending gets a gentle retry hint. Progress and the completed poem stay on this device. Unknown, invented, duplicate, or out-of-turn tool submissions cannot award progress.

## Optional Mac server setup

1. Put `ELEVENLABS_API_KEY=...` in `server/.env` (ignored by Git). The key needs ElevenAgents Write and Voices Read.
2. Run `/usr/bin/python3 server/voice_server.py` from the repository root. First launch creates a private Nibbi agent and saves its ID and a random pairing code in ignored `server/.env.voice.json`. Subsequent launches reuse it.
3. In the app, open Connection settings → Character voices. Enter `http://YOUR-MAC-LAN-IP:8788` and the pairing code. Keep Mac and phone on the same trusted network. This is a local development server; use authenticated HTTPS hosting for deployment.
4. Choose Nibbi, begin the quest, then tap Talk when nearby. Or use Try talking to Nibbi in Character voices to test before scanning a room.

Tap Talk to Nibbi to allow the microphone and begin. Mute pauses your microphone, End chat disconnects, and Done/swiping down/backgrounding the app also ends the session. Calls are limited to five minutes. The agent is configured not to retain voice recordings and to remove transcripts after one day.

The broker only exchanges a paired request for an ephemeral conversation token. In server mode the ElevenLabs service key stays on the Mac and is never returned by the broker. The broker does not log audio, transcripts, or credentials. Its pairing token grants access to Nibbi sessions, so keep it private too.

## Checks

`/usr/bin/python3 -m unittest discover -s server -p test_voice_server.py`

Covers rejected unpaired requests, the fixed Nibbi endpoint, rate limiting, and sanitized provider errors. Live API verification additionally requires the local service key and may use account credits.

Poem rule tests: `swift test --filter PoetryQuestTests`. Live validation also exercised both poem tool calls and generated a Bloopi objective as MP3 audio.
