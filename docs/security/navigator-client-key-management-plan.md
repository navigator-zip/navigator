# Navigator Client Key Management Plan v1

## Purpose

This document turns the client E2EE behavior spec into a concrete implementation plan for Navigator.

It defines:

- what secret material exists on the client
- where each secret is stored
- when secret material is created, fetched, wrapped, rotated, or destroyed
- how first-device setup behaves
- how future-device approval behaves
- how mnemonic recovery behaves
- how optional iCloud convenience is scoped
- what the app must never do

This plan is intentionally client-centric. It does not redefine the server protocol. It explains how the Navigator app should behave when using the current encrypted sync contract.

Related documents:

- [navigator-client-e2ee-sync-spec-v1.md](/Users/rk/Developer/Navigator/docs/security/navigator-client-e2ee-sync-spec-v1.md)
- `/Users/rk/Developer/navigator-api/docs/navigator-api-e2ee-behavior.md`

## Product Position

Navigator v1 should use a three-layer recovery model:

1. Keychain-backed local storage is always used.
2. iCloud-backed convenience is used only if available and only for optional wrapped recovery material.
3. A mnemonic recovery phrase is always generated on first encrypted account initialization and must be user-confirmed before setup completes.

This gives Navigator:

- a secure local default
- an Apple-platform convenience path
- a platform-independent recovery path

The mnemonic is the durable user-held recovery mechanism.

## Core Rules

The client must follow these rules without exception:

- Generate the first `AccountMasterKey` only when the account is truly uninitialized.
- Never silently generate a replacement `AccountMasterKey` for an already initialized account.
- Treat `/sync/bootstrap` as the authoritative source of encrypted account state.
- Store long-lived private material only in protected local storage.
- Keep iCloud out of the root trust model.
- Treat the mnemonic as a recovery phrase, not as a casual export of raw private-key material.
- Require mnemonic confirmation during first setup.
- If recovery fails, stop and report failure. Do not create a new account key.

## Secret Inventory

Navigator v1 should treat these as distinct secret classes.

### Account master key

- The root symmetric key for the encrypted account.
- This is the key that must remain stable across devices for a single account.
- Browser-content decryption ultimately depends on this key or on keys derived from it.

### Device agreement private key

- The private X25519 key used to receive device-wrapped envelopes.
- This key is unique per device.

### Device signing private key

- The private Ed25519 key used to sign approval artifacts.
- This key is unique per device.

### Collection keys

- Symmetric keys used for encrypted object domains.
- These may be wrapped under the `AccountMasterKey`.
- They can rotate more often than the account root.

### Recovery secret

- A generated high-entropy secret created at first-account initialization.
- This is the recovery material represented to the user as a mnemonic phrase.
- It is not a user-chosen password in v1.

### Local cache key

- A device-local key used only to protect decrypted local cache.
- It must not equal the raw `AccountMasterKey`.

## Storage Plan

### Keychain is mandatory

The client should always persist local long-lived secret material in Keychain-backed protected storage.

At minimum:

- device agreement private key
- device signing private key
- locally protected form of `AccountMasterKey`
- local cache key

The app must not store this material in:

- `UserDefaults`
- plist files
- SQLite plaintext columns
- JSON files in app support
- logs, diagnostics, or analytics payloads

### Recommended Keychain accessibility

Default v1 policy:

- device agreement private key: `WhenUnlockedThisDeviceOnly`
- device signing private key: `WhenUnlockedThisDeviceOnly`
- protected local account key material: `WhenUnlockedThisDeviceOnly`
- local cache key: `WhenUnlockedThisDeviceOnly`

If background transport while locked is later required, that change must be deliberate and documented. v1 should prefer unlocked-only access for simplicity and risk reduction.

### Local account-key persistence model

Navigator should not persist the raw `AccountMasterKey` as a casual blob.

Instead:

- generate `AccountMasterKey` in memory
- wrap or protect it for local storage using platform-protected storage conventions
- persist only the protected local form
- unwrap it only when needed for decryption or envelope creation

This keeps the root key aligned with the rule that it is never persisted unwrapped outside protected storage.

## Optional iCloud Plan

