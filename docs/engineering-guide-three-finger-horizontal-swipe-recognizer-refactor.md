# Three-Finger Horizontal Swipe Recognizer Refactor Guide

## Objective

Refactor the current `SwipeRightGestureRecognizer` into a robust, production-quality three-finger horizontal swipe recognizer that is materially more accurate, more debuggable, and more resilient to real-world trackpad input noise.

The refactor should solve the current weaknesses:

- over-reliance on centroid-only motion
- premature direction locking
- immediate cancellation on transient finger-count instability
- inconsistent smoothing
- weak confidence modeling
- no group coherence validation
- no stabilization phase before gesture onset
- no real velocity or angle analysis
- overly brittle rejection rules

The resulting recognizer should correctly and reliably identify:

- three-finger swipe right
- three-finger swipe left

while rejecting:

- diagonal smears
- staggered multi-finger drags
- pinch / spread-like motions
- accidental posture adjustments
- noisy startup jitter
- brief contact glitches that should not kill an otherwise valid gesture

This guide assumes the recognizer is running over a stream of `TouchFrame` values produced by a lower-level multitouch source.

## Executive Summary

The current implementation is inaccurate because it models a three-finger swipe as a single centroid translation. That is insufficient.

A true three-finger swipe recognizer must reason about:

- group stability: are the same three fingers present long enough to form a candidate?
- motion onset: has intentional movement begun, or are the fingers just settling?
- direction lock: is the gesture meaningfully moving left or right yet?
- coherence: are the fingers moving together, or is one finger dominating?
- trajectory quality: is movement mostly horizontal, with tolerable vertical drift?
- shape stability: is the contact cluster maintaining a stable overall form?
- commit confidence: has enough evidence accumulated over enough frames to recognize the gesture?
- hysteresis: can the recognizer survive tiny reversals and transient contact-count glitches?

The refactor should move from a centroid-only rule set to a more explicit gesture model based on:

- filtered centroid motion
- per-frame group motion features
- cluster shape features
- onset and commit hysteresis
- short-lived glitch tolerance
- a clean and explicit state machine

## Refactor Goals

### Functional Goals

The refactor should:

- recognize left and right three-finger horizontal swipes accurately
- reduce false rejection caused by startup jitter
- reduce false acceptance caused by centroid-only movement
- tolerate brief contact-count instability without collapsing the candidate
- avoid double-firing or repeated recognition for the same swipe
- preserve rich diagnostics for offline tuning and replay testing

### Architectural Goals

The refactor should:

- separate feature extraction from recognition policy
- make thresholds explicit and tunable
- reduce hidden state coupling
- make the state machine easier to inspect and unit test
- allow deterministic replay of recorded touch-frame sequences
- make future extension possible for other gestures

### Non-goals

This refactor does not need to:

- solve all multi-touch gesture recognition in one system
- introduce a reducer-style event pipeline
- build a generic gesture DSL
- support arbitrary finger counts
- support pinch, rotate, or complex gesture arbitration in V1

The goal is a clean, high-quality recognizer for one class of gesture: three-finger horizontal swipes.

## Problems in the Current Recognizer

### 1. Gesture Representation Is Too Lossy

The current recognizer tracks only:

- contact count
- centroid
- accumulated travel
- drift

That discards essential information about how the fingers are moving relative to one another.

As a result, these distinct cases can look similar:

- three fingers moving together rightward
- one finger moving strongly while two barely move
- a changing contact cloud due to finger shape noise
- diagonal repositioning
- a cluster translation caused by unstable contact registration

This is the most important architectural problem.

### 2. Direction Is Assigned Too Early

The current code assigns direction as soon as the sign of `centroid.x - startX` becomes nonzero.

That means a tiny amount of startup jitter can decide the gesture direction. Any later sign change may cause rejection.

This is not how real touch input behaves. There should be an explicit dead zone before direction lock.

### 3. Smoothing Is Inconsistent and Conceptually Confused

