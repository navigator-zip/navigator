# ModelKit Guide

## Purpose

- `ModelKit` is the dedicated Swift package for pure model/object definitions used across Navigator.
- Put shared domain objects, identifiers, payload shapes, and reusable value types here.
- Treat `ModelKit` as the source of truth for app object representation.

## Allowed Contents

- Pure Swift `struct`, `class`, and `enum` model definitions.
- Strongly typed IDs and related lightweight wrapper types.
- Protocol conformances needed for the model to be usable (`Codable`, `Sendable`, `Equatable`, `Hashable`, `Identifiable`, and similarly lightweight traits).
- Small representation helpers that do not introduce business behavior or side effects.

## Forbidden Contents

- Business logic.
- Networking clients, request dispatch, or transport concerns.
- Persistence/storage logic.
- View models, views, controllers, or UI-only presentation helpers.
- Dependency registration, environment wiring, or service singletons.
- Cross-model mutation orchestration or workflow logic.

## Ownership Rules

- When introducing a new app/domain object type, default to creating it in `ModelKit`.
- If multiple packages need the same object shape, consolidate it into `ModelKit` instead of duplicating it.
- Keep package-specific adapters around `ModelKit` types in the owning package; do not move adapter behavior into `ModelKit`.
- If a type starts local and later becomes shared, promote it into `ModelKit` before adding another copy elsewhere.

## Design Guidance

- Prefer value types unless reference semantics are required by the model itself.
- Keep APIs narrow and representation-oriented.
- Avoid embedding behavior that depends on services, time, caches, network state, or persistence state.
- Keep these types easy to decode, test, and reuse across feature packages.
