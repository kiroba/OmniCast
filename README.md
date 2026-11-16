# OmniCast

OmniCast for The Omniverse. Split out of [kiroba/The-Omniverse](https://github.com/kiroba/The-Omniverse) with its git history (Oct 30 2026).

## Calls
1:1 video calls connect through your own Omni Node (loopback, token from Omni Node > Connect apps).
The node hands out call settings (`/api/signal/ice-config`): direct first (LAN, IPv6, hole
punching), then a relay on another Omni node (desktops by default, phones only when their owner
opts in on Wi-Fi + charging). No Google, Cloudflare or other hosted STUN/TURN. When connected, the
call shows which path worked: **direct**, **direct (through the router)** or **relayed through an
Omni node**. Classroom Mode is unchanged.

**Status:** pre-alpha. 1:1 calls between real phones on different networks are still
untested — the first real two-person trial is the rescheduled friend test on
Nov 18/19, 2026 (calls run through the daemon's signed signaling mailbox on
`:5000`, direct-first media, another Omni node as relay fallback, no hosted
STUN/TURN). Two people behind carrier NAT with no reachable Omni node may not
connect yet.

## Build
```
flutter pub get
flutter build apk --release --target-platform android-arm64
```
Shared code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI), pinned by tag in `pubspec.yaml`. Android package: `com.omniverse.omnicast`.

CI here makes test builds (debug key). Signed releases still come from the monorepo's `release.yml` until release orchestration moves.

`design/` holds NotebookLM design screens (UI only, not wired yet).
`tool/build_multi_app_suite.py` is the old generator, kept for reference.
