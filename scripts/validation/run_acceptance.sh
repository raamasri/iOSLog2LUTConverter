#!/bin/bash
# Run the real user-media acceptance suite on a booted iOS Simulator.
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: bash scripts/validation/run_acceptance.sh SOURCE_DIRECTORY SIMULATOR_ID [--ui]" >&2
    exit 2
fi
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_DIRECTORY="$1"
SIMULATOR_ID="$2"
RUN_UI="${3:-}"
if [[ -n "$RUN_UI" && "$RUN_UI" != --ui ]]; then
    echo "The optional third argument must be --ui" >&2
    exit 2
fi
cd "$ROOT_DIR"
mkdir -p build/validation/acceptance
RUN_DIRECTORY="$(mktemp -d "$ROOT_DIR/build/validation/acceptance/run.XXXXXX")"
trap 'RUN_EXIT_CODE=$?; printf "Acceptance logs/results: %s\n" "$RUN_DIRECTORY"; exit "$RUN_EXIT_CODE"' EXIT
DERIVED_DIRECTORY="${VALIDATION_DERIVED_DATA:-$ROOT_DIR/build/validation/DerivedData-$SIMULATOR_ID}"
DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project iOSLOG2LUTConverter.xcodeproj -scheme iOSLOG2LUTConverter \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED_DIRECTORY" \
    CODE_SIGNING_ALLOWED=NO build-for-testing > "$RUN_DIRECTORY/build.log" 2>&1
xcrun simctl install "$SIMULATOR_ID" "$DERIVED_DIRECTORY/Build/Products/Debug-iphonesimulator/iOSLOG2LUTConverter.app"
STAGE_ARGUMENTS=("$SOURCE_DIRECTORY" "$SIMULATOR_ID")
if [[ "$RUN_UI" == --ui ]]; then STAGE_ARGUMENTS+=(--photos); fi
python3 scripts/validation/stage_simulator_fixtures.py "${STAGE_ARGUMENTS[@]}"
python3 scripts/validation/generate_precision_fixture.py --output "$RUN_DIRECTORY/precision"
APP_CONTAINER="$(xcrun simctl get_app_container "$SIMULATOR_ID" raamblings.iOSLOG2LUTConverter data)"
mkdir -p "$APP_CONTAINER/Documents/PrecisionFixtures"
cp "$RUN_DIRECTORY/precision/neutral-ramp-10bit-high422.mp4" "$APP_CONTAINER/Documents/PrecisionFixtures/"
TEST_ARGUMENTS=(-only-testing:iOSLOG2LUTConverterTests)
if [[ "$RUN_UI" == --ui ]]; then
    TEST_ARGUMENTS+=(-only-testing:iOSLOG2LUTConverterUITests/WorkflowRegressionTests \
        -only-testing:iOSLOG2LUTConverterUITests/RealMediaWorkflowTests)
fi
xcodebuild -project iOSLOG2LUTConverter.xcodeproj -scheme iOSLOG2LUTConverter \
    -destination "$DESTINATION" -derivedDataPath "$DERIVED_DIRECTORY" \
    -parallel-testing-enabled NO -resultBundlePath "$RUN_DIRECTORY/results.xcresult" \
    CODE_SIGNING_ALLOWED=NO test-without-building "${TEST_ARGUMENTS[@]}" > "$RUN_DIRECTORY/tests.log" 2>&1
printf 'Acceptance results: %s\n' "$RUN_DIRECTORY/results.xcresult"
