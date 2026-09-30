# Changelog - CK Dynamic Skybox

## [0.5.2-port039] - 2026-10-01

### Changed
- The mod no longer forces the exposure. The -1.2 EV offset and the low sun boost matched the author's 0.38 screenshots but blew the sky out to white in normal driving. Exposure is left to the game's auto exposure and the player's EV setting; only the relative offset from a preset's `brightness` is kept.

### Removed
- Low sun exposure boost and the `shirakaba` exclusion (no longer needed).

## [0.5.1-port039] - 2026-09-30

### Added
- **Freeze time toggle**: "Freeze time (preset time of day)" checkbox in the "Current Info" tab; `util_cktodbox.setFreezeTime(bool)` / `getFreezeTime()`. Enabled by default (time locked to `overrideTod`, matching the static cubemap); disabled lets the time of day be changed freely.
- **Low sun exposure boost**: `lowSunBoostEV = 0.75` for sun elevations <= 15 degrees, smoothstep fade-in below 30 degrees and fade-out to night between 3 and -2 degrees. Daytime exposure unchanged.
- **Stylised preset exclusion**: `lowSunExcluded` exempts `shirakaba` from the boost.

### Fixed / Compatibility
- BeamNG 0.39.4 physically based sky and environment APIs.
- Removed development calibration hooks (`setCalibration`).
- Kept the preset format version at `0.5`: bumping it to `0.5.1` made every preset fail the version check and the preset list came up empty. The port version is shown in the window title only.

### Calibration (vs. 0.38 author screenshots)
- Johnson Valley, Partly Cloudy 1 (day): 91.4-91.6 % (threshold 90 %).
- West Coast USA sunset (shot 6): 85.2 % frame / 91.7 % sky at 15 degrees.
- Utah sunset (shot 7): ~74 % frame, target not reached. The author's 0.38 references are inconsistent: shot 6 and shot 7 use the same preset (`daysky008b`) and a similar sun elevation, but their sky brightness differs (L 95.8 vs 69.2, different manual EV). One global exposure curve cannot match both; it is calibrated for shot 6. Darkening for Utah would gain < 3 % on the frame and push shot 6 below target.
