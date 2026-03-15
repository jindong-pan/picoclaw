#!/bin/bash
imax=${1:-12}
python3 -c "
import json
with open('/home/rose_oasis_tw/.picoclaw/config.json') as f:
    cfg = json.load(f)
cfg['agents']['defaults']['max_tool_iterations'] = ${imax}
with open('/home/rose_oasis_tw/.picoclaw/config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
print('Set max_tool_iterations=${imax}')
"
