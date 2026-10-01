"""Check deployment using only versioned files, without any private/local data."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
with tempfile.TemporaryDirectory(prefix='rime-clean-deployment-') as directory:
    clean = Path(directory)
    for name in filter(None, files):
        source = ROOT / name
        if source.is_file():
            target = clean / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def check_opencc(node):
        if isinstance(node, dict):
            if node.get('type') == 'text' and 'file' in node:
                assert (clean / 'opencc' / node['file']).is_file(), f"Missing OpenCC data: {node['file']}"
            for value in node.values():
                check_opencc(value)
        elif isinstance(node, list):
            for value in node:
                check_opencc(value)

    for config in (clean / 'opencc').glob('*.json'):
        check_opencc(json.loads(config.read_text()))
    result = subprocess.run(
        ['rime_deployer', '--build', str(clean), str(clean), str(clean / 'build')],
        capture_output=True, text=True, timeout=240,
    )
    if result.returncode:
        print(result.stdout + result.stderr)
        raise SystemExit(result.returncode)
    for schema in ('rime_mint', 'double_pinyin'):
        assert (clean / 'build' / f'{schema}.schema.yaml').is_file(), f'Missing compiled schema: {schema}'
    assert (clean / 'build' / 'rime_mint.table.bin').is_file(), 'Missing compiled main dictionary'
    print('Clean deployment and OpenCC dependency checks passed')
