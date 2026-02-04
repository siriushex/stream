# Roadmap

## 0-2 Weeks (Stabilization)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Docs + CI baseline | Single source of truth and automated checks | `docs/*` present, CI green on push | Low | docs/, .github/workflows |
| Settings UI parity audit | Remove placeholder UI or wire it to settings/runtime | Softcam/CAS/License reflect real behavior or hidden | Medium | web/, scripts/api.lua |
| Backup default deviation documented | Avoid surprise behavior | `docs/PARITY.md` lists deviation | Low | docs/ |
| Smoke coverage refresh | Ensure basic runtime checks remain reliable | `contrib/ci/smoke.sh` updated if needed | Low | contrib/ci |

## 1-2 Months (Productization)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Sessions/Logs UX polish | Faster ops visibility | UI filters + stable performance with large logs | Medium | web/, scripts/runtime.lua |
| HLS failover resilience | No broken segments during input switch | HLS smoke shows continuous playback | High | modules/hls, scripts/stream.lua |
| Config history UX | Safer reloads | Revision list with meaningful error text | Medium | scripts/api.lua, web/ |
| Monitoring exports | Operator integration | Prometheus/Influx or webhook parity documented | Medium | scripts/runtime.lua |

## 3-6 Months (Differentiators)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Advanced analytics | Better diagnostics | Alert enrichment, rate-limited notifications | Medium | scripts/runtime.lua |
| Extended output types | Broader compatibility | Clear validation, docs, smoke tests | High | scripts/stream.lua, web/ |
| Ops automation | Easier deploys | Installer scripts + systemd defaults | Medium | contrib/systemd |
