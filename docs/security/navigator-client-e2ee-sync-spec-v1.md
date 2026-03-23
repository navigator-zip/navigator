# Navigator Client E2EE Sync Spec v1

## Purpose

This document defines how Navigator behaves as the client owner of end-to-end encrypted browser sync.

For a more implementation-oriented plan covering Keychain, optional iCloud convenience, mnemonic confirmation, first-device setup, trusted-device approval, and recovery UX/state handling, see [navigator-client-key-management-plan.md](/Users/rk/Developer/Navigator/docs/security/navigator-client-key-management-plan.md).

Navigator is responsible for:

- generating keys
- holding plaintext
- encrypting outgoing state
- decrypting incoming state
- approving future devices
- enforcing local trust and rollback checks
- protecting local cache and key material

The server is not trusted with browser-content plaintext.

## Security Goals

Navigator must ensure:

- browser content never leaves the device unencrypted
- long-term account key material is never sent to the server in plaintext
- every encrypted payload is authenticated before use
- future-device approval is authenticated by an existing trusted device or recovery flow
- cursor regression is treated as a sync integrity failure
- revoked devices never receive newly wrapped keys
- sign-out or trust reset invalidates local plaintext state

## Client Security Invariants

The following invariants are mandatory:

- `AccountMasterKey` is never uploaded in plaintext
- `AccountMasterKey` is never persisted unwrapped outside platform-protected storage
- decrypted browser objects are never included in analytics, logs, or crash diagnostics
- AEAD authentication failure is a hard failure, not a best-effort parse
- local knowledge of stream heads must be persisted durably
- a device must not approve another device without out-of-band identity verification
- local decrypted cache must be protected separately from transport encryption
- cursor advancement must not happen for unauthenticated payloads
- sign-out wipes decrypted local state and local wrapped content keys where practical

## Protocol Profile

Navigator must implement the same protocol profile as the server v1 spec.

### Algorithm suite

- device-to-device key envelopes: HPKE over X25519 with HKDF-SHA256 and ChaCha20-Poly1305
- content encryption: ChaCha20-Poly1305
- device approval signatures: Ed25519
- human-entered recovery derivation, if ever supported: Argon2id with versioned parameters
- v1 recovery path: generated random high-entropy recovery secret

### Versioning

Every encrypted or signed structure must include:

- `version`
- `suite`
- `createdAt`

At minimum, versioned structures are:

- content envelopes
- mutation-event envelopes
- bootstrap snapshot envelopes
- device envelopes
- recovery envelopes
- device approval records

### Serialization

REST transport is JSON over HTTPS.

Binary fields are base64url without padding.

Signed structures and AAD-bound visible fields use:

- UTF-8 canonical JSON
- lexicographically sorted keys
- no insignificant whitespace

Navigator must not sign or verify serializer-specific incidental formatting.

### Content envelope

Navigator must treat the following fields as present on every encrypted content payload:

- `version`
- `suite`
- `keyID`
- `nonce`
- `ciphertext`
- `aad`

### Device envelope

Navigator must treat the following fields as present on every device-wrapped account-key envelope:

- `version`
- `suite`
- `senderDeviceID`
- `recipientDeviceID`
- `recipientKeyFingerprint`
- `createdAt`
- `ciphertext`

### Recovery envelope

Navigator must treat the following fields as present on every recovery envelope:

- `version`
- `scheme`
- `createdAt`
- `ciphertext`
- `kdfParams`, only if recovery is human-entered text in a future version

## Nonce Rules

For v1:

- AEAD nonce length is 96 bits
- nonces are generated using cryptographically secure randomness
- each encryption under a given key must use a fresh nonce
- nonce reuse under the same key is forbidden

Because v1 uses fresh full-object encryption and fresh event encryption, random nonces are the required strategy.

## AAD Rules

Navigator must build and verify AAD exactly as specified.

For encrypted object state:

- `version`
- `suite`
- `userID`
- `objectID`
- `objectKind`
- `collectionID`
- `objectVersion`
- `isDeleted`

For encrypted sync events:

- `version`
- `suite`
- `userID`
- `streamID`
- `eventID`
- `cursor`
- `entityID`
- `entityKind`
- `clientMutationID`, if present