The current implementation stores `smoothedCentroids`, but those are not actually smoothed values; they are raw centroids stored in a finite window and only averaged opportunistically.

Worse, it uses:

- current centroid for horizontal travel
- averaged centroid for vertical drift

This inconsistency makes behavior unpredictable and hard to tune.

### 4. Exact Finger Count Is Treated as a Hard Invariant

The current recognizer cancels immediately if `frame.contacts.count != 3`.

Real trackpad hardware and private touch APIs often produce transient glitches:

- contact briefly disappears
- contact splits or merges
- count jumps to 2 or 4 for a frame

A recognizer should tolerate short mismatches if the broader candidate remains coherent.

### 5. No Onset Stabilization

The first frame with 3 contacts becomes the baseline immediately.

In practice, finger placement usually includes a settling interval. Baseline capture should happen only after a short priming phase.

### 6. No Angle or Velocity Tests

The current recognizer uses displacement and vertical drift, but not:

- velocity
- motion angle
- sustained horizontal dominance

That makes it easy for slow, diagonal, or messy motions to accumulate enough displacement to be accepted.

### 7. No Group Coherence or Shape Stability Measurement

A three-finger swipe is a coordinated group movement. The recognizer should verify that the contact cloud behaves like a stable group.

Even if stable contact IDs are not available, there are still useful group-level features that can be computed.

### 8. Commit Rules Are Too Simple

Commit is based on:

- minimum horizontal travel
- minimum confidence

But the confidence function is only:

- horizontal progress score x vertical straightness score

This does not capture enough of the gesture quality.

## Target Refactor Shape

The recognizer should be split into three conceptual layers:

### 1. Frame Normalization / Feature Extraction

Convert a raw `TouchFrame` into a normalized set of measurable features.

Examples:

- contact count
- centroid
- filtered centroid
- bounding box width / height
- average pairwise contact distance
- cluster aspect ratio
- frame-to-frame delta
- velocity
- motion angle

### 2. Candidate State Management

Maintain a gesture candidate over time.

Examples:

- start time
- priming start time
- baseline centroid
- baseline shape
- filtered motion history
- direction lock
- reversal debt
- mismatch budget
- consecutive good-frame count

### 3. Recognition Policy

Apply explicit rules to decide:

- continue candidate
- upgrade state
- reject candidate
- commit gesture
- cool down / reset

This separation is important. Today these responsibilities are interleaved.

## Recommended State Machine

Replace the current state machine with:

```swift
enum State {
	case idle
	case priming(Candidate)
	case ready(Candidate)
	case tracking(Candidate)
	case committed(CommittedGesture)
	case cooldown(CooldownState)
}
```

### State Meanings

#### `idle`

No gesture candidate exists.

Entry condition:

- default resting state
- previous candidate rejected or fully completed

Exit condition:

- sufficient contacts appear to begin priming

#### `priming`

Potential three-finger gesture is forming, but baseline has not yet been finalized.

Purpose:

- absorb initial finger landing noise
- require short-lived stability
- establish baseline after the fingers settle

Entry condition:

- approximately 3 contacts appear
- initial cluster shape is reasonable

Exit condition:

- enough stable priming frames collected -> `ready`
- instability too severe -> `idle`

#### `ready`

A candidate exists and baseline is established, but no intentional movement has yet been detected.

Purpose:

- wait for meaningful motion onset
- avoid assigning direction from tiny noise

Entry condition:

- priming stabilized successfully

Exit condition:

- movement exceeds onset threshold -> `tracking`
- candidate destabilizes -> `idle`

#### `tracking`

Intentional movement appears underway.

Purpose:

- measure motion quality
- lock direction after dead zone
- accumulate confidence and hysteresis

Entry condition:

- onset thresholds passed

Exit condition:

- commit thresholds passed consistently -> `committed`
- severe instability or invalid motion -> `idle`

#### `committed`

Gesture has been recognized and emitted.

Purpose:

