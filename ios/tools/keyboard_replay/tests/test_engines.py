"""Checks --engine hex and --parity on the synthetic fixture and on an export from Hex's keyboard."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1]
SYNTHETIC = TOOL / "fixture" / "synthetic.json"
HEX_JOIN = TOOL / "fixture" / "hex-join.json"


class EngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.scratch = tempfile.TemporaryDirectory()
        binary = os.environ.get("KEYBOARD_REPLAY")
        if not binary:
            built = subprocess.run(["bash", str(TOOL / "build.sh"), str(Path(cls.scratch.name) / "build")],
                                   capture_output=True, text=True, check=True)
            binary = built.stdout.strip().splitlines()[-1]
        cls.binary = binary

    @classmethod
    def tearDownClass(cls) -> None:
        cls.scratch.cleanup()

    def run_tool(self, export: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run([self.binary, str(export), *args], capture_output=True, text=True,
                              cwd=self.scratch.name, timeout=120)

    def report(self, export: Path, *args: str) -> dict:
        result = self.run_tool(export, "--json", *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_typr_is_the_default_engine(self):
        self.assertEqual(self.report(SYNTHETIC), self.report(SYNTHETIC, "--engine", "typr"))
        self.assertEqual(self.report(SYNTHETIC)["engine"], "typr")

    def test_an_unknown_engine_is_refused(self):
        result = self.run_tool(SYNTHETIC, "--engine", "apple")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--engine", result.stderr)

    def test_hex_replays_the_words_typr_replays(self):
        report = self.report(SYNTHETIC, "--engine", "hex")
        self.assertEqual(report["engine"], "hex")
        self.assertEqual((report["exported"], report["replayed"]), (32, 9))
        self.assertEqual(report["skipped"], {"learning state uncertain": 4, "needs system spelling": 17, "swipe": 1,
                                             "tap without point": 1})
        reproduction = report["reproduction"]
        self.assertEqual((reproduction["literalMatches"], reproduction["literals"]), (9, 9))
        self.assertEqual((reproduction["commitMatches"], reproduction["commits"], reproduction["picked"]), (4, 7, 1))

    def test_a_word_whose_hex_commit_needs_system_spelling_is_skipped(self):
        export = json.loads(SYNTHETIC.read_text())
        export["words"] = [w for w in export["words"] if w["meant"] == "around"][:1]
        path = Path(self.scratch.name) / "around.json"
        path.write_text(json.dumps(export))
        self.assertEqual(self.report(path, "--engine", "hex")["skipped"], {"needs system spelling": 1})
        self.assertEqual(self.report(path, "--parity")["skipped"], {"Hex: needs system spelling": 1})
        self.assertEqual(self.report(path)["replayed"], 1)

    def test_taps_map_onto_hex_keys_as_hex_keyboard_logs_them(self):
        result = subprocess.run([self.binary, "--tap-mapping"], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        mapping = json.loads(result.stdout)
        self.assertEqual((mapping["en"]["taps"], mapping["en"]["unmapped"]), (26 * 9 + 3, 0))
        self.assertEqual((mapping["de"]["taps"], mapping["de"]["unmapped"]), (26 * 9 + 3, 3 * 9))
        for language in ("en", "de"):
            self.assertLess(mapping[language]["maxError"], 1e-9)

    def copy_of_the_build(self) -> Path:
        copy = Path(tempfile.mkdtemp(dir=self.scratch.name)) / "build"
        shutil.copytree(Path(self.binary).resolve().parent, copy, ignore=shutil.ignore_patterns("modules", "trimmed"))
        return copy

    def assert_hex_refuses(self, build: Path, missing: str):
        for args in (["--engine", "hex"], ["--parity"]):
            result = subprocess.run([str(build / "keyboard-replay"), str(SYNTHETIC), *args], capture_output=True,
                                    text=True, timeout=120)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(missing, result.stderr)
            self.assertEqual(result.stdout, "")
        typr = subprocess.run([str(build / "keyboard-replay"), str(SYNTHETIC)], capture_output=True, text=True,
                              timeout=120)
        self.assertEqual(typr.returncode, 0, typr.stderr)

    def test_hex_refuses_to_run_without_its_english_model(self):
        build = self.copy_of_the_build()
        (build / "en.hextm").unlink()
        self.assert_hex_refuses(build, "en.hextm")

    def test_hex_refuses_to_run_with_a_broken_english_model(self):
        build = self.copy_of_the_build()
        (build / "en.hextm").write_bytes(b"not a model")
        self.assert_hex_refuses(build, "en.hextm")

    def test_hex_refuses_to_run_with_a_broken_never_suggest_list(self):
        for content in (b"", b"garbled \x00 text\n", b"en\tslur\n", b"en\tmaybe\tword\n"):
            build = self.copy_of_the_build()
            (build / "never-suggest.tsv").write_bytes(content)
            self.assert_hex_refuses(build, "never-suggest.tsv")

    def test_hex_refuses_to_run_with_broken_german_capitals(self):
        for content in (b"", b"garbled \x00 text\n", b"aachen\t100\naal\n", b"aal\tninety\n", b"aal\t300\n"):
            build = self.copy_of_the_build()
            (build / "de.capitals").write_bytes(content)
            self.assert_hex_refuses(build, "de.capitals")

    def test_hex_refuses_to_run_without_its_never_suggest_list(self):
        build = self.copy_of_the_build()
        (build / "never-suggest.tsv").unlink()
        self.assert_hex_refuses(build, "never-suggest.tsv")

    def test_hex_report_names_its_engine(self):
        result = self.run_tool(SYNTHETIC, "--engine", "hex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("Typing log replay through Hex's engine: 32 words exported"))

    def test_parity_compares_each_replayed_word_once(self):
        parity = self.report(SYNTHETIC, "--parity", "--show-words")
        self.assertEqual((parity["exported"], parity["compared"], parity["sameCommit"]), (32, 9, 6))
        self.assertEqual(parity["compared"] + sum(parity["skipped"].values()), parity["exported"])
        self.assertEqual(len(parity["differences"]), parity["compared"] - parity["sameCommit"])
        for line in parity["differences"]:
            self.assertNotEqual(line["typr"], line["hex"])
        hex_report = self.report(SYNTHETIC, "--engine", "hex")
        self.assertEqual(parity["hex"], hex_report["score"])

    def test_parity_without_show_words_lists_no_text(self):
        parity = self.report(SYNTHETIC, "--parity")
        self.assertNotIn("differences", parity)
        result = self.run_tool(SYNTHETIC, "--parity")
        self.assertTrue(result.stdout.startswith("Engine parity: 32 words exported"))
        self.assertNotIn("Commits differ", result.stdout)

    def test_hex_keyboard_export_reproduces_through_typr(self):
        report = self.report(HEX_JOIN)
        reproduction = report["reproduction"]
        self.assertEqual((report["exported"], report["replayed"]), (2, 2))
        self.assertEqual((reproduction["commitMatches"], reproduction["commits"]), (2, 2))

    def test_hex_joins_the_words_typr_joined(self):
        parity = self.report(HEX_JOIN, "--parity")
        self.assertEqual((parity["compared"], parity["sameCommit"]), (1, 1))
        self.assertEqual(parity["skipped"], {"Hex: needs system spelling": 1})
        report = self.report(HEX_JOIN, "--engine", "hex", "--show-words")
        self.assertEqual(report["words"], [{"meant": "observe", "known": True, "logged": "observe",
                                            "replayed": "observe", "replayedLetters": "onset e"}])

if __name__ == "__main__":
    unittest.main()
