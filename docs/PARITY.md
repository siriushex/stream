# Astral Parity Matrix

Last updated: 2026-02-05

Legend: DONE, PARTIAL, TODO

## Core UI + Navigation
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Dashboard tiles/table/compact views | DONE | DONE | N/A | DONE | manual | |
| Streams editor (tabs + basic fields) | DONE | DONE | DONE | DONE | manual | |
| Adapter editor shell | PARTIAL | DONE | DONE | PARTIAL | N/A | Detected DVB list + BUSY labels + scan flow; DVB hardware not tested on server |
| Sessions view | DONE | DONE | DONE | DONE | manual | |
| Access log view | DONE | DONE | DONE | DONE | manual | |
| Logs view | DONE | DONE | DONE | DONE | manual | |
| Settings shell + sections | DONE | DONE | DONE | DONE | manual | |

## General Settings
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Feature toggles (HLSSplitter/Buffer visibility) | DONE | DONE | N/A | N/A | manual | |
| EPG export interval | DONE | DONE | DONE | DONE | manual | |
| Event webhook URL (event_request) | DONE | DONE | DONE | DONE | manual | |
| Analyze concurrency limit | DONE | DONE | DONE | DONE | manual | |
| Log retention/max entries | DONE | DONE | DONE | DONE | manual | |
| Access log retention/max entries | DONE | DONE | DONE | DONE | manual | |
| Auth session TTL + CSRF + login rate limits | DONE | DONE | DONE | DONE | manual | |
| Stream defaults (timeouts/backup/keep-active) | DONE | DONE | DONE | DONE | manual | |
| Groups settings (playlist categories) | DONE | DONE | DONE | DONE | manual | |
| Servers settings | DONE | DONE | DONE | DONE | manual | |
| Telegram alerts | DONE | DONE | DONE | DONE | unit | |

## HLS Segmenter Settings
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Duration/quantity/naming/resource path/headers/TS extension/mime | DONE | DONE | DONE | DONE | manual | |

## HTTP Play Settings
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Allow HTTP/HLS, custom port, playlist name/arrange/logos/screens | DONE | DONE | DONE | DONE | manual | |
| M3U header and XSPF title | DONE | DONE | DONE | DONE | manual | |

## Streams / Inputs / Outputs
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Inputs list + inline editor | DONE | DONE | DONE | DONE | manual | |
| Output list inline editor | DONE | DONE | DONE | DONE | manual | |
| Stream rename + adapter rename | DONE | DONE | DONE | DONE | manual | |
| Allow stream without outputs | DONE | DONE | DONE | DONE | manual | Doc parity confirmed |
| Backup mode default = passive | DONE | DONE | DONE | DONE | manual | Deviates from Cesbo docs (default active) |
| Service/Remap/EPG tabs (basic) | DONE | DONE | DONE | DONE | manual | |
| MPTS config runtime apply (best-effort) | DONE | DONE | DONE | DONE | manual | Maps codepage/provider/tsid/pass_sdt/eit; other fields ignored |
| Advanced input options parity | DONE | DONE | DONE | DONE | manual | |
| Output modal parity (HLS/SRT/SCTP/NP/BISS) | DONE | DONE | DONE | DONE | manual | |
| Stream groups tab | DONE | DONE | DONE | DONE | manual | |
| Analyze details (PSI/PID/codec) | DONE | DONE | DONE | DONE | manual | On-demand analyze API + UI modal |

## Users / Auth
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Users list + create/update/reset | DONE | DONE | DONE | DONE | manual | |
| Password policy UI | DONE | DONE | DONE | DONE | manual | |
| HTTP auth settings UI | DONE | DONE | DONE | DONE | manual | |

## Softcam / CAS / License
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Softcam settings (list + apply) | DONE | DONE | DONE | DONE | manual | |
| CAS settings | DONE | DONE | DONE | DONE | manual | Default CAS passthrough applied via settings. |
| License view | DONE | DONE | DONE | DONE | manual | Read-only license via `/api/v1/license` (COPYING). |

## Monitoring / Integrations
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Alerts list API + UI | DONE | DONE | DONE | DONE | manual | |
| Webhook events (event_request) | DONE | DONE | DONE | DONE | manual | |
| InfluxDB export | DONE | DONE | DONE | DONE | manual | |
| Telegram alerts | DONE | DONE | DONE | DONE | unit | |
| Grafana/Zabbix | TODO | TODO | TODO | TODO | N/A | |

## Buffer / HLSSplitter
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Buffer UI + API | DONE | DONE | DONE | DONE | manual | |
| HLSSplitter UI + API | DONE | DONE | DONE | DONE | manual | |
| Visibility toggles in General | DONE | DONE | N/A | N/A | manual | |

## Config Safety
| Feature | Status | UI | API | Runtime | Tests | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Validate/reload/config history | DONE | DONE | DONE | DONE | manual | |
| Import/export | DONE | DONE | DONE | DONE | manual | |

## Deviations vs Cesbo Docs
- Backup mode default is PASSIVE in Astral (Cesbo doc default is active backup). This is a deliberate safety choice.
- DVB features are present in code, but are not tested on the target server (no DVB hardware).