### What iCloud is for

iCloud is optional convenience only.

On macOS, iCloud cannot be assumed to exist for every user because some users:

- are not signed into an Apple Account
- have iCloud disabled
- are in managed or restricted environments
- do not want Apple-account-coupled recovery behavior

### What may be stored in iCloud

If implemented, iCloud may store only optional recovery convenience material, such as:

- a locally wrapped recovery secret
- a locally wrapped account-key recovery blob
- metadata that helps the same user restore more quickly on another Apple device

### What must not depend on iCloud

Navigator must not require iCloud for:

- first-device initialization
- future-device approval
- recovery on a non-Apple device
- account continuity

If iCloud is unavailable, the account must still remain recoverable through the mnemonic and trusted-device flows.

## Mnemonic Plan

### What the mnemonic is

The mnemonic should be the user-readable encoding of the generated recovery secret.

The mnemonic should not be described in product copy as:

- “your private key”
- “your account encryption key”

Instead it should be described as:

- “recovery phrase”
- “recovery phrase for your encrypted sync account”

That wording preserves flexibility for future rotation and avoids teaching users the wrong mental model.

### Mnemonic generation policy

On first encrypted account initialization:

- generate a random high-entropy recovery secret locally
- encode it as a mnemonic phrase using a fixed versioned encoding
- display it once during setup
- require the user to confirm it before setup completes

The client should treat the mnemonic as versioned recovery material, not as ad hoc display text.

### Mnemonic confirmation policy

Navigator should not let the user finish encrypted setup until backup confirmation is complete.

Allowed confirmation methods:

- full mnemonic re-entry
- targeted word-position challenge

For v1, full mnemonic re-entry is acceptable and simpler.

Recommended UX:

1. show the phrase
2. require explicit “I have written this down”
3. navigate to a confirmation screen
4. require the user to type it back
5. complete setup only after exact validation

This is important because a passive “continue” button is not enough to establish that the user actually captured the phrase.

### Re-display policy

v1 should not casually re-show the same mnemonic later.

Preferred policy:

- show it during first setup
- do not reveal it again from settings
- if the user wants a fresh phrase later, rotate the recovery secret and recovery envelope

This reduces long-term local-secret retrievability pressure.

## Bootstrap State Machine

Navigator must decide what to do after authentication by reading `/sync/bootstrap`.

### Authoritative bootstrap tuple

The client expects:

- `latestCursor`
- `snapshot`
- `devices`
- `deviceEnvelopes`
- `recoveryEnvelope`
- `user`

### Uninitialized account

Treat the account as uninitialized only when all of the following are true:

- `latestCursor == 0`
- `snapshot == nil`
- `recoveryEnvelope == nil`
- `devices.isEmpty`
- `deviceEnvelopes.isEmpty`

Only in this state may the app mint the first `AccountMasterKey`.

### Initialized account

Treat the account as initialized if any encrypted artifact already exists.

Examples:

- `latestCursor > 0`
- `snapshot != nil`
- `recoveryEnvelope != nil`
- `devices` is non-empty
- `deviceEnvelopes` is non-empty

In this state, the app must not create a replacement account key.

### Inconsistent bootstrap

Mixed tuples are protocol or integrity failures.

Examples:

- `latestCursor == 0` and `devices` non-empty
- no snapshot but non-empty wrapped envelopes
- otherwise empty account plus non-`nil` recovery envelope

The client must stop and surface an error. It must not infer that initialization is safe.

## First Device Plan

This flow applies only after bootstrap proves the account is uninitialized.

### Step-by-step flow

1. Authenticate the user.
2. Fetch `/sync/bootstrap`.
3. Confirm the tuple is fully uninitialized.
4. Generate `AccountMasterKey`.
5. Generate device agreement keypair.
6. Generate device signing keypair.
7. Generate initial collection keys.
8. Protect and store device private keys locally in Keychain.
9. Protect and store local account-key material in Keychain.
10. Generate the recovery secret.
11. Encode recovery secret as mnemonic.
12. Show mnemonic UI.
13. Require mnemonic confirmation.
14. Derive or unwrap the recovery-encryption key locally from the recovery secret.
15. Build the server recovery envelope.
16. Build a self-addressed account-key device envelope for this device.
17. Encrypt initial snapshot state if needed.
18. Upload:
    - device public keys
    - key fingerprints
    - device envelope
    - recovery envelope
    - encrypted sync snapshot and later sync mutations
