import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
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
        existing.write_bytes(b'existing audio')
        self.assertEqual(music.import_music(self.archive, self.dest), 1)
        self.assertEqual(existing.read_bytes(), b'existing audio')
        self.assertEqual({p.name for p in self.dest.iterdir()}, {'Track00.m4a', 'Track01.m4a'})
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-i', str(self.dest / 'Track00.m4a'),
                        '-f', 'null', '-'], check=True)

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
