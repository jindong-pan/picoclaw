---
name: lessons
description: Record lessons from failures and past experience. Use propose_change to append to LESSONS.md when a task fails, an approach wastes tokens, or a better method is found. Read LESSONS.md before attempting tasks that have failed before.
---
# Lessons

Read LESSONS.md before attempting queries similar to past failures:
```
read_file: ~/.picoclaw/workspace/LESSONS.md
```

When a task fails or a better approach is discovered, record it:
```
propose_change:
  file: "LESSONS.md"
  mode: append
  content: "- [topic]: what failed and what to do instead"
  reason: brief summary
```
