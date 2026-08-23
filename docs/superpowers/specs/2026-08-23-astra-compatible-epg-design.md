# Astra-Compatible DVB EPG Design

## Goal

Restore the legacy Astra `epg_export = "file:///...xml"` behavior in Stream Lite so existing adapter JSON files collect DVB EIT schedules and continuously publish valid XMLTV files without requiring manual edits to every channel.

## Current Failure

The production host has 54 legacy `epg_export` values across 15 active adapter configurations and no `epg` objects in the new Stream schema. Stream preserves the legacy field in SQLite but the UI reads only `config.epg`, so the EPG tab appears empty.

The current `scripts/epg.lua` exporter creates `<channel>` elements only. It does not consume MPEG-TS PID `0x12`, parse EIT sections, or emit `<programme>` elements. Enabling the existing exporter against `/opt/epg/*.xml` would therefore overwrite useful Astra-generated schedules with channel-only XML.

Production probing confirmed that the required source data is present. Stream outputs for `a5_60103` and `a9_62102` carry EIT present/following and schedule tables (`0x4E` and `0x50`) with event entries.

## Approaches Considered

### 1. Native Stream EIT collector (selected)

Add a focused MPEG-TS module that reassembles EIT sections from PID `0x12`, parses DVB events and descriptors, and reports normalized guide records to Lua. Extend the Stream EPG layer to preserve legacy destinations, merge events, and write XMLTV atomically.

This keeps one Stream binary per instance, consumes EIT from the existing in-process SPTS pipeline, and provides the closest behavioral match to Astra.

### 2. External Python collector

Run a separate process that reads every `/play/<id>` endpoint and writes XMLTV. This avoids a binary change but adds another supervisor, duplicates all selected streams over HTTP, and can silently lose collection when HTTP access policy changes. It also leaves the Stream UI and configuration model inconsistent.

### 3. Keep an Astra helper process

Feed Stream SPTS outputs into the old Astra `epg_export` module. This would preserve XML formatting but contradicts the single Stream runtime goal, retains a proprietary legacy dependency, and complicates service recovery.

## Architecture

### Native EIT module

Create a small stream module under `modules/epg/` with one responsibility: observe PID `0x12` packets and emit normalized EIT events through a Lua callback.

The module will:

- reassemble PSI sections and verify section bounds and CRC;
- accept actual-transport EIT present/following and schedule tables (`0x4E`, `0x50`-`0x5F`);
- filter by configured service ID when supplied;
- parse event ID, start time, duration, running status, language, title, subtitle, description, and content category;
- decode DVB text through existing charset helpers;
- deduplicate sections by table, service, version, section number, and CRC;
- attach to the already active stream pipeline without opening another DVB frontend or HTTP client.

Malformed sections are discarded and rate-limited in logs. They must not remove previously valid events.

### Lua EPG registry and XMLTV writer

Replace the channel-only behavior in `scripts/epg.lua` with an in-memory registry keyed by destination, channel ID, and event identity.

For each configured stream:

- `epg_export = "file:///opt/epg/name.xml"` is treated as an Astra-compatible destination;
- channel ID defaults to the stream ID, matching the existing Astra XML files;
- an explicit modern `epg.xmltv_id` overrides the default;
- an explicit modern `epg.destination` overrides the legacy destination;
- disabled streams do not start collectors;
- the collector stays active independently of HTTP viewers.

Writes are debounced after EIT updates. Output is written to a sibling temporary file, flushed, closed, validated for at least one channel and one programme, and atomically renamed. An empty or invalid new guide never replaces the last valid XML.

Expired events are pruned while future schedule entries are retained. Restarting an instance may temporarily preserve the previous valid XML until enough EIT sections are collected to produce a replacement.

### Runtime integration

The stream lifecycle creates one EPG collector per configured output stream after the final SPTS channel stage. Reload, disable, delete, or stream replacement closes the old collector before a new one is attached.

The runtime will expose a compact status object for diagnostics:

- collector state;
- last EIT receive time;
- last successful write time;
- channel and programme counts;
- destination;
- last error.

### Configuration and UI compatibility

The API representation will synthesize a modern `epg` view from legacy `epg_export` without deleting or rewriting the legacy field. The EPG tab will show:

- XMLTV channel ID, defaulting to the stream ID;
- the resolved destination path;
- format and codepage;
- read-only collection status and programme count.

Saving an unchanged legacy stream preserves its `file:///` destination. The migration is compatibility-first and does not require editing the 54 production channel records.

## XMLTV Semantics

Generated XML uses UTF-8 and the existing Astra-compatible channel identifiers. Each programme includes `channel`, `start`, and `stop`. Available DVB descriptors add `title`, `sub-title`, `desc`, and `category` elements with language attributes.

Time conversion uses DVB MJD plus BCD UTC fields. XMLTV timestamps are rendered through the server's local timezone with the event-specific numeric offset, matching the existing Astra files and preserving daylight-saving changes. Invalid BCD values and impossible durations are rejected.

## Testing

Development follows red-green TDD.

Automated tests will cover:

- legacy `epg_export` normalization and UI/API visibility;
- EIT section reassembly across TS packets;
- present/following and schedule table parsing;
- MJD/BCD time conversion;
- short-event and extended-event descriptors;
- deduplication and version replacement;
- expired-event pruning;
- atomic XMLTV write with programme validation;
- fail-closed preservation of an existing XML when the new guide is empty or malformed;
- collector lifecycle during reload, disable, and delete.

The synthetic EIT fixture will be small and deterministic. Production verification additionally uses live PID `0x12` data.

## Canary and Rollout

Backups will be stored in `/root/back/stream-epg-astra-compat-20260823/` and include the current Stream binary, affected run files, adapter JSON files, Stream SQLite files, and the existing `/opt/epg` tree.

The new binary is first installed as `/usr/local/bin/stream-epg-canary`. Only `/etc/sv/adapter5/run` is changed and adapter5 is restarted. All other adapters continue using their current open binary inode.

Canary acceptance requires:

- adapter5 streams remain online with no new CC/PES degradation;
- `/opt/epg/Delfi.xml`, `/opt/epg/lnk.xml`, and other configured files receive fresh mtimes;
- XML parses successfully and contains future `<programme>` entries;
- channel IDs match the configured stream IDs;
- files continue updating after EIT version changes;
- real playback still decodes through FFmpeg.

After canary acceptance, the binary is promoted to `/usr/local/bin/stream` and adapters `0,1,2,3,4,5,6,8,9,10,11,13,14,15,17` are restarted sequentially with a health check after each restart. `aggregation` is excluded.

## Rollback

If the canary fails, restore `/etc/sv/adapter5/run`, restart adapter5 with the original Stream binary, and leave the previous XML files intact. No other adapter is restarted.

If a later rolling restart fails, stop the rollout, restore the backed-up `/usr/local/bin/stream` and affected run/config files, and restart only the adapters already updated. Saved Astra XML files remain available throughout rollback.

## Success Criteria

The change is complete only when the legacy fields are visible in Stream, future DVB schedule events are written as valid XMLTV, empty collections cannot destroy a good guide, all targeted streams remain decodable, and `aggregation` remains untouched.
