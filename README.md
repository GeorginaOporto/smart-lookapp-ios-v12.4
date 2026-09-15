# SmartLookApp iOS MVD — pipeline validation

This is a SwiftUI MVD app used to validate the build path and the first
fleet-aware location/CMM workflow:

`private GitHub repository → GitHub Actions macOS/Xcode → unsigned .ipa → Windows/Sideloadly → iPad`

It contains no real aircraft images, credentials, or customer documents. The
active catalog is limited to the supplied B777-200 and B777-300 location and
CMM applicability data. B787, B737, A320/A321, and A330 remain explicit empty
fleet slots for future independent additions.

The CMM Location workflow includes:

- B777 galley and lavatory selectors.
- Unified CREW STATION selector for captain, first officer, observer, OFCR,
  and F/A seats, including the B777-300 5L/5R positions.
- Grouped stowage-bin selectors with their CMM numbers.
- Seat applicability for the supplied B777-200 and B777-300 configurations.
- Galley Standard Practices merged into the selected galley; it is not a
  separate overlay field.

Training records keep the selected location and create local CMM folders under
Application Support/TrainingData/<model>/<customer>/<nose>/CMM/.

## Local validation

The Windows workstation cannot run `xcodebuild`; the iOS build runs on the GitHub-hosted macOS runner. Push this folder to a private repository, then run **Actions → Build unsigned iOS IPA → Run workflow**.

The workflow publishes `SmartLookApp-unsigned.ipa` as an artifact. Download it only to the trusted Windows workstation, and do not commit the generated IPA.

## Sideloading boundary

Sideloadly and the iPad step are intentionally manual. Connect only the intended iPad over USB, use the user's own free Apple ID in Sideloadly, and keep the IPA local. An unsigned build may require Sideloadly's normal free-account signing step; the GitHub workflow itself never receives Apple ID credentials.

## Fleet architecture

FleetArchitecture.swift owns the family registry and shared models.
B777FleetData.swift owns the B777 location catalog and CMM applicability.
Future fleet families can be populated without editing the B777 rules.
