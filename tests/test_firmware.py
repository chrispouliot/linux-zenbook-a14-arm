import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("firmware", Path(__file__).resolve().parents[1] / "scripts/firmware.py")
fw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fw)


class FirmwareTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.reference = b"reference firmware fixture"
        self.manifest = [{"name": "test.elf", "referenceSha256": hashlib.sha256(self.reference).hexdigest()}]

    def make_file(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_prefers_reference_over_conflicting_driver_versions(self):
        expected = self.make_file("old/TEST.ELF", self.reference)
        self.make_file("new/test.elf", b"different")
        result = fw.discover([self.root], self.manifest)
        self.assertEqual(result["test.elf"], expected)

    def test_unknown_conflicting_versions_fail(self):
        self.make_file("one/test.elf", b"one")
        self.make_file("two/test.elf", b"two")
        with self.assertRaisesRegex(fw.FirmwareError, "Conflicting"):
            fw.discover([self.root], self.manifest)

    def test_missing_alias_only_recreated_from_exact_reference_bytes(self):
        source = self.make_file("test.elf", self.reference)
        alias = {"name": "alias.elf", "referenceSha256": self.manifest[0]["referenceSha256"]}
        result = fw.discover([self.root], self.manifest + [alias])
        self.assertEqual(result["alias.elf"], source)
        source.write_bytes(b"unfamiliar version")
        with self.assertRaisesRegex(fw.FirmwareError, "Not found: alias"):
            fw.discover([self.root], self.manifest + [alias])

    def test_missing_and_empty_rejected(self):
        with self.assertRaisesRegex(fw.FirmwareError, "Missing"):
            fw.validate(self.root, self.manifest)
        self.make_file("test.elf", b"")
        with self.assertRaisesRegex(fw.FirmwareError, "Empty"):
            fw.validate(self.root, self.manifest)

    def test_different_version_warns_or_fails_strict(self):
        self.make_file("test.elf", b"new")
        _, warnings = fw.validate(self.root, self.manifest)
        self.assertEqual(len(warnings), 1)
        with self.assertRaisesRegex(fw.FirmwareError, "Different"):
            fw.validate(self.root, self.manifest, strict=True)

    def test_copy_idempotent_and_conflicts_preserved(self):
        source = self.make_file("source/test.elf", self.reference)
        output = self.root / "output"
        fw.write_selection({"test.elf": source}, output, self.manifest, strict=True)
        fw.write_selection({"test.elf": source}, output, self.manifest, strict=True)
        (output / "test.elf").write_bytes(b"keep this")
        with self.assertRaisesRegex(fw.FirmwareError, "Refusing"):
            fw.write_selection({"test.elf": source}, output, self.manifest)
        self.assertEqual((output / "test.elf").read_bytes(), b"keep this")

    def test_invalid_set_does_not_create_destination(self):
        source = self.make_file("source/test.elf", b"not reference")
        output = self.root / "output"
        with self.assertRaises(fw.FirmwareError):
            fw.write_selection({"test.elf": source}, output, self.manifest, strict=True)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
