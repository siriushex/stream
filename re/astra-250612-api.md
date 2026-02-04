# Astra 250612 HTTP API Spec (Static + Dynamic)

## Sources and Scope
- Static source of truth for routes/validation: `astra/scripts/api.lua`.
- Dynamic observation: run on server using `./astra` (source build, v4.4.187)
  because `astra-250612` aborts at startup with `sqlite` missing
  (`scripts/config.lua:346: attempt to index global 'sqlite'`).
- Endpoints and schemas below are derived from code; observed response keys are
  recorded where runtime responses were available.

## Auth and CSRF
- `POST /api/v1/auth/login` returns `{token, user}` and sets cookie
  `astra_session=<token>; Path=/; HttpOnly`.
- `Authorization: Bearer <token>` is accepted for all authenticated routes.
- If using cookie-based auth, state-changing requests require
  `x-csrf-token` header equal to the session token.
- Error payload is always JSON: `{ "error": "message" }`.

## Endpoint Index (Full List)
### Auth
- `POST /api/v1/auth/login`
  - Body: `{ username, password }`
  - Response: `{ token, user: { id, username, is_admin } }`
- `POST /api/v1/auth/logout`
  - Auth: required
  - Response: `{ status: "ok" }` (cookie cleared)

### Streams
- `GET /api/v1/streams`
  - Auth: required
  - Response: list of `{ id, enabled, config }`
- `POST /api/v1/streams`
  - Auth: required
  - Body: `{ id, enabled?, config? }` (if `config` missing, body is used)
  - Response: `{ status: "ok" }`
- `GET /api/v1/streams/<id>`
  - Auth: required
  - Response: `{ id, enabled, config }`
- `PUT /api/v1/streams/<id>`
  - Auth: required
  - Body: stream config (same shape as POST)
  - Response: `{ status: "ok" }`
- `DELETE /api/v1/streams/<id>`
  - Auth: required
  - Response: `{ status: "ok" }`

### Adapters (Do not exercise on server: no DVB)
- `GET /api/v1/adapters`
- `POST /api/v1/adapters`
  - Body: `{ id, enabled?, config? }`
- `GET /api/v1/adapters/<id>`
- `PUT /api/v1/adapters/<id>`
- `DELETE /api/v1/adapters/<id>`
- `GET /api/v1/adapter-status`
- `GET /api/v1/adapter-status/<id>`

### Splitters
- `GET /api/v1/splitters`
- `POST /api/v1/splitters`
  - Body: `{ id?, name, enable, port, in_interface?, out_interface?, logtype?, logpath?, config_path? }`
- `GET /api/v1/splitters/<id>`
- `PUT /api/v1/splitters/<id>`
- `DELETE /api/v1/splitters/<id>`
- `GET /api/v1/splitters/<id>/links`
- `POST /api/v1/splitters/<id>/links`
  - Body: `{ id?, enable, url, bandwidth, buffering }` (HTTP-only URL)
- `PUT /api/v1/splitters/<id>/links/<link_id>`
- `DELETE /api/v1/splitters/<id>/links/<link_id>`
- `GET /api/v1/splitters/<id>/allow`
- `POST /api/v1/splitters/<id>/allow`
  - Body: `{ id?, kind: "allow"|"allowRange", value }`
- `DELETE /api/v1/splitters/<id>/allow/<rule_id>`
- `POST /api/v1/splitters/<id>/start`
- `POST /api/v1/splitters/<id>/stop`
- `POST /api/v1/splitters/<id>/restart`
- `POST /api/v1/splitters/<id>/apply-config`
- `GET /api/v1/splitters/<id>/config` (XML)
- `GET /api/v1/splitter-status`
- `GET /api/v1/splitter-status/<id>`

### Buffer (HTTP TS Buffer)
- `GET /api/v1/buffers/resources`
- `POST /api/v1/buffers/resources`
  - Body: `{ id?, name, path, enable, buffering_sec, bandwidth_kbps, ... }`
  - Notes: `path` required, normalized to `/...`; must be unique.
- `GET /api/v1/buffers/resources/<id>`
- `PUT /api/v1/buffers/resources/<id>`
- `DELETE /api/v1/buffers/resources/<id>`
- `GET /api/v1/buffers/resources/<id>/inputs`
- `POST /api/v1/buffers/resources/<id>/inputs`
  - Body: `{ id?, enable, url, priority }` (HTTP-only URL)