For encrypted bootstrap snapshots:

- `version`
- `suite`
- `userID`
- `streamID`
- `snapshotCursor`
- `snapshotKind`

If AAD verification fails, the payload is invalid and must not be used.

## Key Material Classes

Navigator must treat these as distinct secret classes.

### Account master key

- root symmetric key for browser-content access
- generated once per account unless rotated

### Device agreement private key

- X25519 private key for HPKE recipient envelopes
- long-lived for the device

### Device signing private key

- Ed25519 private key for approval records
- long-lived for the device

### Locally wrapped account master key

- locally stored protected form of `AccountMasterKey`
- retrieved only through platform-protected storage

### Collection keys

- symmetric keys for sync domains
- rotated more often than the account master key

### Local cache key

- protects the local decrypted cache at rest
- device-local only

### Recovery artifact

- generated high-entropy recovery secret
- not treated like a user password in v1

## Apple Platform Storage Policy

This section is normative for Navigator on Apple platforms.

### Protocol private keys

v1 uses X25519 and Ed25519 protocol keys.

Because those protocol keys are not the natural Secure Enclave fit for this design, v1 policy is:

- protocol private keys may be stored as exportable key material
- they must be stored only in Keychain-backed protected storage
- they must not be stored in UserDefaults, plist files, or general app storage

### Keychain accessibility

Default requirements:

- device agreement private key: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- device signing private key: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- locally wrapped account master key: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` only if background sync while locked is explicitly required
- otherwise locally wrapped account master key: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- recovery artifact, if locally retained at all: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

### Secure Enclave usage

Secure Enclave is:

- not required for v1 protocol keys
- allowed as an additional local wrapping anchor if implemented explicitly
- not a substitute for the protocol profile

### Platform backup policy

Platform-backed recovery material is optional convenience, not part of the root trust model.

If Navigator later supports platform backup:

- it must remain optional
- trusted-device approval and recovery-secret fallback must still work without it
- the product must state clearly that Apple-account recovery may affect access to backed-up wrapped material

### Locked-device behavior

Default v1 behavior:

- do not require browser-content decryption while the device is locked
- background transport may fetch encrypted payloads while locked
- decrypted application of sync state waits until required local keys are available

If this policy changes later, that must be explicit because it changes storage-class requirements.

### Local cache protection

Any local decrypted cache must be encrypted at rest using a device-local protected key.

The cache key must not equal the raw `AccountMasterKey`.

## Bootstrap Contract Interpretation

Navigator must treat `GET /sync/bootstrap` as the authoritative read-only source for encrypted account bootstrap state.

For v1, the client expects bootstrap to include:

- `user`
- `latestCursor`
- `snapshot`
- `devices`
- `deviceEnvelopes`
- `recoveryEnvelope`

Client expectations:

- `snapshot` is the encrypted canonical snapshot, or `null`
- `latestCursor` is the latest committed global cursor
- `devices` is the current device record set, including approval state and key fingerprints
- `deviceEnvelopes` contains wrapped account-key envelopes relevant to the requesting device
- `recoveryEnvelope` is the current recovery envelope, or `null`

Navigator must not infer account initialization from plaintext bookmark or workspace emptiness.

## Account Initialization Decision Rule

Navigator must branch initial sync using the encrypted bootstrap tuple, not ad hoc heuristics.

Treat the account as `uninitialized` only when all of the following are true:

- `latestCursor == 0`
- `snapshot == null`
- `recoveryEnvelope == null`
- `devices` is empty
- `deviceEnvelopes` is empty

Only in that explicit uninitialized state may Navigator create the first account root material.

If any encrypted sync artifact already exists, Navigator must treat the account as initialized. Examples include:

- `latestCursor > 0`
- `snapshot != null`
- `recoveryEnvelope != null`
- one or more `devices`
- one or more `deviceEnvelopes`

In the initialized case, this device must not mint a replacement `AccountMasterKey`. It must join through trusted-device approval or recovery.

If bootstrap returns a mixed or inconsistent tuple, Navigator must treat that as an integrity or protocol error, not as permission to initialize a new encrypted account. Examples include:

- `latestCursor == 0` with non-empty `devices`
- `snapshot == null` with non-empty `deviceEnvelopes`
- `recoveryEnvelope != null` with an otherwise empty account tuple

An explicit server field such as `accountState: uninitialized | initialized` would be a cleaner future contract, but until that exists the client must apply the tuple rule above.

## First Device Flow

When encrypted sync is enabled for the first time on a truly uninitialized account:

1. generate `AccountMasterKey`
2. generate device agreement keypair
3. generate device signing keypair
4. generate initial collection keys
5. wrap collection keys under `AccountMasterKey`
6. create a self-addressed wrapped account-key envelope
7. generate a recovery secret
8. create recovery envelope locally
9. upload:
   - public keys
   - key fingerprints
   - wrapped account-key envelope
   - wrapped collection metadata if needed
   - encrypted sync state

Navigator should require explicit user confirmation that the recovery secret has been captured before treating setup as complete.

The server never receives plaintext key material.

## Recovery Secret Policy

v1 recovery uses a generated random high-entropy secret.

v1 recovery does not use a user-memorable passphrase.

If a future version allows user-memorable recovery text:

- Argon2id is mandatory
- parameters must be versioned
- derived unwrap keys must never leave the client

## Recovery Secret Display Policy

This must not remain ambiguous.

v1 default:

- the recovery secret is shown during setup
- the app does not casually re-show the same secret later
- later user action may generate a new recovery secret and rotate the recovery envelope

If product requirements later demand “show existing recovery secret again,” that is a separate design choice and must explicitly state how a retrievable local copy is stored and what additional risk is accepted.

## Future Device Onboarding

### Default path: trusted-device approval

1. new device authenticates
2. new device generates agreement and signing keypairs locally
3. new device requests a pending device record from the server
4. new device displays an out-of-band verification artifact
5. existing trusted device verifies that artifact locally
6. existing trusted device signs approval
7. existing trusted device wraps `AccountMasterKey` to the new device agreement public key
8. new device downloads wrapped key material
9. new device decrypts bootstrap and joins the sync set

### Verification artifact requirements

The artifact must contain:

- pending `deviceID`
- agreement-key fingerprint
- signing-key fingerprint
- server-issued challenge

Allowed UX forms:

- QR code
- short authentication string
- explicit fingerprint comparison

Approval must fail if the trusted device cannot verify the same artifact locally.

Without this step, the flow is vulnerable to server-side key substitution.

## Recovery Flow

If no trusted device is available:

1. new device authenticates
2. new device requests recovery envelope
3. user enters the generated recovery secret
4. new device unwraps `AccountMasterKey` locally
5. new device generates fresh device keys
6. new device uploads a new self-addressed wrapped envelope
7. new device performs encrypted bootstrap

Recovery is separate from trusted-device approval and must be labeled clearly as such.

Recovery failure must never trigger silent creation of a replacement account key, because that would permanently sever access to existing ciphertext.

## Canonical Mutation Model

v1 uses:

- full canonical encrypted object state
- opaque append-only encrypted mutation events
- optimistic concurrency with expected cursor and expected object version

v1 does not use encrypted patch semantics.

For each logical mutation:

1. apply user intent to local canonical plaintext state
2. produce new canonical object plaintext
3. encrypt full object state
4. create mutation envelope with:
   - `clientMutationID`
   - expected `cursor`
   - expected `objectVersion`
   - encrypted canonical object state
5. upload mutation
6. apply committed result only after verified response

## Bootstrap and Replay Rules

Bootstrap is authoritative for:

- first device after recovery
- future-device initial state
- integrity-failure recovery
- retention-gap recovery

Events are authoritative only for incremental catch-up after a known good base state.

Navigator must not try to reconstruct account state from partial unauthenticated events.

## Sync Integrity Rules

Navigator must persist:

- last seen global stream cursor
- last seen object version for locally materialized objects
- current trusted-device list snapshot if available

Navigator must reject:

- stream cursor regression
- object version regression outside explicit trust-reset/bootstrap flow
- unexplained lineage changes
- approval records with invalid signatures

Navigator must treat as sync integrity failures:

- repeated unexplained decrypt failures
- unexpected cursor gaps that cannot be resolved by replay
- conflicting bootstrap lineage after known committed local state

## Split-View and Suppression Limitations

v1 does not fully prevent a malicious server from presenting different valid encrypted histories to different devices.

v1 client-side mitigations are:

- durable cursor-regression checks
- signed device approval records
- device-list verification during approval
- stream-head comparison when trusted devices are already communicating
- detection of withheld or inconsistent replay when durable known heads and new responses conflict

This is a limitation, not a solved problem.

## Decrypt Failure Behavior

On bootstrap or event decrypt failure:

- do not partially apply the payload
- do not advance the cursor
- quarantine the envelope for debugging without plaintext exposure
- mark sync state unhealthy
- attempt replay if safe
- fall back to full encrypted bootstrap when replay is not sufficient

Navigator must never “best effort” parse corrupted ciphertext.

## Local Cache Rules

The local cache is part of the threat model.

Required behavior:

- local decrypted browser state must be protected at rest
- sign-out wipes decrypted cache
- trust reset wipes decrypted cache
- cache entries encrypted under stale keys must not be silently reused after key rotation

## Plaintext Exposure Surfaces

Plaintext browser content may exist only in:

- live in-memory models
- device-protected local cache
- explicit user-approved exports

Plaintext browser content must not leak into:

- app logs
- analytics events
- crash reports
- tracing payloads
- state restoration payloads
- widget payloads
- screenshot preview metadata where avoidable
- thumbnail caches where avoidable
- pasteboard or share-extension payloads without explicit user action
- Spotlight or system search indexing
- support bundles unless explicitly user-approved and redacted

## Transport and Domain Boundary

Navigator must keep encrypted sync transport models separate from decrypted app domain models.

Rules:

- `Networking` owns encrypted sync request and response transport types
- decrypted browser objects are mapped into internal app domain models only after local verification and decryption
- auth, billing, session, and account-management models may remain readable transport models unless redesigned separately

This separation is required to avoid accidental plaintext assumptions in the transport layer.

## Device Trust UI

Navigator should expose:

- current device identity
- trusted device list
- pending device requests
- device revoke action
- recovery-secret rotation action

The approval UI must expose enough identity material to support real verification:

- device label
- device ID
- public-key fingerprint summary
- pairing code or QR confirmation

## Revocation and Rotation Rules

Revoked devices must never receive newly wrapped keys after the revocation is committed.

### Lost device, believed safe

Default action:

- revoke device
- rewrap active keys for remaining devices

### Stolen device or possible compromise

Default action:

- revoke device
- rotate collection keys
- optionally rotate `AccountMasterKey` if exposure scope is unclear
- ensure newly written content uses rotated keys immediately

### Recovery secret exposed

Default action:

- rotate recovery envelope immediately
- consider broader key rotation depending on timing and compromise confidence

### Secure storage corruption or local key loss

Default action:

- perform local trust reset
- wipe local decrypted cache
- recover through trusted-device approval or recovery flow

## Threat-Triggered Actions Matrix

- lost device, believed safe: revoke + rewrap
- stolen device, possibly unlocked: revoke + rotate collection keys by default
- widespread compromise suspicion: revoke + rotate account master key
- recovery secret exposure: rotate recovery envelope immediately
- repeated decrypt failures: quarantine payloads, stop cursor advancement, force bootstrap if needed
- cursor regression: treat as integrity failure, stop sync, require explicit recovery
- invalid approval signature: reject onboarding attempt
- Keychain corruption or local secret loss: wipe local decrypted cache, reset local trust state, recover through trusted device or recovery secret

## Package Ownership Guidance

Expected ownership in Navigator:

- `Networking`
  - encrypted sync transport requests and responses
- `ModelKit`
  - decrypted browser domain models
- dedicated crypto or security module
  - key generation
  - wrapping
  - deterministic envelope construction
  - secure storage access
  - recovery logic
- app feature layer
  - device trust UI
  - approval flow UI
  - recovery flow UI

## Recommended Defaults

For v1:

- one global encrypted per-user sync log
- full encrypted object state
- append-only opaque encrypted events
- generated random recovery secret
- mandatory out-of-band verification for device approval
- no browser-content decryption while device is locked by default
- no plaintext browser-content leakage to logs, analytics, or support tooling
