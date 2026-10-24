"""Entry point launched by Windows, independent of the Codex command job."""
from pathlib import Path
import runpy
import sys

workspace = Path(__file__).resolve().parents[1]
logs = workspace / 'runtime' / 'server' / 'logs'
logs.mkdir(parents=True, exist_ok=True)
sys.stdout = (logs / 'supervisor-console.log').open('a', encoding='utf-8', buffering=1)
sys.stderr = (logs / 'supervisor-errors.log').open('a', encoding='utf-8', buffering=1)
target = workspace / 'scripts' / 'public_server.py'
sys.argv = [str(target), 'run']
runpy.run_path(str(target), run_name='__main__')
