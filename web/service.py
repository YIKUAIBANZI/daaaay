#!/usr/bin/env python3
"""Explicit install/status/uninstall for the user-owned daily planner service."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys

LABEL = 'local.daaaay.dashboard'
BASE = Path(__file__).resolve().parent
PLIST = Path.home() / 'Library' / 'LaunchAgents' / f'{LABEL}.plist'
DOMAIN = f'gui/{os.getuid()}'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['install','status','uninstall'])
    args = parser.parse_args()
    if args.action == 'status':
        return subprocess.run(['/bin/launchctl','print',f'{DOMAIN}/{LABEL}']).returncode
    if args.action == 'install':
        if PLIST.exists():
            print('Service plist already exists; inspect it before changing anything.',file=sys.stderr)
            return 1
        PLIST.parent.mkdir(parents=True,exist_ok=True)
        config = {
            'Label':LABEL,
            'ProgramArguments':[sys.executable,str(BASE/'server.py')],
            'WorkingDirectory':str(BASE),
            'RunAtLoad':True,
            'KeepAlive':True,
            'ThrottleInterval':10,
        }
        with PLIST.open('xb') as f:
            plistlib.dump(config,f)
        result = subprocess.run(['/bin/launchctl','bootstrap',DOMAIN,str(PLIST)])
        if result.returncode:
            PLIST.unlink()
        return result.returncode
    if not PLIST.exists():
        print('Service is not installed.')
        return 0
    with PLIST.open('rb') as f:
        config = plistlib.load(f)
    if config.get('Label') != LABEL or str(BASE/'server.py') not in config.get('ProgramArguments',[]):
        raise RuntimeError('Refusing to remove an unrelated service')
    result = subprocess.run(['/bin/launchctl','bootout',DOMAIN,str(PLIST)])
    if result.returncode:
        print('Unload failed; plist retained for inspection.',file=sys.stderr)
        return result.returncode
    PLIST.unlink()
    print('Dashboard service removed.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
