# Tools/CEFBuilder

`Tools/CEFBuilder` builds Chromium Embedded Framework from source and emits the two
archives CEFPackager already consumes:

- runtime: `cef_binary_<spec-name>_macosarm64.tar.bz2`
- client/helpers: `cef_binary_<spec-name>_macosarm64_client.tar.bz2`

Example:

```bash
swift Tools/CEFBuilder/main.swift \
  --spec Vendor/CEF/BuildSpecs/cef_145_codec_arm64.json \
  --work-dir ~/Library/Caches/Navigator/CEFSource \
  --output-dir Vendor/CEF/Artifacts \
  --cache-dir ~/Library/Caches/Navigator/CEFBuilds \
  --verbose
```

The command prints JSON to stdout:

```json
{
  "runtime": ".../Vendor/CEF/Artifacts/cef_binary_cef_145_codec_arm64_macosarm64.tar.bz2",
  "client": ".../Vendor/CEF/Artifacts/cef_binary_cef_145_codec_arm64_macosarm64_client.tar.bz2"
}
```
