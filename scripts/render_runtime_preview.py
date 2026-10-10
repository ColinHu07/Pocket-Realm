"""Render the newest trio with the app's SceneKit animator on macOS.

Uses the actual PreviewAnimator source, with only UIKit/AppKit type adapters.
Requires Xcode and FFmpeg; outputs Art/Creatures/friends-new-runtime.mp4.
"""
from pathlib import Path
import os
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
build = root / 'build'
build.mkdir(exist_ok=True)
source = (root / 'PocketRealm/Views/FriendPreview.swift').read_text()
marker = '@MainActor final class PreviewAnimator {'
assert marker in source, 'PreviewAnimator moved; update the source extraction path.'
source = marker + source.split(marker, 1)[1]
source = source.replace('UIBezierPath()', 'NSBezierPath()')
source = source.replace('path.addLine(to:', 'path.line(to:')
source = source.replace('UIColor(', 'NSColor(')
source = source.replace('height = root.boundingBox.max.y', 'height = Float(root.boundingBox.max.y)')
source = source.replace('.one * max(', 'SIMD3<Float>(repeating: 1) * max(')
adapter = build / 'new-trio-preview-animator.swift'
adapter.write_text('import Foundation\nimport SceneKit\nimport AppKit\nimport simd\n' + source)
environment = dict(os.environ)
environment.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
executable = build / 'render-new-trio'
subprocess.run(['swiftc', 'PocketRealm/Core/RealmFriend.swift', 'PocketRealm/Core/FriendMotion.swift',
                str(adapter), 'scripts/render_runtime_preview.swift', '-o', str(executable)],
               cwd=root, env=environment, check=True)
ffmpeg = shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg'
subprocess.run([str(executable), ffmpeg], cwd=root, env=environment, check=True)
