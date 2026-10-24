"""Package only source/assets and scan the APKs/archive for API secrets."""
from pathlib import Path
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / 'artifacts'
excluded = {'.venv', '.tools', '.dart_tool', '.gradle', '.cxx', 'build', '__pycache__', 'runtime', 'data', '.pytest_cache', '.git'}
excluded_names = {'local.properties', 'key.properties', '.DS_Store'}
files = set()
for name in ('README.md', '.gitignore'):
    files.add(ROOT / name)
files.update(ROOT.glob('*.cmd'))
for name in ('backend', 'mobile/lib', 'mobile/test', 'mobile/assets', 'mobile/android', 'scripts', 'docs'):
    for path in (ROOT / name).rglob('*'):
        relative = path.relative_to(ROOT)
        if path.is_file() and not any(part in excluded for part in relative.parts) and path.name not in excluded_names and path.suffix not in ('.pyc', '.log', '.sqlite3', '.key', '.pem', '.apk'):
            if path.resolve().is_relative_to(ROOT.resolve()):
                files.add(path)
for name in ('pubspec.yaml','pubspec.lock','analysis_options.yaml','.metadata'):
    path = ROOT / 'mobile' / name
    if path.is_file(): files.add(path)
if len(files) > 1500 or sum(path.stat().st_size for path in files) > 100 * 1024 * 1024:
    raise ValueError('Unexpected source package size')
secret = (ROOT / 'runtime/server/openrouter.key').read_bytes().strip()
pattern = re.compile(rb'sk-or-v1-[a-fA-F0-9]{40,}')
def check(data, name):
    if secret in data or pattern.search(data):
        raise ValueError('API secret found in package member: ' + name)
destination = ARTIFACTS / 'pulse-source.zip'
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as output:
    for path in sorted(files):
        data = path.read_bytes()
        name = path.relative_to(ROOT).as_posix()
        check(data, name)
        output.writestr(name, data)
for name in ('pulse-online.apk','pulse-demo.apk'):
    with zipfile.ZipFile(ARTIFACTS / name) as apk:
        for member in apk.infolist():
            check(apk.read(member), name + ':' + member.filename)
print(json.dumps({'archive':str(destination),'source_files':len(files),'bytes':destination.stat().st_size,'secrets_scan':'passed'},ensure_ascii=False))
