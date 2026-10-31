# OmniCast

OmniCast for The Omniverse. Split out of [kiroba/The-Omniverse](https://github.com/kiroba/The-Omniverse) with its git history (Oct 30 2026).

## Build
```
flutter pub get
flutter build apk --release --target-platform android-arm64
```
Shared code comes from [Omni-Core-UI](https://github.com/kiroba/Omni-Core-UI), pinned by tag in `pubspec.yaml`. Android package: `com.omniverse.omnicast`.

CI here makes test builds (debug key). Signed releases still come from the monorepo's `release.yml` until release orchestration moves.

`design/` holds NotebookLM design screens (UI only, not wired yet).
`tool/build_multi_app_suite.py` is the old generator, kept for reference.
