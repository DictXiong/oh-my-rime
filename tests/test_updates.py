"""Offline failure-injection tests. No real downloads or user dictionaries are touched."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TARGETS = (
    'dicts/rime_word_marker_export.dict.yaml',
    'dicts/rime_ice.cn_en_double_pinyin.txt',
    'opencc/rime_word_marker_export.opencc.txt',
    'rime_mint.dict.yaml',
    'opencc/emoji.json',
)
MODEL = b'VALID_MODEL_FIXTURE\x00\x01'
MOCK_CURL = r'''
import hashlib, json, os, pathlib, sys
args = sys.argv[1:]
url = next(s for s in args if s.startswith('https://'))
output = pathlib.Path(args[args.index('-o') + 1])
model = b'VALID_MODEL_FIXTURE\x00\x01'
if url.endswith('/releases/tags/LTS'):
    kind = 'metadata'
    digest = 'sha256:' + hashlib.sha256(model).hexdigest()
    if os.environ.get('MOCK_NO_DIGEST'): digest = None
    data = json.dumps({'assets': [{'name': 'wanxiang-lts-zh-hans.gram', 'size': len(model),
        'digest': digest,
        'browser_download_url': 'https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram'}]}).encode()
elif url.endswith('.gram'):
    kind, data = 'model', model
elif url.endswith('melt_eng.schema.yaml'):
    kind, data = 'schema', b'schema:\n  schema_id: melt_eng\n'
elif 'export_mode=main' in url:
    kind, data = 'main', b'---\nname: rime_word_marker_export\nversion: "test"\nsort: by_weight\n...\n'
    if not os.environ.get('MOCK_EMPTY_PRIVATE'): data += '\u79c1\u8bcd\tci\t1\n'.encode()
elif 'export_mode=mixed' in url:
    kind, data = 'mixed', ('\u79c1AI\tsiAI' if not os.environ.get('MOCK_EMPTY_PRIVATE') else '').encode()
elif 'export_mode=opencc' in url:
    kind, data = 'opencc', ('\u79c1\u8bcd\t\u79c1\u8bcd AI\n' if not os.environ.get('MOCK_EMPTY_PRIVATE') else '').encode()
elif url.endswith('cn_en_double_pinyin.txt'):
    kind, data = 'upstream', b'# table\nX\tXcode'
else:
    kind, data = 'index', b'Rime Word Marker'
with open(os.environ['MOCK_LOG'], 'a') as log: log.write(kind + '\n')
if os.environ.get('MOCK_BAD_AT') == kind: data = b'<html>error</html>\n'
if os.environ.get('MOCK_CORRUPT_MODEL') and kind == 'model': data = b'X' * len(model)
output.write_bytes(data)
if os.environ.get('MOCK_FAIL_AT') == kind: sys.exit(18)
'''
MOCK_MV = r'''
import os, pathlib, subprocess, sys
src, dst = sys.argv[1:]
marker = pathlib.Path(os.environ['MOCK_MV_MARKER'])
if '/backup/' not in src and dst == os.environ.get('MOCK_MV_FAIL_TARGET') and not marker.exists():
    marker.touch()
    sys.exit(1)
sys.exit(subprocess.call([os.environ['REAL_MV'], src, dst]))
'''


class Updates(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rime update test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.root / 'dicts').mkdir()
        (self.root / 'opencc').mkdir()
        for name in ('update_dict.sh', 'update_patch.sh', 'rime_mint.dict.yaml', 'opencc/emoji.json'):
            shutil.copyfile(ROOT / name, self.root / name)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        MOCK_LOG=str(self.root / 'calls'), MOCK_MV_MARKER=str(self.root / 'mv-failed'),
                        REAL_MV=shutil.which('mv'))
        for name, script in (('curl', MOCK_CURL), ('mv', MOCK_MV)):
            path = self.bin / name
            path.write_text('#!' + sys.executable + '\n' + script)
            path.chmod(0o755)

    def seed_old(self):
        for name in TARGETS[:3]:
            (self.root / name).write_bytes(b'OLD_VALID_CONTENT\n')
        (self.root / 'melt_eng.schema.yaml').write_bytes(b'OLD_SCHEMA\n')

    def snapshot(self, names=TARGETS):
        return {name: (self.root / name).read_bytes() if (self.root / name).exists() else None for name in names}

    def run_script(self, name='update_dict.sh', options=None, shell=None):
        env = self.env | (options or {})
        command = (shell or [os.environ.get('TEST_SH', '/bin/sh')]) + [str(self.root / name)]
        if name == 'update_dict.sh': command.append('https://example.invalid/')
        return subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)

    def assert_clean(self, result, success):
        if success: self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else: self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(list(self.root.glob('.update-*')))

    def test_dict_download_failures_preserve_all_files(self):
        self.seed_old()
        before = self.snapshot()
        for stage in ('index', 'main', 'upstream', 'mixed', 'opencc'):
            with self.subTest(stage=stage):
                self.assert_clean(self.run_script(options={'MOCK_FAIL_AT': stage}), False)
                self.assertEqual(self.snapshot(), before)

    def test_dict_invalid_responses_preserve_all_files(self):
        self.seed_old()
        before = self.snapshot()
        for stage in ('index', 'main', 'upstream', 'mixed', 'opencc'):
            with self.subTest(stage=stage):
                self.assert_clean(self.run_script(options={'MOCK_BAD_AT': stage}), False)
                self.assertEqual(self.snapshot(), before)

    def test_success_and_idempotent_private_integration(self):
        for _ in range(2):
            self.assert_clean(self.run_script(), True)
            dictionary = (self.root / TARGETS[3]).read_text()
            self.assertEqual(dictionary.count('  - dicts/rime_word_marker_export'), 1)
            config = json.loads((self.root / TARGETS[4]).read_text())
            files = [x['file'] for x in config['conversion_chain'][0]['dict']['dicts']]
            self.assertEqual(files.count('rime_word_marker_export.opencc.txt'), 1)
            self.assertEqual((self.root / TARGETS[1]).read_text(), '# table\nX\tXcode\n私AI\tsiAI\n')

    def test_empty_private_exports_are_valid(self):
        self.assert_clean(self.run_script(options={'MOCK_EMPTY_PRIVATE': '1'}), True)
        self.assertEqual((self.root / TARGETS[2]).read_bytes(), b'')

    def test_replacement_failure_rolls_back_existing_files(self):
        self.seed_old()
        before = self.snapshot()
        self.assert_clean(self.run_script(options={'MOCK_MV_FAIL_TARGET': TARGETS[1]}), False)
        self.assertEqual(self.snapshot(), before)

    def test_replacement_failure_removes_new_files(self):
        before = self.snapshot()
        self.assert_clean(self.run_script(options={'MOCK_MV_FAIL_TARGET': TARGETS[2]}), False)
        self.assertEqual(self.snapshot(), before)

    def test_unsupported_custom_config_is_not_overwritten(self):
        (self.root / TARGETS[4]).write_text(json.dumps(json.loads((self.root / TARGETS[4]).read_text())))
        before = self.snapshot()
        self.assert_clean(self.run_script(), False)
        self.assertEqual(self.snapshot(), before)

    def test_dict_with_dash(self):
        dash = os.environ.get('TEST_DASH') or shutil.which('dash')
        if not dash: self.skipTest('dash is not installed')
        self.assert_clean(self.run_script(shell=[dash]), True)

    def test_dict_with_busybox_commands(self):
        busybox = os.environ.get('TEST_BUSYBOX') or shutil.which('busybox')
        if not busybox: self.skipTest('BusyBox is not installed')
        # Exercise BusyBox text/file commands too, not only its shell parser.
        for name in ('dirname', 'mkdir', 'grep', 'awk', 'sed', 'cp', 'rm', 'wc'):
            (self.bin / name).symlink_to(busybox)
        self.env['REAL_MV'] = busybox
        # BusyBox dispatches by argv[0], so let its mv symlink handle rollback.
        (self.bin / 'mv').unlink()
        (self.bin / 'mv').symlink_to(busybox)
        self.assert_clean(self.run_script(shell=[busybox, 'ash']), True)

    def test_model_interruption_then_retry(self):
        self.seed_old()
        (self.root / 'wanxiang-lts-zh-hans.gram').write_bytes(b'OLD_MODEL')
        names = ('melt_eng.schema.yaml', 'wanxiang-lts-zh-hans.gram')
        before = self.snapshot(names)
        self.assert_clean(self.run_script('update_patch.sh', {'MOCK_FAIL_AT': 'model'}), False)
        self.assertEqual(self.snapshot(names), before)
        self.assert_clean(self.run_script('update_patch.sh'), True)
        self.assertEqual((self.root / names[1]).read_bytes(), MODEL)

    def test_patch_metadata_and_schema_failures_preserve_old_files(self):
        self.seed_old()
        names = ('melt_eng.schema.yaml', 'wanxiang-lts-zh-hans.gram')
        before = self.snapshot(names)
        for stage in ('schema', 'metadata'):
            for mode in ('MOCK_FAIL_AT', 'MOCK_BAD_AT'):
                with self.subTest(stage=stage, mode=mode):
                    self.assert_clean(self.run_script('update_patch.sh', {mode: stage}), False)
                    self.assertEqual(self.snapshot(names), before)

    def test_corrupt_existing_model_is_repaired_and_valid_model_skipped(self):
        (self.root / 'wanxiang-lts-zh-hans.gram').write_bytes(b'PARTIAL_DOWNLOAD')
        self.assert_clean(self.run_script('update_patch.sh'), True)
        self.assertEqual((self.root / 'wanxiang-lts-zh-hans.gram').read_bytes(), MODEL)
        (self.root / 'calls').write_text('')
        self.assert_clean(self.run_script('update_patch.sh'), True)
        self.assertNotIn('model', (self.root / 'calls').read_text().splitlines())

    def test_bad_model_hash_and_missing_digest_preserve_old_files(self):
        self.seed_old()
        names = ('melt_eng.schema.yaml', 'wanxiang-lts-zh-hans.gram')
        before = self.snapshot(names)
        for options in ({'MOCK_CORRUPT_MODEL': '1'}, {'MOCK_NO_DIGEST': '1'}):
            with self.subTest(options=options):
                self.assert_clean(self.run_script('update_patch.sh', options), False)
                self.assertEqual(self.snapshot(names), before)

    def test_model_replacement_failure_rolls_back_schema(self):
        self.seed_old()
        names = ('melt_eng.schema.yaml', 'wanxiang-lts-zh-hans.gram')
        before = self.snapshot(names)
        self.assert_clean(self.run_script('update_patch.sh', {'MOCK_MV_FAIL_TARGET': names[1]}), False)
        self.assertEqual(self.snapshot(names), before)


if __name__ == '__main__':
    unittest.main()
