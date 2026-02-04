# Clean-Room Skeleton Interfaces

These stubs are reference-only interfaces for a clean-room implementation.
They are not compiled or used by the current build. The intent is to provide
minimal Lua and C shapes for modules observed in the `astra-250612` binary.

Included modules:
- http_server
- srt_input
- mux

Notes:
- Keep these files separate from production sources.
- Treat these as scaffolding for a new implementation.