19. Mark encrypted account setup complete locally.

### Non-negotiable guard

Steps 15 through 19 must not be considered complete if the mnemonic confirmation step has not succeeded.

If the app crashes or is quit before confirmation, setup should resume in a guarded in-progress state instead of silently continuing as completed.

## Future Device Approval Plan

This flow is for a new device when the account is already initialized and another trusted device is available.

### New device steps

1. Authenticate.
2. Fetch `/sync/bootstrap`.
3. Detect initialized account state.
4. Generate new device agreement keypair locally.
5. Generate new device signing keypair locally.
6. Create a pending device record on the server.
7. Display verification material to the user.

### Existing trusted device steps

1. Load the pending device details.
2. Verify the out-of-band artifact locally.
3. Refuse approval if verification fails.
4. Use the existing account key to create a device envelope for the new device.
5. Sign the approval payload.
6. Upload approval plus wrapped envelope.

### New device completion

1. Fetch the now-available device envelope.
2. Unwrap the existing `AccountMasterKey` locally.
3. Store local protected account-key material in Keychain.
4. Store device private keys in Keychain.
5. Bootstrap encrypted state.
6. Join normal incremental sync.

### Security point

Future-device approval does not create a new account key.

It transfers access to the existing account key to the new device after verification.

## Mnemonic Recovery Plan

This flow is for an initialized account when no trusted device is available.

### High-level idea

The server holds an encrypted recovery envelope.

The user holds the mnemonic.

The new device combines those two things locally to regain access to the same existing `AccountMasterKey`.

### Recovery steps

1. Authenticate.
2. Fetch `/sync/bootstrap`.
3. Detect initialized account state.
4. Fetch `/sync/recovery-envelope`.
5. Ask the user for the mnemonic.
6. Decode the mnemonic into the recovery secret locally.
7. Derive or reconstruct the recovery unwrap material locally.
8. Use that material to decrypt or unwrap the existing `AccountMasterKey` from the recovery envelope.
9. Generate fresh device agreement and signing keypairs for this new device.
10. Store those private keys in Keychain.
11. Store protected local account-key material in Keychain.
12. Create and upload a new self-addressed device envelope for this device.
13. Bootstrap encrypted sync state.
14. Join incremental sync.

### What recovery is not

Recovery is not:

- generating a replacement root key
- creating a second encrypted account lineage
- restoring plaintext from the server

Recovery means restoring access to the same pre-existing encrypted account root.

## Crypto Object Model

Navigator should keep the object model conceptually simple.

### On the first device

Local protected storage contains:

- device agreement private key
- device signing private key
- protected local account-key material
- local cache key

Server stores:

- device records
- public keys and fingerprints
- device-wrapped account-key envelopes
- recovery envelope
- encrypted snapshots
- encrypted sync events

User stores:

- mnemonic recovery phrase

Optional iCloud stores:

- optional locally wrapped recovery convenience artifact

### On a recovered device

The server gives the encrypted recovery envelope.

The user gives the mnemonic.

The device reconstructs access locally, then persists its own local protected key material and uploads its own device envelope.

## UX Plan

### First setup screens

Recommended sequence:

1. “Encrypted sync setup”
2. “Your recovery phrase”
3. “Confirm your recovery phrase”
4. “Setup complete”

### Messaging requirements

The product must explain:

- the phrase is required to recover access if devices are lost
- Navigator cannot recover it for the user later
- the phrase should be stored offline in a safe place
- losing both device access and the phrase may permanently lose access to existing encrypted sync data

### Recovery screen requirements

Recovery entry should:

- clearly say that this restores access to an existing encrypted account
- not imply creation of a new account
- fail closed on invalid phrase entry

### Approval screen requirements

Trusted-device approval should:

- distinguish itself clearly from mnemonic recovery
- show the verification artifact
- require explicit confirmation on the approving device

