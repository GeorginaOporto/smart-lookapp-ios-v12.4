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


