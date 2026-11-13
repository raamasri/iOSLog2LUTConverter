# iOS LOG to LUT Converter

A native SwiftUI app for grading videos with a primary conversion LUT, an optional creative LUT, and white balance controls. Runs on iPhone and iPad with iOS 18.5 or later.

## Supported workflow

1. Import a video from Photos or Files. Enable Batch mode to build a queue.
2. Choose a bundled LUT or import a `.cube` file. Either LUT slot can be set to None; white balance and export also work without a LUT.
3. Adjust each LUT's opacity and white balance. Scrub the timeline to inspect the same frame before and after grading.
4. Export to MP4, then share the result or save it to Photos. Batch export reports completed and failed items and can be cancelled.
5. Save a project to retain its settings, full batch queue, and copies of its video/LUT assets.

Photos and Files imports are copied into app-owned storage. Saving a project creates its own copies, so large projects require additional free space. Project files reference those copies using relative filenames, allowing them to survive changes to the app's storage path. Older projects that only reference an unavailable external or temporary video must have that video imported again.

## Color and export behavior

- Supports 1D and 3D `.cube` files, including input-domain metadata. Invalid sizes, incomplete rows, nonfinite values, and unsupported formats are rejected.
- The grade order is primary LUT, white balance, then creative LUT. Opacity blends each LUT result with that stage's input.
- Preview and export use explicit Core Image context settings so implicit linear color-space conversion does not change signal-encoded LUT indexing.
- **Low, Medium, and High export 8-bit SDR H.264. Maximum exports 10-bit SDR HEVC Main 10.** Maximum decodes, grades, and renders through half-float RGB without an 8-bit intermediate. An 8-bit input does not acquire new source detail from a 10-bit output.
- Audio is encoded to stereo AAC at 48 kHz. Source HDR metadata is not retained, and arbitrary PQ/HLG footage is not automatically tone mapped. Choose a conversion LUT matching the footage's log/gamut encoding when converting camera log to Rec.709.
- Long 1D curves are resampled to a 64³ color cube for Core Image processing. 3D cubes retain their supplied grid, up to the supported 128³ limit.
- Low and Medium cap the long/short edges at 1280×720 and 1920×1080, respectively, including portrait footage. Smaller footage is not enlarged. High and Maximum retain the original displayed resolution, rounded to even dimensions for the encoder.
- Maximum uses higher-bitrate HEVC Main 10; it is compressed, not lossless or uncompressed. Encoding may take longer in the Simulator than on supported physical hardware.
- Export honors portrait/rotation transforms. Each run creates unique output files, and cancelled or failed exports remove partial files.

Apple's decoder is preferred. A bundled, local software decoder handles H.264 profiles that iOS rejects, including the supplied Sony 10-bit 4:2:2 original in MOV/MP4. Other video codecs depend on AVFoundation support on the device. Unsupported or corrupt media reports an error and does not create a successful export.

`.3dl` and arbitrary `.lut` files are not supported. Exports retain the source's rational frame timestamps, including 29.97 fps. Export temporarily disables foreground auto-lock and requests finite iOS background time; if the system's background allowance expires, it cancels cleanly. This does not grant unlimited background execution.

## Build and test

Open `iOSLOG2LUTConverter.xcodeproj` in Xcode and select the `iOSLOG2LUTConverter` scheme. Use an installed iOS Simulator or a provisioned physical device.

List available simulators:

```sh
xcrun simctl list devices available
```

Replace `SIMULATOR_ID` with an available device ID:

```sh
xcodebuild -project iOSLOG2LUTConverter.xcodeproj \
  -scheme iOSLOG2LUTConverter \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' build

xcodebuild -project iOSLOG2LUTConverter.xcodeproj \
  -scheme iOSLOG2LUTConverter \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -parallel-testing-enabled NO test
```

