from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

spec = importlib.util.spec_from_file_location('music', Path(__file__).parents[1] / 'import-mission-music.py')
music = importlib.util.module_from_spec(spec)
spec.loader.exec_module(music)


@unittest.skipUnless(shutil.which('ffmpeg'), 'FFmpeg not installed')
class MusicImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        tone = self.root / 'tone.ogg'
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i',
                        'sine=frequency=440:duration=0.15', '-c:a', 'libvorbis', str(tone)], check=True)
        self.audio = tone.read_bytes()
        existing = self.root / 'existing.m4a'
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-f', 'lavfi', '-i',
                        'sine=frequency=660:duration=0.15', '-c:a', 'aac', '-movflags', '+faststart',
                        str(existing)], check=True)
        self.existing_audio = existing.read_bytes()
        self.archive = self.root / 'music.zip'
        self.dest = self.root / 'cache'

    def zip(self, entries):
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, data in entries:
                z.writestr(name, data)

    def test_real_conversion_ignores_dlls_and_preserves_existing(self):
        self.zip([('Music/Track00.ogg', self.audio), ('Music/Track01.ogg', self.audio),
                  ('winmm.dll', b'never install'), ('Music/Atmosdel.wav', b'never import')])
        self.dest.mkdir()
        existing = self.dest / 'Track01.m4a'
        existing.write_bytes(self.existing_audio)
        previous_stat = existing.stat()
        self.assertEqual(music.import_music(self.archive, self.dest), 1)
        self.assertEqual(existing.read_bytes(), self.existing_audio)
        self.assertEqual(existing.stat().st_ino, previous_stat.st_ino)
        self.assertEqual(existing.stat().st_mtime_ns, previous_stat.st_mtime_ns)
        self.assertEqual({p.name for p in self.dest.iterdir()}, {'Track00.m4a', 'Track01.m4a'})
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', str(self.dest / 'Track00.m4a'),
                        '-f', 'null', '-'], check=True)
        # A repeat import validates both retained tracks but publishes nothing.
        published_audio = (self.dest / 'Track00.m4a').read_bytes()
        self.assertEqual(music.import_music(self.archive, self.dest), 0)
        self.assertEqual((self.dest / 'Track00.m4a').read_bytes(), published_audio)
        self.assertEqual(existing.read_bytes(), self.existing_audio)

    def test_invalid_existing_track_does_not_publish_or_report_ready(self):
        self.zip([('Track00.ogg', self.audio), ('Track01.ogg', self.audio)])
        self.dest.mkdir()
        existing = self.dest / 'Track01.m4a'
        # The truncated M4A retains its header and decodable initial packets;
        # FFmpeg without strict decoding can exit successfully for this file.
        for invalid in (b'', b'invalid audio', self.existing_audio[:-128]):
            with self.subTest(size=len(invalid)):
                existing.write_bytes(invalid)
                output = io.StringIO()
                with redirect_stdout(output), self.assertRaises(ValueError) as raised:
                    music.import_music(self.archive, self.dest)
                self.assertIn(f'Existing track is not valid audio: {existing}', str(raised.exception))
                self.assertIn('it was not overwritten', str(raised.exception))
                self.assertNotIn('Mission music ready', output.getvalue())
                self.assertEqual(existing.read_bytes(), invalid)
                self.assertEqual({p.name for p in self.dest.iterdir()}, {'Track01.m4a'})

    def test_valid_publication_race_keeps_existing_track(self):
        self.zip([('Track00.ogg', self.audio)])
        real_link = music.os.link

        def publish_competing_track(converted, target):
            target.write_bytes(self.existing_audio)
            real_link(converted, target)

        output = io.StringIO()
        with mock.patch.object(music.os, 'link', side_effect=publish_competing_track) as link:
            with redirect_stdout(output):
                self.assertEqual(music.import_music(self.archive, self.dest), 0)
        link.assert_called_once()
        self.assertIn('Keeping existing Track00.m4a', output.getvalue())
        self.assertIn('Mission music ready', output.getvalue())
        self.assertEqual((self.dest / 'Track00.m4a').read_bytes(), self.existing_audio)
        self.assertEqual({p.name for p in self.dest.iterdir()}, {'Track00.m4a'})

    def test_invalid_publication_race_is_not_overwritten_or_reported_ready(self):
        self.zip([('Track00.ogg', self.audio)])
        real_link = music.os.link
        target = self.dest / 'Track00.m4a'
        for invalid in (b'', b'invalid audio', self.existing_audio[:-128]):
            with self.subTest(size=len(invalid)):
                def publish_competing_track(converted, target):
                    target.write_bytes(invalid)
                    real_link(converted, target)

                output = io.StringIO()
                with mock.patch.object(music.os, 'link', side_effect=publish_competing_track) as link:
                    with redirect_stdout(output), self.assertRaises(ValueError) as raised:
                        music.import_music(self.archive, self.dest)
                link.assert_called_once()
                self.assertIn(f'Existing track is not valid audio: {target}', str(raised.exception))
                self.assertNotIn('Mission music ready', output.getvalue())
                self.assertEqual(target.read_bytes(), invalid)
                self.assertEqual({p.name for p in self.dest.iterdir()}, {'Track00.m4a'})
                target.unlink()

    def test_cli_rejects_invalid_existing_track_with_exact_path(self):
        self.zip([('Track00.ogg', self.audio)])
        self.dest.mkdir()
        target = self.dest / 'Track00.m4a'
        target.write_bytes(b'invalid audio')
        result = subprocess.run([sys.executable, str(Path(music.__file__)), str(self.archive),
                                 '--destination', str(self.dest)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn(f'Music import failed: Existing track is not valid audio: {target}', result.stderr)
        self.assertIn('Move it out of the cache and retry; it was not overwritten.', result.stderr)
        self.assertNotIn('Mission music ready', result.stdout)
        self.assertEqual(target.read_bytes(), b'invalid audio')

    def test_archive_paths_cannot_escape_destination(self):
        self.zip([('../../Track00.ogg', self.audio)])
        music.import_music(self.archive, self.dest)
        self.assertTrue((self.dest / 'Track00.m4a').is_file())
        self.assertFalse((self.root / 'Track00.ogg').exists())

    def test_duplicate_track_rejected_before_install(self):
        self.zip([('a/Track00.ogg', self.audio), ('b/track00.ogg', self.audio)])
        with self.assertRaises(ValueError):
            music.import_music(self.archive, self.dest)
        self.assertFalse(self.dest.exists())

    def test_failed_conversion_does_not_publish_partial_playlist(self):
        self.zip([('Track00.ogg', self.audio), ('Track01.ogg', b'invalid audio')])
        with self.assertRaises(subprocess.CalledProcessError):
            music.import_music(self.archive, self.dest)
        self.assertEqual(list(self.dest.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
