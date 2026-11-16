#!/usr/bin/python3
"""Harmless CLI stand-ins: arguments travel separately from program stdout."""
import json
import os
import sys

record = {'command': os.path.basename(sys.argv[0]), 'args': sys.argv[1:]}
if 'COMMAND_CAPTURE_FD' in os.environ:
    os.write(int(os.environ['COMMAND_CAPTURE_FD']), (json.dumps(record) + '\n').encode())
print(json.dumps(record))