The standard regression suite generates small H.264/AAC fixtures for audio, orientation, preview timing, cancellation, LUT math, durable projects, and queue integrity. Optional acceptance suites use the supplied 4K Sony original, all eight existing conversions, and the four supplied LUTs. They process complete videos, decode the exports, check frame/audio counts and timing, and compare frame results with independent FFmpeg references. A generated 877-level grayscale ramp checks that Maximum retains actual 10-bit detail rather than only a format flag.

Real-media UI tests select files through native Photos and Files, adjust both LUT stages and white balance, scrub and compare frames, export, save to Photos, open sharing, save/reopen/search/favorite/delete projects, apply a template, and cancel/retry processing. These require fixture staging and an English-language test Simulator.

After installing the app in a booted Simulator, stage the user's unchanged files:

```sh
python3 scripts/validation/stage_simulator_fixtures.py \
  '/path/to/lutconvertertest' SIMULATOR_ID --photos
python3 scripts/validation/generate_precision_fixture.py --help
```

For the complete reproducible setup and run, use:

```sh
bash scripts/validation/run_acceptance.sh '/path/to/lutconvertertest' SIMULATOR_ID --ui
```

This installs the test build, stages unchanged media, generates/stages the precision ramp, and saves its `.xcresult` and logs under `build/validation/acceptance`. Omit `--ui` for service/processing tests only. It preserves Simulator data; Photos seeding can add another copy of the two test assets on repeated UI runs.

For manual setup, stage the generated ramp in the test app's `Documents/PrecisionFixtures` directory. `RealMediaProcessingTests`, `RealProjectAcceptanceTests`, and `SoftwareDecoderAcceptanceTests` skip ordinary runs when their fixture directory is absent; a staged directory missing required files is a failure. Their results remain in `Documents/RealMediaResults` and `Documents/PrecisionResults` for inspection. Native UI tests require the staged media and do not substitute a different source when a requested original fails.

Independent numerical checks are reproducible with `scripts/validation/validate_media.py` and `compare_app.py`; use `--help` for their input/output arguments. These optional engineering tools require FFmpeg/ffprobe and Python with NumPy and Pillow. They do not run inside the app or upload media.

Simulator acceptance does not establish physical-device performance. The supplied camera Log conversion is checked numerically against its matching LUT/reference; other camera encodings require matching conversion LUTs and their own reference footage.

## Source layout

- `Models/ProjectState.swift`: grade settings, preview lifecycle, timeline, and batch orchestration.
- `Services/LUTProcessor.swift`: `.cube` parsing, Core Image grading, preview decoding, and audio/video export.
- `Services/SoftwareDecoder/`: native software H.264 fallback, including BGRA8 and half-float output.
- `Services/VideoProcessor.swift`: export configuration, progress, cancellation, and output management.
- `Services/FileImportManager.swift`: durable local/Photos imports and supported file types.
- `Services/LUTManager.swift`: bundled/custom LUT discovery and selection.
- `Services/ProjectManager.swift`: project assets, templates, recent projects, and favorites.
- `Views/`: adaptive interface, before/after preview, LUT selectors, and project management.

The app uses SwiftUI, Combine, AVFoundation, Core Image, and PhotosUI. Project metadata is stored as JSON and UserDefaults; it does not use Core Data.


## Bundled decoder and production packaging

`Vendor/FFmpegMinimal/FFmpegMinimal.xcframework` includes arm64 iOS-device and arm64 Apple-silicon Simulator static libraries, so a normal Xcode build does not require downloading or compiling FFmpeg. Rebuild with `bash scripts/dependencies/build_ffmpeg_ios.sh` if needed. The script checks the vendored source archive's SHA-256 and uses the pinned source commit in `Vendor/FFmpegMinimal/build-manifest.json`.

The build enables local-file H.264 decoding only, with no networking, GPL, or nonfree components. The corresponding source, LGPL license, notices, and reproducible build script are supplied. See `Vendor/FFmpegMinimal/NOTICE.txt` for relinking/distribution requirements; license notices are also included in the app resources.

Release builds exclude the developer's large bundled test movies. The input fixtures and validation exports are engineering artifacts and are not shipped with the production app.
