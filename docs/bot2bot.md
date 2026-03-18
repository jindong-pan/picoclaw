The architecture is clear. The shared mux in `channels/manager.go` is where we add the `/spawn` endpoint. Here's the complete design:

**Server B** exposes `/api/spawn` on its existing HTTP server (same port as `/health`). **Server A** has a new `remote_spawn` tool that POSTs tasks to Server B's endpoint.

```
Server A                          Server B
POST /api/spawn                   ← new endpoint on existing mux
  {task, label, secret}           authenticates with shared secret
                                  → runs task via AgentLoop
                                  → returns {result}
```

Check the mux setup and what we need to add:

```bash
sed -n '277,315p' pkg/channels/manager.go
```

This will show exactly where to register the new `/api/spawn` handler. Then we need:

1. `pkg/channels/manager.go` — add `RegisterSpawnHandler(handler)` method
2. `pkg/tools/remote_spawn.go` — new tool that POSTs to remote server
3. `cmd/picoclaw/internal/gateway/helpers.go` — wire everything together
4. Config: `remote_agents` list with URL + secret per remote server

Before writing code — two questions:
- Should Server B only accept spawned tasks, or also accept direct user messages?
- Do you want Server A to wait for Server B's response (synchronous) or fire-and-forget (async)?
Good choices. Async with handshake means:

```
Server A                              Server B
POST /api/spawn                  ──►  validates secret
  {task, label, secret,               queues task
   callback_url, callback_secret}     returns 202 Accepted immediately
                                      runs task async
POST {callback_url}              ◄──  when done, POSTs result back
  {result, label, secret}             
Server A receives result,             
publishes to user via bus
```

The handshake is the `callback_url` + `callback_secret` — Server B proves identity when calling back.

**Four components to build:**

1. **`pkg/api/spawn_handler.go`** — Server B's `/api/spawn` endpoint
2. **`pkg/api/callback_handler.go`** — Server A's `/api/callback` endpoint  
3. **`pkg/tools/remote_spawn.go`** — Server A's tool that calls Server B
4. **Config** — `remote_agents` in `config.json`

Config design:
```json
"remote_agents": [
  {
    "id": "server-b",
    "name": "Overseas Specialist",
    "url": "https://serverb.example.com:18790",
    "secret": "shared-secret-key",
    "skills": ["translation", "local-data"]
  }
]
```

Before writing code, check if there's already any API package:

```bash
ls pkg/api/ 2>/dev/null || echo "no api package yet"
grep -rn "callback\|remote\|webhook" pkg/ --include="*.go" -l | head -10
```
