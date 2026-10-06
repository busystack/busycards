#!/usr/bin/env python3
"""Filesystem contracts for offline-input verification and independent copies."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

TOOL = Path(__file__).with_name('prepare_offline.py')
spec = importlib.util.spec_from_file_location('prepare_offline', TOOL)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class OfflineInputsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.inputs = self.root / 'inputs'
        self.app = self.root / 'app'
        self.app.mkdir()
        self.payloads = {
            'pub-cache/hosted/pub.dev/example-1.0.0/lib/example.dart': b'public fixture',
            'maven-repository/example/1.0/example.jar': b'public jar fixture',
            'maven-wrapper/apache-maven-3.10.0/bin/mvn': b'#!/bin/sh\nexit 0\n',
            'native/libsqlcipher.x64.linux.so': b'public native fixture',
        }
        self.files = {}
        for name, payload in self.payloads.items():
            path = self.inputs / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
            self.files[name] = hashlib.sha256(payload).hexdigest()
        (self.inputs / 'maven-wrapper/apache-maven-3.10.0/bin/mvn').chmod(0o755)
        self.write_manifest()
        for name, value in [('APP', self.app),
                            ('SQLCIPHER_SHA256', self.files['native/libsqlcipher.x64.linux.so'])]:
            substitution = patch.object(prepare, name, value)
            substitution.start()
            self.addCleanup(substitution.stop)
        environment = patch.dict(os.environ, {'PUB_CACHE': str(self.app / 'validation/pub-cache')})
        environment.start()
        self.addCleanup(environment.stop)
        # Tiny native fixture bytes use an injected expected hash only in this
        # module instance; the unchanged production pin is asserted separately.

    def write_manifest(self):
        (self.inputs / 'manifest.json').write_text(json.dumps({'files': self.files}))

    def execute(self):
        with patch('sys.argv', [str(TOOL), str(self.inputs)]):
            prepare.main()

    def assert_rejected_before_copy(self):
        with self.assertRaises(ValueError):
            self.execute()
        self.assertEqual(list(self.app.iterdir()), [], 'Rejected inputs changed a destination')

    def test_complete_inputs_make_independent_copies_with_execute_permissions(self):
        self.execute()
        copied = self.app / 'validation/pub-cache/hosted/pub.dev/example-1.0.0/lib/example.dart'
        source = self.inputs / 'pub-cache/hosted/pub.dev/example-1.0.0/lib/example.dart'
        self.assertEqual(copied.read_bytes(), source.read_bytes())
        self.assertNotEqual(copied.stat().st_ino, source.stat().st_ino)
        source.write_bytes(b'changed source after copy')
        self.assertEqual(copied.read_bytes(), b'public fixture')
        wrapper = self.app / 'native/microsoft_auth_helper/target/wrapper/apache-maven-3.10.0/bin/mvn'
        self.assertTrue(os.access(wrapper, os.X_OK))
        native = self.app / '.dart_tool/hooks_runner/shared/sqlite3/build/download-cd09126c/libsqlcipher.so'
        self.assertEqual(native.read_bytes(), self.payloads['native/libsqlcipher.x64.linux.so'])
        self.assertEqual(len([p for p in self.app.rglob('*') if p.is_file()]), 4)

    def test_unlisted_file_is_rejected_before_copy(self):
        (self.inputs / 'pub-cache/unlisted.txt').write_text('unlisted bytes')
        self.assert_rejected_before_copy()

    def test_missing_listed_file_is_rejected_before_copy(self):
        (self.inputs / 'maven-repository/example/1.0/example.jar').unlink()
        self.assert_rejected_before_copy()

    def test_directory_symlink_is_rejected_before_copy(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'sentinel.txt').write_text('outside fixture')
        (self.inputs / 'pub-cache/unlisted-directory').symlink_to(outside, target_is_directory=True)
        self.assert_rejected_before_copy()

    def test_file_symlink_is_rejected_before_copy(self):
        source = self.inputs / 'maven-repository/example/1.0/example.jar'
        source.unlink()
        source.symlink_to(self.inputs / 'native/libsqlcipher.x64.linux.so')
        self.assert_rejected_before_copy()

    def test_manifest_symlink_is_rejected_before_read_or_copy(self):
        manifest = self.inputs / 'manifest.json'
        external = self.root / 'external-manifest.json'
        manifest.rename(external)
        manifest.symlink_to(external)
        self.assert_rejected_before_copy()

    def test_root_directory_symlink_is_rejected(self):
        link = self.root / 'linked-inputs'
        link.symlink_to(self.inputs, target_is_directory=True)
        with patch('sys.argv', [str(TOOL), str(link)]):
            with self.assertRaises(ValueError):
                prepare.main()
        self.assertEqual(list(self.app.iterdir()), [])

    def test_hardlinked_input_is_rejected_before_copy(self):
        source = self.inputs / 'maven-repository/example/1.0/example.jar'
        os.link(source, self.root / 'outside-hardlink')
        self.assert_rejected_before_copy()

    def test_fifo_input_is_rejected_before_open_or_copy(self):
        os.mkfifo(self.inputs / 'pub-cache/unlisted-fifo')
        self.assert_rejected_before_copy()

    def test_tampered_hash_is_rejected_before_copy(self):
        (self.inputs / 'maven-repository/example/1.0/example.jar').write_bytes(b'tampered')
        self.assert_rejected_before_copy()

    def test_malformed_manifest_is_rejected_before_copy(self):
        for text in ('not json', '[]', '{"files": []}'):
            with self.subTest(text=text):
                (self.inputs / 'manifest.json').write_text(text)
                self.assert_rejected_before_copy()

    def test_pinned_native_mismatch_is_rejected_before_any_cache_copy(self):
        with patch.object(prepare, 'SQLCIPHER_SHA256', '0' * 64):
            self.assert_rejected_before_copy()

    def test_manifest_traversal_absolute_or_unexpected_native_paths_are_rejected(self):
        original = dict(self.files)
        for name in ('../outside', '/absolute', 'pub-cache/../outside',
                     'pub-cache\\outside', 'native/unexpected.so', 'pub-cache'):
            with self.subTest(name=name):
                self.files = {**original, name: '0' * 64}
                self.write_manifest()
                self.assert_rejected_before_copy()

    def test_verified_copy_rechecks_changed_source_before_replacing_destination(self):
        source = self.inputs / 'maven-repository/example/1.0/example.jar'
        destination = self.root / 'copy/example.jar'
        destination.parent.mkdir()
        destination.write_bytes(b'previous valid bytes')
        prepare.verify_inputs(self.inputs)
        source.write_bytes(b'changed after preflight')
        with self.assertRaisesRegex(ValueError, 'changed after verification'):
            prepare.copy_verified(source, destination, self.files['maven-repository/example/1.0/example.jar'])
        self.assertEqual(destination.read_bytes(), b'previous valid bytes')
        self.assertEqual(list(destination.parent.iterdir()), [destination])

    def test_production_sqlcipher_pin_is_unchanged(self):
        self.assertIn(
            "SQLCIPHER_SHA256='cd09126c9e85191f2b4f57e6c0bcd232c7481f56fb1d659b79374ccad21bfef9'",
            TOOL.read_text())


if __name__ == '__main__':
    unittest.main()
