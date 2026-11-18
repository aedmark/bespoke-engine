import unittest

from tools.package_linux_release import requirement


ELF = "  Machine:                           Advanced Micro Devices X86-64\n"
LOADER = "  INTERP         0x001000 0x0000000000401000\n"
SDL = " 0x0000000000000001 (NEEDED)             Shared library: [libSDL2-2.0.so.0]\n"
GLIBC = (
    " 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]\n"
    "  0x0020:   Name: GLIBC_2.9   Flags: none  Version: 3\n"
    "  0x0030:   Name: GLIBC_2.36  Flags: none  Version: 4\n"
)


class LinuxReleaseTest(unittest.TestCase):
    def test_static_rejects_either_dynamic_linkage_marker_and_wrong_arch(self):
        self.assertIn("without Zig, SDL2", requirement(ELF, desktop=False))
        for linkage in (LOADER, SDL):
            with self.subTest(linkage=linkage), self.assertRaisesRegex(ValueError, "must not need"):
                requirement(ELF + linkage, desktop=False)
        with self.assertRaisesRegex(ValueError, "Linux x86_64"):
            requirement(ELF.replace("Advanced Micro Devices X86-64", "AArch64"), desktop=False)

    def test_desktop_needs_loader_sdl_and_glibc(self):
        self.assertIn("glibc 2.36 or newer", requirement(ELF + LOADER + SDL + GLIBC, desktop=True))
        for missing in (ELF + SDL + GLIBC, ELF + LOADER + GLIBC, ELF + LOADER + SDL):
            with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, "SDL2 and glibc"):
                requirement(missing, desktop=True)
