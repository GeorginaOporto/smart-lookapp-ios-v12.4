# Golden image-extraction baseline

This baseline records the iOS v12.4 build whose image extraction was validated on the iPad as pixel-accurate. The extraction pipeline is frozen: CMM/manual search work must not modify its touch mapping, orientation normalization, MobileSAM raster contract, mask selection, retry lifecycle, or fallback behavior unless the user explicitly requests a new extraction change.

## Validated IPA

- Local artifact: `C:\SmartLookapp IOS v12.4\work\downloaded-ipa-20260826\SmartLookApp9\SmartLookApp-v12.4-unsigned (4).ipa`
- Size: `57113292` bytes
- SHA-256: `5614B9426F295B2AEFBBBA6CFEDF3CE49A2377B7A39CE4486B8B64B8EF245F98`
- Published source commit: `c7c891707b23322f450f0b04bf51fa5199faca90`
- Release: `ios-v12.4-build-25`

## Frozen source contract

- `SmartLookApp/MVDMobileSAM.swift`
  - SHA-256: `99C3CCA159858C92E9F95C5F8A2DD0109A360960E3A935070BDE8FAE57AB82E9`
- `SmartLookApp/MVDImageExtraction.swift`
  - SHA-256: `E23237CBF7D8FF4B6CF61CA1FCD1FFE32C17A5333989FEF6B2982BC7F77CC1E3`
- `SmartLookApp/Models/mobile_sam.onnx`
  - SHA-256: `68D7EBBE837AF66ECE5BF0ACC334D0317EBA77CB20F87063C03729751F6B2DD2`
- Extraction region in `SmartLookApp/ContentView.swift`, beginning at `MVDExtractionCanvas` and ending immediately before `CameraPicker` (validated lines 1957-2379):
  - SHA-256 over UTF-8 lines joined with LF: `AEB912BA7E471FAF4C8BC51144D6D8FBAB74470AFEB5EDAFDDEAD706531F4DE4`

## Required invariants

1. UIKit converts the visible tap to the original image pixel and then to one normalized top-left coordinate.
2. Image orientation is normalized once; extraction must not rotate or mirror the source afterward.
3. MobileSAM receives image pixels and the prompt in the same top-left row order.
4. Mask selection remains anchored to the exact prompted pixel.
5. A second extraction attempt must release the previous inference buffers and must not run MobileSAM and Vision simultaneously after MobileSAM succeeds.
6. Search-engine, CMM-routing, embeddings, and feedback changes must remain outside this pipeline.
## Protected functional baseline — build 71

The following components are considered validated and must not be modified without an explicit user instruction naming the component and the requested change:

1. **Image extraction**
   - Touch coordinate conversion from the visible image to original pixels.
   - Orientation normalization and preservation.
   - MobileSAM prompt, mask selection, extraction lifecycle, retry handling, and extracted-piece output.
   - This entire pipeline remains frozen; search, embeddings, feedback, logos, and browser work must stay outside it.

2. **Application logos and icons**
   - AppIcon asset catalog and SmartLookAppLogo rendering in the login, header, and search screens.
   - The validated logo assets must not be replaced, cropped, renamed, or reconnected to another resource without explicit approval.

3. **Training-library download and installation**
   - Server download route and fallback route.
   - Sequential installation of all selected libraries followed by one complete index build.
   - Canonical Documents/TrainingData hierarchy, including shared manufacturer-level CMM.
   - These changes must not be mixed with search or extraction changes.

4. **Fleet-aware search routing**
   - Resolution by customer, manufacturer, aircraft model, nose, manual type, ATA folder, and CMM scope.
   - Correct manual/folder names, including MaintMessage as the canonical maintenance-message folder.
   - CMM applicability filtering must remain separate from the visual ranking formula.

5. **Persistent learning and embeddings — build 71**
   - Training-index cache persists in the Documents container across IPA updates.
   - Existing legacy feedback sidecars are migrated before index restoration.
   - Positive feedback and positive query embeddings persist with the canonical training library.
   - Feedback sidecars do not invalidate or force a full training-index rebuild.
   - The Android-compatible ranking/feedback contract remains the reference; no independent iOS learning algorithm may be introduced without explicit approval.

6. **Current IPA update contract**
   - The bundle identifier remains com.aeronexares.smartlookapp.mvd so an update can preserve the app container.
   - Uninstalling the app is not equivalent to updating it: uninstalling removes local libraries and learning data unless they were exported or synchronized first.

## Explicitly not frozen

The following areas remain open for future work and may be changed when requested: CMM browser/knowledge acknowledgement flow, browser navigation, negative-feedback policy, progress/status wording, server synchronization, duplicate GitHub workflows, and release cleanup.

Any future change must preserve the protected baseline above unless the user explicitly authorizes an exception.
