# Decoder selection regression tests

Run `bash Tests/Regression/run.sh` after building the Xcode project with `bash scripts/build-release.sh`. An optional argument specifies another resolved `Sweep.swift` path. The runner builds the production parser, format selection and playback state, uses a temporary directory, and does not change audio devices or play music.

Covers stale logs, late preloads, ordering, delayed decoder lines, malformed formats, sample-rate-family fallback, physical format ranges, repeated metadata, stale position timestamps, seeks, pause/resume and other media applications. These tests do not verify real Music event timing or hardware switching. The transition window remains a heuristic because decoder logs have no reliable public track identifier.
