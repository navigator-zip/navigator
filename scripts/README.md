# CEF integration notes

## Vendor requirement

This repo expects the CEF source/processed payload at:

`Vendor/CEF/Release/Chromium Embedded Framework.framework`

and optional helper staging at:

`Vendor/CEF/Release/CEFResourcesStaging/` (legacy `Vendor/CEF/Release/Resources/` still supported)

The packagable runtime artifact expected by the app build is:

`Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework`

Helper helper apps in the vendored runtime should include roles:

- base (`*Helper.app`)
- renderer (`*Helper (Renderer).app`)
- gpu (`*Helper (GPU).app`)
- plugin (`*Helper (Plugin).app`) optional depending on branch

If required helpers are missing at `Vendor/CEF/Release`, the build phase fails early with an explicit error.

## Runtime packaging and app attachment

`CEFPackager` now creates `Vendor/CEF/Release/ChromiumEmbeddedRuntime.framework` as a deterministic runtime artifact.

`Attach Packaged CEF Runtime` (a shell build phase) consumes that artifact and moves:

- `Chromium Embedded Framework.framework` → `Contents/Frameworks`
- helper bundles discovered by role (`base`, `renderer`, `gpu`, `plugin`) → `Contents/Frameworks`
- `runtime_layout.json` and top-level resource files → `Contents/Resources`

## Deterministic layout used by runtime

`Contents/Frameworks` is now the authoritative helper location expected by runtime discovery.

- `settings.browser_subprocess_path` is set from the helper executable found under `Contents/Frameworks`
- `expectedPaths.helpersDirRelativePath` is written as `Contents/Frameworks`
- `expectedPaths.resourcesRelativePath` is written as `Contents/Resources`
- `expectedPaths.localesRelativePath` is written as `Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/locales`

This avoids fallback behavior that can accidentally pick the app executable.

## Verify script

Run:

```
./scripts/verify_runtime.sh /path/to/Navigator.app
```

It now checks:

- framework and `runtime_layout.json` presence
- required helpers (`base`, `renderer`, `gpu`) in `Contents/Frameworks`
- optional plugin helper
- framework and helper code signatures
- locale resource presence
- signature checks are non-deep by default; set `VERIFY_DEEP_CODESIGN=1` for an optional deep pass

## Signing

- Helper bundles and framework are signed during CEF runtime packaging when `shouldSign` is enabled and `--sign-identity` is provided.
- For app signing/notarization continue to run:

```
./scripts/sign_and_notarize.sh /path/to/Navigator.app
```

Set `TEAM_ID`, `APPLE_ID`, and `NOTARY_PASSWORD` as documented by that script.

## CEFPackager Swift target

This project now includes a `CEFPackager` Swift target and shared Xcode scheme.

Use it for one-step fetch + stage + runtime package + hardening/sign order:

- `--mode all` (default)
- `--cef-archive-url <https URL to CEF zip>` or `--cef-archive-path <local archive>`
- `--app-bundle-path <path/to/Navigator.app>` (defaults from `APP_BUNDLE_PATH`; optional for `--mode package` if you only want runtime artifact output)
- `--sign-identity "<Developer ID Application: Name (TEAMID)>"`
- `--team-id` (for notary submission), `--apple-id`, `--notary-password`
- `--notary-profile <keychain profile name>` (optional alternative to APPLE_ID/NOTARY_PASSWORD)
- `--notarize` to run notarytool + stapler
- `--skip-fetch` to reuse `Vendor/CEF/Release`
- `CEF_STAGING_DIR` and `CEF_RESOURCES_STAGING_DIR` can be overridden in env to control where packager/bundle script reads CEF artifacts from.

Helper discovery behavior in the packager:

- Uses exact role-based names for target executable naming when staging:
  - `<App> Helper.app`
  - `<App> Helper (Renderer).app`
  - `<App> Helper (GPU).app`
  - `<App> Helper (Plugin).app`
- If archive helper names are stock names (for example `Chromium Helper...`), it maps them by role and renames to target names while copying.
- `base`, `renderer`, `gpu` roles are required; `plugin` remains optional.

Entitlements used by the target are in `scripts/entitlements/`:

- `app.plist`
- `helper.plist`
- `helper_renderer.plist`
- `helper_gpu.plist`
- `helper_plugin.plist`

Runtime checks:

- Codesign is verified non-deep by default during packager runs.
- Set `VERIFY_DEEP_CODESIGN=1` for an additional deep verification pass.

Run options from Xcode:
- Pick the **CEFPackager** scheme and click **Run**.
- Set environment in the scheme to inject your credentials and artifact URL.
