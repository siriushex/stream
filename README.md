# Stream Hub

Stream Hub is a streaming server with a browser-based control panel. It
combines stream ingest, routing, delivery, monitoring, DVB workflows, DVR,
and optional SoftCAM support in one runtime.

This repository contains source code only: the C runtime and modules, Lua
services, web assets, tests, and build tooling. Do not commit deployed
configuration, recordings, runtime databases, access data, or locally built
binaries.

## Start here

- [Usage guide](docs/USAGE.md) — build, first start, UI workflow, validation,
  SoftCAM/Newcamd operations, maintenance, and troubleshooting.
- [Architecture](docs/ARCHITECTURE.md) — runtime boundaries and component map.
- [DevOps](docs/DEVOPS.md) — controlled build, deployment, and rollback flow.
- [Security review](docs/SECURITY_REVIEW.md) — security constraints and risk
  register.
- [Auth backend contract](contrib/auth-backends/contract.md) — Ministra/TMS
  integration contract and related QA material.

## Validation before publishing

```bash
scripts/ci/check_sensitive_data.sh --staged
contrib/ci/check_public_docs.sh
node --check web/app.js
```

The Help page in Stream Hub opens the same public usage guide hosted in this
repository.

License: see [COPYING](COPYING).