## Rotation Plan

### Device replacement

If a user adds a normal new device:

- no root-key rotation is required
- only wrap the existing account key for the new device

### Recovery phrase rotation

If the user wants a fresh phrase:

- generate a new recovery secret
- create a new recovery envelope
- invalidate the old recovery envelope
- require the same phrase-confirmation flow as first setup

### Device compromise

If a device is suspected compromised:

- revoke the device
- stop issuing new wrapped keys to it
- rotate collection keys by default
- evaluate whether root-key rotation is necessary

## Failure Handling

The app must fail safely in these cases.

### Bootstrap inconsistent

- show error
- do not initialize
- do not create account key

### Mnemonic confirmation incomplete

- do not mark setup complete
- do not silently suppress future confirmation

### Mnemonic recovery failure

- show error
- allow retry
- do not create replacement account key

### Missing iCloud

- continue normally
- do not downgrade account security
- do not block setup

### Keychain unavailable

- stop setup or recovery
- surface explicit error
- do not continue with plaintext-only memory assumptions after app relaunch

## Local State Model

The client should make account-key state explicit rather than burying it in booleans.

Recommended local state cases:

- `signedOut`
- `authenticatedAwaitingBootstrap`
- `uninitializedAccount`
- `initializingEncryptedAccount`
- `awaitingMnemonicConfirmation`
- `initializedAwaitingLocalKeys`
- `initializedReady`
- `pendingTrustedDeviceApproval`
- `recoveringWithMnemonic`
- `syncIntegrityFailure`

This makes first-run, future-device, and recovery flows easier to reason about and test.

## Implementation Phases

### Phase 1: key storage foundation

- add a dedicated local key-material store abstraction
- implement Keychain persistence for device keys and protected local account-key material
- define local state machine for bootstrap and onboarding

### Phase 2: bootstrap decision wiring

- branch startup behavior from `/sync/bootstrap`
- implement strict uninitialized vs initialized tuple checks
- add integrity-failure handling for inconsistent tuples

### Phase 3: first-device setup

- generate key material
- generate mnemonic
- add phrase display and confirmation screens
- persist local key material
- upload initial recovery and device envelopes

### Phase 4: future-device approval

- generate local device keys on the new device
- create pending-device flow
- implement verification artifact UX
- implement approval and device-envelope consumption

### Phase 5: mnemonic recovery

- implement recovery phrase entry
- implement recovery-envelope unwrap flow
- store recovered account-key material locally
- rejoin encrypted sync

### Phase 6: optional iCloud convenience

- add a clearly optional iCloud-backed recovery convenience layer
- keep it isolated from mandatory recovery logic

### Phase 7: key lifecycle and settings

- add phrase rotation
- add device revocation support
- add trust reset and local wipe controls

## Testing Plan

Navigator should have explicit coverage for:

- cold-start on uninitialized account
- cold-start on initialized account with local keys present
- cold-start on initialized account without local keys
- first-device setup interrupted before mnemonic confirmation
- successful first-device setup after confirmation
- recovery with valid mnemonic
- recovery with invalid mnemonic
- trusted-device approval success
- trusted-device approval verification mismatch
- bootstrap inconsistent tuple handling
- sign-out wiping decrypted local state
- local key material missing or corrupted
- no-iCloud environment
- iCloud-available environment with the same mandatory fallback behavior

## Things Navigator Must Never Do

Navigator must never:

- create a new account root key for an initialized encrypted account
- store long-lived private material outside protected storage
- treat iCloud as mandatory
- continue first-device setup without phrase confirmation
- reveal the existing mnemonic casually after setup
- interpret recovery failure as permission to reset encrypted history
- send plaintext account keys, recovery secrets, or decrypted browser content to the server

## Recommended v1 Decision

For Navigator v1, the concrete plan should be:

- always store local secret material in Keychain
- always generate a mnemonic recovery phrase on first encrypted account setup
- always require mnemonic confirmation before setup completes
- use iCloud only as optional convenience if available
- recover the same existing `AccountMasterKey` from the mnemonic plus server recovery envelope on a new device
- never mint a replacement key unless bootstrap proves the account is truly uninitialized
