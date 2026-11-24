"""Checks --engine hex and --parity on the synthetic fixture and on an export from Hex's keyboard."""
from __future__ import annotations

import json
import os
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
        self.assertEqual((report["exported"], report["replayed"]), (32, 26))
        self.assertEqual(report["skipped"], {"learning state uncertain": 4, "swipe": 1, "tap without point": 1})
        reproduction = report["reproduction"]
        self.assertEqual((reproduction["literalMatches"], reproduction["literals"]), (26, 26))
        self.assertEqual((reproduction["commitMatches"], reproduction["commits"], reproduction["picked"]), (21, 24, 1))

    def test_hex_reads_taps_with_its_typing_model(self):
        export = json.loads(SYNTHETIC.read_text())
        export["words"] = [w for w in export["words"] if w["meant"] == "around"][:1]
        self.assertEqual([t["key"] for t in export["words"][0]["taps"]], list("aroumd"))
        path = Path(self.scratch.name) / "around.json"
        path.write_text(json.dumps(export))
        report = self.report(path, "--engine", "hex")
        self.assertEqual(report["reproduction"]["literalMatches"], 1)
        self.assertEqual(report["reproduction"]["commitMatches"], 1)

    def test_hex_report_names_its_engine(self):
        result = self.run_tool(SYNTHETIC, "--engine", "hex")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith("Typing log replay through Hex's engine: 32 words exported"))

    def test_parity_compares_each_replayed_word_once(self):
        parity = self.report(SYNTHETIC, "--parity", "--show-words")
        self.assertEqual((parity["exported"], parity["compared"], parity["sameCommit"]), (32, 26, 23))
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
        self.assertEqual((parity["compared"], parity["sameCommit"]), (2, 2))
        report = self.report(HEX_JOIN, "--engine", "hex", "--show-words")
        self.assertEqual(report["words"], [{"meant": "observe", "known": True, "logged": "observe",
                                            "replayed": "observe", "replayedLetters": "onset e"}])

if __name__ == "__main__":
    unittest.main()