- prevent duplicate firing
- allow gesture tail to complete naturally

Entry condition:

- commit criteria satisfied

Exit condition:

- contacts lifted or gesture clearly ended -> `cooldown` or `idle`

#### `cooldown`

Optional short refractory state.

Purpose:

- avoid accidental immediate re-triggering from the same physical interaction

Entry condition:

- completed committed gesture

Exit condition:

- cooldown elapsed or contacts gone -> `idle`

If you prefer not to keep a dedicated cooldown state, you can instead stay in `committed` until all contacts are gone. That is acceptable for V1.

## Candidate Data Model

The current `Candidate` struct is too minimal. Replace it with a richer one.

### Proposed Candidate Structure

```swift
struct Candidate {
	let primingStartTimestamp: TimeInterval
	let baselineTimestamp: TimeInterval

	let baselineCentroid: Point
	let baselineBoundingBox: BoundingBox
	let baselineAveragePairwiseDistance: Double

	let filteredCentroid: Point
	let previousFilteredCentroid: Point
	let latestRawCentroid: Point

	let directionLock: GestureDirection?
	let directionLockTimestamp: TimeInterval?

	let cumulativeHorizontalTravel: Double
	let cumulativeVerticalTravel: Double

	let reverseTravelAfterLock: Double
	let badContactFrameCount: Int
	let consecutiveGoodTrackingFrames: Int
	let consecutiveCommitEligibleFrames: Int

	let motionHistory: RingBuffer<MotionSample>
	let clusterHistory: RingBuffer<ClusterSample>
}
```

You do not need this exact shape, but the recognizer does need to store substantially more than it does now.

### Why This Is Better

This candidate structure explicitly supports:

- priming and baseline establishment
- filtered motion
- direction locking
- reversal tolerance
- glitch tolerance
- consecutive-frame hysteresis
- replay-friendly diagnostics

## Data Types to Introduce

### `Point`

```swift
struct Point: Equatable {
	let x: Double
	let y: Double
}
```

Avoid using a gesture-specific name like `SmoothedCentroid` for a general geometry type.

### `BoundingBox`

```swift
struct BoundingBox: Equatable {
	let minX: Double
	let maxX: Double
	let minY: Double
	let maxY: Double

	var width: Double { maxX - minX }
	var height: Double { maxY - minY }
}
```

Useful for cluster spread and shape stability.

### `MotionSample`

```swift
struct MotionSample: Equatable {
	let timestamp: TimeInterval
	let filteredCentroid: Point
	let dxFromBaseline: Double
	let dyFromBaseline: Double
	let frameDx: Double
	let frameDy: Double
	let vx: Double
	let vy: Double
	let speed: Double
	let angleRadians: Double
}
```

### `ClusterSample`

```swift
struct ClusterSample: Equatable {
	let timestamp: TimeInterval
	let contactCount: Int
	let centroid: Point
	let boundingBox: BoundingBox
	let averagePairwiseDistance: Double
	let spreadScaleRelativeToBaseline: Double
}
```

## FrameFeatures

This is the most important new type.

```swift
struct FrameFeatures {
	let timestamp: TimeInterval
	let contactCount: Int

	let rawCentroid: Point
	let filteredCentroid: Point

	let boundingBox: BoundingBox
	let averagePairwiseDistance: Double

	let dxFromBaseline: Double
	let dyFromBaseline: Double

	let frameDx: Double
	let frameDy: Double
	let dt: TimeInterval

	let vx: Double
	let vy: Double
	let speed: Double
	let angleRadians: Double

	let horizontalDominance: Double
	let spreadScaleRelativeToBaseline: Double
}
```

This should be computed centrally, rather than scattered through the recognizer logic.

## Feature Extraction Recommendations

The refactor should introduce a dedicated feature extraction step per frame.

Always compute these features:

### 1. Raw centroid

Already available.

### 2. Filtered centroid

Use a single, consistent filter for both axes.

Recommended first pass:

- exponential moving average

For example:

