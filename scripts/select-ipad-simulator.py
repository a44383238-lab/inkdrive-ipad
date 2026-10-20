import json
import subprocess
import sys

sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version'], text=True).strip()
runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-' + sdk.replace('.', '-')
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))['devices']
candidates = [device for device in devices.get(runtime, []) if 'iPad' in device['name'] and device.get('isAvailable', True)]
if not candidates:
    raise SystemExit('No iPad simulator matches the selected iOS SDK ' + sdk)
candidates.sort(key=lambda device: ('iPad Air 11-inch' not in device['name'], device['name']))
device = candidates[0]
print(f"Using {device['name']}, iOS {sdk}", file=sys.stderr)
print(device['udid'])