- `PUT /api/v1/buffers/resources/<id>/inputs/<input_id>`
- `DELETE /api/v1/buffers/resources/<id>/inputs/<input_id>`
- `GET /api/v1/buffers/allow`
- `POST /api/v1/buffers/allow`
  - Body: `{ id?, kind: "allow"|"allowRange", value }`
- `DELETE /api/v1/buffers/allow/<rule_id>`
- `POST /api/v1/buffers/reload`
- `POST /api/v1/buffers/<id>/restart-reader`
- `GET /api/v1/buffer-status`
- `GET /api/v1/buffer-status/<id>`

### Sessions and Logs
- `GET /api/v1/sessions`
  - Query: `type=auth`, `stream_id`, `login`, `ip`, `text`, `limit`, `offset`
- `DELETE /api/v1/sessions/<id>`
- `GET /api/v1/logs`
  - Query: `since`, `limit`, `level`, `text`, `stream_id`
- `GET /api/v1/access-log`
  - Query: `since`, `limit`, `event`, `stream_id`, `ip`, `login`, `text`

### Users (Admin)
- `GET /api/v1/users`
- `POST /api/v1/users`
  - Body: `{ username, password, is_admin?, enabled?, comment? }`
- `PUT /api/v1/users/<username>`
  - Body: `{ is_admin?, enabled?, comment? }`
- `POST /api/v1/users/<username>/reset`
  - Body: `{ password }`

### Auth Debug
- `GET /api/v1/auth-debug/session`
  - Query: `stream_id`, `ip?`, `proto?`, `token?`

### Metrics and Health
- `GET /api/v1/metrics`
- `GET /api/v1/metrics?format=prometheus`
- `GET /api/v1/health/process`
- `GET /api/v1/health/inputs`
- `GET /api/v1/health/outputs`

### Alerts, Audit, Transcode, Settings
- `GET /api/v1/alerts` (query: `since`, `limit`, `stream_id`, `code`, `type=auth`)
- `GET /api/v1/audit` (query: `since`, `limit`, `action`, `actor`, `target`, `ip`, `ok`)
- `GET /api/v1/transcode-status`
- `GET /api/v1/transcode-status/<id>`
- `POST /api/v1/transcode/<id>/restart`
- `GET /api/v1/settings` (returns key/value map)
- `PUT /api/v1/settings` (body: key/value map)
- `POST /api/v1/import` (body: `{ mode?, config? }`)
- `GET /api/v1/export`
  - Query: `include_users`, `include_settings`, `include_streams`,
    `include_adapters`, `include_softcam`, `include_splitters`, `download`
- `POST /api/v1/restart` (triggers process restart)

## Observed Response Keys (Server Build)
Observed on `/home/hex/astra` using `./astra scripts/server.lua -p 9131`.

- `GET /api/v1/health/process`: `started_at`, `status`, `ts`, `uptime_sec`, `version`
- `GET /api/v1/health/inputs`: `inputs`, `streams`, `ts`, `unhealthy_streams`
- `GET /api/v1/health/outputs`: `streams`, `ts`, `unhealthy_streams`
- `GET /api/v1/metrics`: `adapters`, `lua_mem_kb`, `perf`, `sessions`, `streams`, `ts`, `uptime_sec`, `version`
- `GET /api/v1/metrics?format=prometheus`: plain text metrics
- `GET /api/v1/settings`: key/value map (sample keys: `hls_base_url`, `hls_dir`, `http_port`)
- `GET /api/v1/streams`: list items with `id`, `enabled`, `config`
- `GET /api/v1/streams/<id>`: `id`, `enabled`, `config`
- `GET /api/v1/stream-status`: list (empty when no running streams)
- `GET /api/v1/stream-status/<id>`: `error` when stream not running
- `GET /api/v1/sessions`: list (empty without activity)
- `GET /api/v1/logs`: `entries`, `next_id`
- `GET /api/v1/access-log`: `entries`, `next_id`
- `GET /api/v1/alerts`: list (empty by default)
- `GET /api/v1/audit`: list with `action`, `actor_user_id`, `actor_username`, `id`, `ip`, `message`, `meta_json`, `ok`, `target_username`, `ts`
- `GET /api/v1/transcode-status`: list (empty by default)
- `GET /api/v1/export?include_users=0`: `dvb_tune`, `make_stream`, `settings`, `splitters`