```swift
filtered = alpha * raw + (1 - alpha) * previousFiltered
```

Use one alpha for now. If needed later, use One Euro filtering.

### 3. Bounding box

Compute from contact positions.

### 4. Average pairwise distance

For three contacts, compute pairwise distances:

- `d(0,1)`
- `d(0,2)`
- `d(1,2)`

Then average them.

This is a simple and very useful shape-stability feature.

### 5. Frame delta and velocity

Use filtered centroids, not raw ones, for velocity.

```swift
dt = max(current.timestamp - previous.timestamp, minimumDt)
vx = (currentFiltered.x - previousFiltered.x) / dt
vy = (currentFiltered.y - previousFiltered.y) / dt
```

### 6. Motion angle

```swift
angle = atan2(vy, vx)
```

### 7. Horizontal dominance

A simple scalar:

```swift
horizontalDominance = abs(vx) / max(abs(vx) + abs(vy), epsilon)
```

or use displacement-based dominance if preferred.

### 8. Spread scale change

```swift
spreadScaleRelativeToBaseline = currentAveragePairwiseDistance / baselineAveragePairwiseDistance
```

This is useful to reject pinch/spread-like motion.

## New Configuration Shape

The existing configuration likely has:

- `minimumHorizontalTravel`
- `maximumVerticalDrift`
- `minimumConfidence`
- `smoothingWindow`

That is too small for a recognizer of this complexity.

### Recommended Configuration

```swift
struct SwipeRecognizerConfiguration {
	let requiredFingerCount: Int

	let primingMinimumDuration: TimeInterval
	let primingMaximumMotion: Double

	let directionLockDistance: Double
	let minimumHorizontalTravelToCommit: Double
	let maximumVerticalOffsetToCommit: Double

	let minimumHorizontalVelocityForOnset: Double
	let minimumHorizontalVelocityForCommit: Double
	let maximumAngleFromHorizontalRadians: Double

	let maximumSpreadScaleDeviation: Double

	let maximumBadContactFrames: Int
	let maximumReverseTravelAfterLock: Double

	let minimumConsecutiveTrackingFrames: Int
	let minimumConsecutiveCommitEligibleFrames: Int

	let filterAlpha: Double
	let minimumFrameDeltaTime: TimeInterval
}
```

### Threshold Philosophy

The thresholds should not be arbitrary magic numbers buried in logic. They should be documented and tunable.

Examples of intended meaning:

- `primingMinimumDuration`: how long the cluster must remain reasonably stable before baseline capture
- `directionLockDistance`: how far the group must move horizontally before left/right is assigned
- `maximumSpreadScaleDeviation`: how much the finger cluster can expand/contract before it no longer looks like a coherent swipe
- `maximumBadContactFrames`: how many transient contact-count glitches are tolerated
- `maximumReverseTravelAfterLock`: how much opposite travel is tolerated after direction lock

## Recognition Logic by Phase

### 1. Idle -> Priming

When the recognizer is idle, it should not create a candidate merely because one frame has exactly three contacts.

Instead:

- require at least `requiredFingerCount`
- compute cluster features
- initialize candidate with provisional baseline
- begin priming
- record diagnostic: candidate started

Important:

If the input stream does not provide stable contact identities, that is fine. Do not block the refactor on IDs. Group-level features will still improve accuracy meaningfully.

### 2. Priming

Priming is a short stabilization interval before motion is interpreted.

What to validate during priming:

- contact count remains near target
- centroid movement stays under a small threshold
- cluster spread stays reasonably stable
- no large velocity spike yet

Priming success:

- finalize baseline centroid
- finalize baseline shape metrics
- transition to `ready`

Priming failure:

- reject back to `idle` if contact instability is sustained
- reject back to `idle` if motion becomes too large before stabilization
- reject back to `idle` if cluster shape is extremely erratic

This prevents startup noise from poisoning the baseline.

### 3. Ready

This state means:

- baseline is set
- candidate is valid
- intentional motion has not started yet

What to watch for:

Use filtered motion from baseline:

- horizontal displacement
- horizontal velocity
- angle from horizontal

Transition to tracking:

- movement exceeds a small onset threshold, or
- horizontal velocity exceeds onset threshold, and
- motion angle is sufficiently horizontal

Stay in ready:

- if motion is still within dead zone, remain in `ready`

Reject:

- if candidate becomes unstable beyond grace budget
- if cluster shape departs too far from baseline

### 4. Tracking

This is where most recognition quality lives.

Tracking responsibilities:

- keep filtered centroid current
- compute velocities and angle
- lock direction once dead zone crossed
- accumulate reversal debt after lock
- validate shape stability
- tolerate short contact glitches
- count consecutive "good" frames
- count consecutive "commit-eligible" frames

Direction lock policy:

Do not assign direction until:

```swift
abs(dxFromBaseline) >= directionLockDistance
```

Then:

- `dx > 0 -> .right`
- `dx < 0 -> .left`

Once locked, retain direction.

Reversal handling:

Do not reject on the first sign change.

Instead:

- measure opposite-direction travel after lock
- reject only if accumulated reverse travel exceeds threshold

This is much more humane and realistic.

Tracking quality checks:

A frame should be considered "good" for tracking if:

- contact mismatch is within budget
- angle is near horizontal
- spread remains stable
- velocity is not degenerate
- overall motion remains coherent

### 5. Commit

The recognizer should commit only when multiple criteria are satisfied for multiple consecutive frames.

Recommended commit conditions:

All of the following should be true:

- direction is locked
- horizontal travel from baseline exceeds commit threshold
- horizontal velocity exceeds commit threshold or recent average velocity does
- vertical offset is within allowed bounds
- angle remains near horizontal
- spread deviation is within tolerance
- mismatch budget has not been exhausted
- consecutive commit-eligible frame count >= required threshold

Why consecutive frames matter:

Single-frame spikes are common in noisy input. Multi-frame commitment is safer.

Recognition emission:

- transition to `committed`
- emit one `RecognizedGesture`
- include direction, timestamp, confidence, and diagnostics snapshot if useful

### 6. Committed / Cooldown

After recognition:

- do not emit again during the same physical gesture
- wait for lift-off or gesture end condition
- optionally enforce short cooldown

The simplest rule:

- remain committed until the contact cluster disappears or falls below threshold for longer than the bad-frame budget

## Confidence Model Refactor

The existing confidence function is too simple.

Replace it with a more structured confidence score derived from several normalized factors.

### Recommended Confidence Components

1. Horizontal progress score
   How far beyond commit threshold has the gesture traveled?

2. Horizontality score
   How close is the motion angle to horizontal?

3. Velocity score
   Does the gesture move with enough horizontal speed to feel swipe-like?

4. Shape stability score
   How stable is average pairwise distance relative to baseline?

5. Coherence score
   How stable has the gesture been over recent frames?

Even if you do not implement all of these in V1, the score should be extensible in this direction.

### Example Confidence Composition

```swift
confidence =
	0.30 * horizontalProgressScore +
	0.25 * horizontalityScore +
	0.20 * velocityScore +
	0.15 * shapeStabilityScore +
	0.10 * trackingConsistencyScore
```

Clamp to `[0, 1]`.

This is far more expressive than the current product of horizontal score and vertical score.

## Diagnostics Refactor

The current diagnostics are useful, but the system would benefit from better structure.

### Current Issues

- diagnostics are tightly coupled to recognition control flow
- measurements are emitted at irregular points
- not enough context is preserved for tuning thresholds

### Recommended Improvements

#### 1. Add state-entry diagnostics

Whenever state changes, emit a structured transition event.

#### 2. Add periodic frame feature diagnostics

On every processed frame, or optionally sampled frames, emit feature summaries:

- state
- raw centroid
- filtered centroid
- `dx` / `dy` from baseline
- velocity
- angle
- spread scale
- direction lock
- bad-frame count
- reversal debt
- commit-eligible flag

#### 3. Separate rejection reason from measurement

When rejecting, emit:

- a feature snapshot
- a rejection reason

not just the reason alone

#### 4. Include threshold values in diagnostics

This makes tuning much easier during offline analysis.

## Suggested File / Type Organization

A refactor of this size should not leave everything in one file.

Recommended structure:

- `SwipeGestureRecognizer.swift`
  Public recognizer type and top-level process entry point.
- `SwipeGestureRecognizer+State.swift`
  State enum, state helpers, transition helpers.
- `SwipeGestureRecognizer+Candidate.swift`
  Candidate model and mutation/update methods.
- `SwipeGestureRecognizerConfiguration.swift`
  Thresholds and configuration defaults.
- `SwipeGestureFrameFeatures.swift`
  Feature extraction models and helper functions.
- `SwipeGestureGeometry.swift`
  `Point`, bounding box, pairwise distance helpers, filtering helpers, angle helpers.
- `SwipeGestureDiagnostics.swift`
  Diagnostic event generation helpers.
- `SwipeGestureTests.swift`
  Deterministic unit tests and replay tests.

If you prefer fewer files, at least split:

- configuration
- geometry/features
- recognizer state/policy

## Concrete Refactoring Plan

### Phase 1: Rename and Clarify Intent

Tasks:

- rename `SwipeRightGestureRecognizer` to something accurate such as `ThreeFingerHorizontalSwipeRecognizer` or `ThreeFingerSwipeRecognizer`
- rename `SwipeRightGestureRecognizerResult` accordingly
- make it explicit in naming and docs that both left and right are recognized

Reason:

The current type name misleads future maintainers and encourages mismatched assumptions.

### Phase 2: Introduce Neutral Geometry Types

Tasks:

- replace `SmoothedCentroid` with a general-purpose `Point`
- add `BoundingBox`
- add reusable geometry helpers:
  - centroid computation
  - bounding box computation
  - pairwise distance computation
  - angle normalization

Reason:

The current types are too tied to one implementation detail and not reusable enough.

### Phase 3: Extract Feature Computation

Tasks:

- build a `FrameFeatures` type
- centralize:
  - filtered centroid calculation
  - velocity calculation
  - displacement calculation
  - angle calculation
  - spread metrics
- make recognizer logic consume `FrameFeatures` rather than raw frame geometry directly

Reason:

This is the biggest structural improvement. Recognition logic should act on measured features, not recompute them ad hoc.

### Phase 4: Replace Window-Averaging with a Real Filter

Tasks:

- remove `smoothedCentroids: [SmoothedCentroid]` as the primary smoothing mechanism
- replace with one filtered centroid value plus previous filtered centroid
- use exponential smoothing first

Reason:

Window averaging is acceptable for offline analysis, but it is not a great primary interaction filter for a stateful recognizer.

Recommendation:

Keep a small ring buffer of recent feature samples for diagnostics and commit hysteresis, but do not treat the buffer itself as the smoothing strategy.

### Phase 5: Add Priming Phase

Tasks:

- add `.priming` state
- during priming:
  - require target contact count with tolerance
  - ensure only small motion
  - measure baseline shape
- transition to `.ready` only after stable priming duration

Reason:

This removes one of the biggest current failure modes: baseline capture during landing jitter.

### Phase 6: Add Dead Zone Before Direction Lock

Tasks:

- add `directionLockDistance`
- keep `directionLock == nil` until horizontal motion crosses that threshold
- once locked, do not clear direction unless candidate is rejected

Reason:

This prevents tiny startup noise from choosing direction.

### Phase 7: Introduce Contact Glitch Tolerance

Tasks:

- replace immediate rejection on `contactCount != 3` with:
  - bad-frame counter, or
  - mismatch duration budget
- continue candidate through short glitches
- reject only when mismatch budget is exceeded

Reason:

Real input streams are not perfectly stable.

### Phase 8: Add Angle and Velocity Gating

Tasks:

- compute `vx`, `vy`, `speed`, and `angle`
- require:
  - horizontal onset velocity for tracking entry
  - horizontal angle cone during tracking / commit
- make thresholds configurable

Reason:

This sharply improves differentiation between swipes and sloppy drags.

### Phase 9: Add Shape Stability Checks

Tasks:

- compute average pairwise distance between contacts
- store baseline average pairwise distance after priming
- during tracking and commit, reject or penalize if spread deviates too much

Reason:

A clean three-finger swipe should maintain reasonably stable shape. Pinch/spread-like motions should not pass.

### Phase 10: Rework Confidence Model

Tasks:

- replace current confidence function with a multi-factor scorer
- include at least:
  - horizontal progress
  - horizontality / angle
  - velocity
  - spread stability
- make weighting explicit

Reason:

The current confidence is too weak to be meaningful.

### Phase 11: Rework Diagnostics

Tasks:

- emit diagnostics from a single helper layer
- emit structured per-frame feature snapshots
- preserve rejection reasons and threshold context

Reason:

This is critical for post-deployment tuning.

## Implementation Details

### Filtering Choice

Recommended first implementation:

Use exponential moving average:

```swift
func filteredPoint(previous: Point?, raw: Point, alpha: Double) -> Point {
	guard let previous else { return raw }
	return Point(
		x: alpha * raw.x + (1 - alpha) * previous.x,
		y: alpha * raw.y + (1 - alpha) * previous.y
	)
}
```

Why this is a good first choice:

- simple
- deterministic
- cheap
- easy to tune
- better latency than box averaging

If later needed, migrate to a One Euro filter, but do not start there unless the jitter/latency tradeoff clearly demands it.

### Motion Angle Evaluation

A helper should normalize angle closeness to horizontal.

Example approach:

- for rightward motion, ideal angle is `0`
- for leftward motion, ideal angle is `pi` or `-pi`

For generic horizontality before lock, use:

```swift
horizontality = abs(vx) / max(abs(vx) + abs(vy), epsilon)
```

For commit after lock, use angle thresholding.

### Reversal Debt

After direction lock, compute opposite-signed motion increments.

For example, if locked right:

- positive frame `dx` contributes to forward progress
- negative frame `dx` contributes to reversal debt

Reject only when reversal debt exceeds threshold.

This is much better than "if sign changes, reject."

### Consecutive-frame Hysteresis

Track at least two counters:

- `consecutiveGoodTrackingFrames`
- `consecutiveCommitEligibleFrames`

This lets you require a candidate to remain good for multiple frames before each major transition.

## Testing Strategy

The refactor should be accompanied by a much stronger test suite.

### 1. Deterministic Unit Tests for State Transitions

Test every transition:

- `idle -> priming`
- `priming -> ready`
- `ready -> tracking`
- `tracking -> committed`
- `tracking -> idle` on instability
- `committed -> idle` after lift-off

Each transition should have both success and failure cases.

### 2. Replay-based Gesture Fixtures

Create recorded or synthetic `TouchFrame` sequences representing:

Positive cases:

- clean right swipe
- clean left swipe
- slightly noisy right swipe
- right swipe with tiny startup jitter
- right swipe with one-frame contact glitch
- right swipe with minor vertical drift

Negative cases:

- three-finger stationary rest
- diagonal drag
- pinch-like contraction
- spread-like expansion
- one-finger dominant motion
- motion that starts left then really goes right
- slow posture adjustment with small drift

Each replay test should assert:

- final recognition or rejection
- state progression if useful
- diagnostic rejection reason if rejected

### 3. Threshold Tuning Tests

Build tests around known near-boundary cases:

- just below direction lock distance
- just above direction lock distance
- just below commit travel
- just above commit travel
- just above max angle
- just below max angle
- one bad contact frame vs too many bad frames

