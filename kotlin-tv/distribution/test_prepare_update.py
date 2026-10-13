"""Run with UPDATE_APK, PREVIOUS_APK and ANDROID_BUILD_TOOLS pointing to real APK fixtures."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class PrepareUpdateTest(unittest.TestCase):
    def test_manifest_matches_verified_apk_and_rejects_rollback_or_unsafe_tag(self):
        apk = Path(os.environ['UPDATE_APK']).resolve()
        previous = Path(os.environ['PREVIOUS_APK']).resolve()
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'update.json'
            command = [sys.executable, str(Path(__file__).with_name('prepare-update.py')),
                       '--apk', str(apk), '--previous-apk', str(previous),
                       '--build-tools', os.environ['ANDROID_BUILD_TOOLS'],
                       '--tag', 'tv-v0.11.0-local', '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stderr)
            manifest = json.loads(output.read_text())
            self.assertEqual(('com.hongguotv.nativeapp', 11, '0.11.0-local', 26),
                             tuple(manifest[k] for k in ('packageName', 'versionCode', 'versionName', 'minSdk')))
            self.assertEqual(apk.name, manifest['apk']['name'])
            self.assertEqual(apk.stat().st_size, manifest['apk']['size'])
            self.assertEqual(hashlib.sha256(apk.read_bytes()).hexdigest(), manifest['apk']['sha256'])
            output.unlink()
            command[command.index('--previous-apk') + 1] = str(apk)
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('versionCode', result.stderr)
            self.assertFalse(output.exists())
            command[command.index('--previous-apk') + 1] = str(previous)
            command[command.index('--tag') + 1] = 'tv-v../other'
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
