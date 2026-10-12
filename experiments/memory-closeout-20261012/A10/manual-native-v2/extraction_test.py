#!/usr/bin/env python3
"""Read-only provenance regressions for the exact Support7 RF extraction path."""
from pathlib import Path
import unittest
import manual_native_v2 as adapter

COMPILER=Path('/home/epentland/ai/canopy/mylang-memory-20261012/.tmp/memory-closeout/coordinator/support7-install/bin/mylang')
OBJECT=Path('/home/epentland/ai/canopy/mylang-memory-20261012-support7/.zig-cache/o/38d22d1e4461e413e446fb42adf284b2/core_number_text.o')
EXPECTED='7cafd8f15b9d865346ab77b26e254d55d93520ffcef564c1f9968dab5085f249'


class Extraction(unittest.TestCase):
    def setUp(self):
        self.embedded=adapter.Embedded(COMPILER,OBJECT)
        self.blob=OBJECT.read_bytes()

    def test_exact_build_input_has_one_complete_readonly_embedding(self):
        self.assertEqual(adapter.sha(self.blob),EXPECTED)
        self.assertEqual(self.embedded.number(),self.blob)
        self.assertEqual(self.embedded.provenance['number']['exact_elf_extent'],len(self.blob))

    def test_truncated_elf_refuses(self):
        for cut in [6,63,len(self.blob)-1]:
            with self.subTest(cut=cut), self.assertRaises(ValueError):
                self.embedded.relocatable_extent(self.blob[:cut])

    def test_extra_bytes_after_exact_extent_refuse(self):
        with self.assertRaisesRegex(ValueError,'exact ELF extent'):
            self.embedded.relocatable_extent(self.blob+b'\0')

    def test_foreign_machine_refuses(self):
        foreign=self.blob[:18]+b'\xb7\0'+self.blob[20:]
        with self.assertRaisesRegex(ValueError,'ET_REL'):
            self.embedded.relocatable_extent(foreign)

    def test_other_compilation_object_refuses(self):
        foreign=self.blob[:-1]+bytes([self.blob[-1]^1])
        with self.assertRaisesRegex(ValueError,'uniquely and completely'):
            self.embedded.complete_input(foreign,'number object')

    def test_duplicate_embedding_refuses(self):
        self.embedded.data+=self.blob
        with self.assertRaisesRegex(ValueError,'uniquely and completely'):
            self.embedded.number()

    def test_writable_segment_refuses(self):
        self.embedded.file_segments=[(start,size,flags|2) for start,size,flags in self.embedded.file_segments]
        with self.assertRaisesRegex(ValueError,'read-only'):
            self.embedded.number()

    def test_unknown_runtime_refuses(self):
        with self.assertRaisesRegex(ValueError,'uniquely and completely'):
            self.embedded.runtime(b'not the compiler runtime or substitute source')


if __name__=='__main__':unittest.main()