This will protect tuning changes from accidental regressions.

### 4. Regression Corpus

Once you have a logging pipeline from real hardware, save representative bad sequences and turn them into replay tests.

This is one of the most valuable long-term investments for a recognizer like this.

## Performance Notes

This recognizer should be cheap. The refactor does not require expensive computation.

Acceptable per-frame work:

- centroid
- bounding box
- pairwise distances for 3 contacts
- simple EMA filter
- some trig
- a few struct updates

This is trivial for modern hardware.

Avoid:

- repeated allocation of arrays per frame where possible
- unbounded motion history storage
- recomputing the same geometry multiple times in one frame
- overly chatty diagnostics in release mode unless gated

Use fixed-size ring buffers where history is needed.

## Backward Compatibility Strategy

If this recognizer is already integrated into a gesture pipeline, introduce the refactor incrementally.

Suggested rollout:

### Step 1

Keep the public `process(frame:sessionID:)` shape unchanged.

### Step 2

Replace internal state and candidate logic while preserving external result format.

### Step 3

Expand diagnostics without breaking existing consumers.

### Step 4

Add new configuration with a compatibility initializer that maps old fields to new defaults.

This reduces downstream churn.

## Suggested Acceptance Criteria

The refactor is complete when all of the following are true:

- The recognizer no longer assigns direction based on sub-threshold noise.
- The recognizer does not immediately fail on a single transient non-3-contact frame.
- The recognizer uses one consistent filtered motion model for `x` and `y`.
- The recognizer includes a priming phase before baseline capture.
- The recognizer uses velocity and angle in onset or commit logic.
- The recognizer uses at least one cluster-shape stability metric.
- The recognizer commits only after satisfying criteria across multiple consecutive frames.
- The recognizer emits clearer diagnostics with threshold context.
- The test suite includes deterministic replay tests for both positive and negative recorded sequences.
- The recognizer performs reliably on recorded real-world data substantially better than the current version.

## Recommended Pseudocode Shape

Below is the target control-flow shape your senior developer should aim for.

```swift
func process(frame: TouchFrame, sessionID: GestureSessionID) -> Result {
	validateFrameOrdering()

	switch state {
	case .idle:
		return handleIdle(frame, sessionID)

	case .priming(let candidate):
		let update = extractFeatures(frame, candidate: candidate)
		return handlePriming(update, sessionID)

	case .ready(let candidate):
		let update = extractFeatures(frame, candidate: candidate)
		return handleReady(update, sessionID)

	case .tracking(let candidate):
		let update = extractFeatures(frame, candidate: candidate)
		return handleTracking(update, sessionID)

	case .committed(let committed):
		return handleCommitted(frame, committed, sessionID)

	case .cooldown(let cooldown):
		return handleCooldown(frame, cooldown, sessionID)
	}
}
```

And the handlers should be short, focused, and policy-oriented rather than geometry-heavy.

## Concise Implementation Brief

Refactor the existing three-finger swipe recognizer away from centroid-only recognition into a phased recognizer with explicit priming, ready, tracking, and committed states. Introduce a central `FrameFeatures` extraction layer that computes filtered centroid motion, velocity, angle, and cluster shape metrics such as bounding box and average pairwise distance. Replace immediate direction selection with a direction dead zone and persistent direction lock. Replace immediate finger-count mismatch rejection with a short mismatch budget. Add multi-frame hysteresis for both tracking and commit. Rework confidence into a multi-factor score. Preserve and improve diagnostics. Build a replay-driven test suite with both positive and negative recorded sequences. Keep the public `process(frame:sessionID:)` API stable if possible.

## Final Recommendation

Do not try to "patch" the current recognizer in place with a few threshold tweaks. That will improve things only marginally.

This should be treated as a structural refactor with these core deliverables:

- a better state machine
- a proper feature extraction layer
- a richer candidate model
- hysteresis and glitch tolerance
- replay-driven tests

That is the level of change needed to make the recognizer genuinely reliable.
