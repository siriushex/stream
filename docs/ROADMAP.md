# Roadmap

## 0-2 Weeks (Stabilization)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Docs + CI baseline | Single source of truth and automated checks | `docs/*` present, CI green on push | Low | docs/, .github/workflows |
| Settings UI parity audit (DONE) | Remove placeholder UI or wire it to settings/runtime | Softcam wired; CAS/License hidden | Low | web/, scripts/api.lua |
| MPTS runtime apply (DONE) | Apply MPTS config to runtime where supported | MPTS config mapped to channel options with warnings for unsupported fields | Medium | scripts/stream.lua |
| Backup default deviation documented | Avoid surprise behavior | `docs/PARITY.md` lists deviation | Low | docs/ |
| Smoke coverage refresh (DONE) | Ensure basic runtime checks remain reliable | Added `smoke_mpts.sh` and CI job | Low | contrib/ci |

## 1-2 Months (Productization)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Sessions/Logs UX polish (PARTIAL) | Faster ops visibility | Added log pause/resume; more UX polish pending | Medium | web/ |
| HLS failover resilience | No broken segments during input switch | HLS smoke shows continuous playback | High | modules/hls, scripts/stream.lua |
| Config history UX (PARTIAL) | Safer reloads | Added error detail modal + copy; more sorting/paging TBD | Medium | scripts/api.lua, web/ |
| Monitoring exports | Operator integration | Prometheus/Influx or webhook parity documented | Medium | scripts/runtime.lua |

## 3-6 Months (Differentiators)
| Task | Goal | Acceptance Criteria | Risk | Code Areas |
| --- | --- | --- | --- | --- |
| Advanced analytics | Better diagnostics | Alert enrichment, rate-limited notifications | Medium | scripts/runtime.lua |
| Extended output types | Broader compatibility | Clear validation, docs, smoke tests | High | scripts/stream.lua, web/ |
| Ops automation | Easier deploys | Installer scripts + systemd defaults | Medium | contrib/systemd |
