import importlib.util
import json
from pathlib import Path
import struct
import unittest

BASE=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("training_wad_index", BASE / "training_wad_index.py")
mod=importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def make_wad(names):
    # Test fixtures are synthetic. No original copyrighted assets.
    paths=b"".join(x.encode()+b"\x00" for x in names)
    sources=b"".join(b"test\x00" for _ in names)
    header=b"WWAD"+struct.pack("<I",len(names))+paths+sources
    first=len(header)+16*len(names)
    records=b"".join(struct.pack("<IIII",1,2,2,first+2*i) for i in range(len(names)))
    return header+records+b"OK"*len(names)

class TrainingSourceTests(unittest.TestCase):
    def test_catalog_original_folder(self):
        wad=make_wad(["Levels\\TutorialLevels\\Training01\\messages.txt","Levels\\Level01\\notes.txt","Levels\\TutorialLevels\\Training02\\Briefing.TXT"])
        c=mod.catalog(wad)
        self.assertEqual(len(c),2)
        self.assertTrue(all(x["text_readable"] for x in c))
        self.assertFalse(any("Level01" in x["path"] for x in c))

    def test_bad_header(self):
        with self.assertRaises(mod.InvalidWad):
            mod.catalog(b"NOPE0000")

    def test_bad_offset(self):
        b=bytearray(make_wad(["Levels\\TutorialLevels\\Tut01\\help.txt"]))
        mark=b.find(b"test\x00")+5
        struct.pack_into("<I",b,mark+12,999999)
        with self.assertRaises(mod.InvalidWad):
            mod.catalog(bytes(b))

    def test_manifest_eight_original_lessons(self):
        data=json.loads((BASE/"tutorial-curriculum.json").read_text())
        self.assertEqual([x["order"] for x in data["training"]],list(range(1,9)))
        self.assertEqual(len(set(x["name"] for x in data["training"])),8)
        self.assertTrue(all(x["skills"] and x["observation_targets"] and x["validation"] for x in data["training"]))
        self.assertTrue(all(data["training"][j]["video_start_seconds"] < data["training"][j+1]["video_start_seconds"] for j in range(7)))

if __name__=="__main__":
    unittest.main()
