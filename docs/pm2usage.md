pm2 start ~/.picoclaw/pm2.config.js     # first time
pm2 restart picoclaw --env basic        # default
pm2 restart picoclaw --env browser      # browser tasks
pm2 restart picoclaw --env github       # github tasks
pm2 restart picoclaw --env summarize    # summarize tasks
pm2 save                                # persist across reboots
