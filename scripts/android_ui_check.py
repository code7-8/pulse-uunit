"""Small driver for the project's Android emulator smoke checks."""
from pathlib import Path
import re
import subprocess
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / '.tools' / 'android-sdk' / 'platform-tools' / 'adb.exe'
OUTPUT = ROOT / 'runtime' / 'server' / 'tmp' / 'native-ui.xml'

def adb(*arguments):
    return subprocess.check_output([str(ADB), '-s', 'emulator-5554', *arguments], text=True, encoding='utf-8', errors='replace')

def snapshot():
    adb('shell', 'uiautomator', 'dump', '/sdcard/pulse-ui.xml')
    adb('pull', '/sdcard/pulse-ui.xml', str(OUTPUT))
    return list(ET.parse(OUTPUT).iter('node'))

def tap_text(text, contains=False):
    nodes = snapshot()
    for node in nodes:
        label = node.get('text') or node.get('content-desc') or ''
        if label == text or (contains and text in label):
            left, top, right, bottom = map(int, re.findall(r'\d+', node.get('bounds')))
            adb('shell','input','tap',str((left+right)//2),str((top+bottom)//2))
            return
    raise ValueError('Visible control not found: ' + text)

def show_labels():
    for node in snapshot():
        label = node.get('text') or node.get('content-desc')
        if label and node.get('password') != 'true':
            print(label, node.get('bounds'))

if __name__ == '__main__':
    show_labels()
