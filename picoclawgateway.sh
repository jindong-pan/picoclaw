#!/usr/bin/bash
#export PICOCLAW_BUILTIN_SKILLS=/home/rose_oasis_tw/picoclaw/workspace/skills
cd ~/picoclaw && ./picoclaw gateway 2>&1 | tee ~/.picoclaw/picoclaw.log
