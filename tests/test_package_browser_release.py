import hashlib
from pathlib import Path
import tarfile
import tempfile
import unittest

from tools.package_browser_release import WASM_HEADER, package_browser


class BrowserReleaseTest(unittest.TestCase):
    def test_reproducible_archive_has_runtime_license_and_checksums(self):
        wasm = WASM_HEADER + b"\x00\x01\x00"  # Empty-named custom section.
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            path = package_browser(directory / "first", "0.2.0", wasm, b"MIT notice", 100)
            repeat = package_browser(directory / "second", "0.2.0", wasm, b"MIT notice", 100)
            self.assertEqual(path.name, "bespoke-browser-0.2.0.tar.gz")
            self.assertEqual(path.read_bytes(), repeat.read_bytes())
            prefix = "bespoke-browser-0.2.0/"
            with tarfile.open(path) as archive:
                files = {}
                for entry in archive:
                    self.assertTrue(entry.isfile())
                    self.assertTrue(entry.name.startswith(prefix))
                    with archive.extractfile(entry) as contents:
                        files[entry.name.removeprefix(prefix)] = contents.read()
            self.assertEqual(set(files), {"README.md", "LICENSE", "bespoke.wasm", "SHA256SUMS"})
            self.assertEqual(files["bespoke.wasm"], wasm)
            self.assertEqual(files["LICENSE"], b"MIT notice")
            self.assertIn(b"BeSpoke Engine 0.2.0", files["README.md"])
            for line in files.pop("SHA256SUMS").decode().splitlines():
                digest, name = line.split("  ")
                self.assertEqual(hashlib.sha256(files.pop(name)).hexdigest(), digest)
            self.assertFalse(files)

    def test_rejects_invalid_inputs_without_creating_an_archive(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / "release"
            wasm = WASM_HEADER + b"\x00\x01\x00"
            cases = [
                ("../bad-version", wasm, b"MIT", 100, "numeric release version"),
                ("0.2.0", WASM_HEADER, b"MIT", 100, "nonempty WebAssembly"),
                ("0.2.0", b"not a module", b"MIT", 100, "nonempty WebAssembly"),
                ("0.2.0", wasm, b"MIT", len(wasm) - 1, "byte budget"),
                ("0.2.0", wasm, b" ", 100, "missing license"),
            ]
            for version, module, license_bytes, limit, message in cases:
                with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                    package_browser(output, version, module, license_bytes, limit)
            self.assertFalse(output.exists())
