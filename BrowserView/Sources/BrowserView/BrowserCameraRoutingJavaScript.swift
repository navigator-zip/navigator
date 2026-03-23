import Foundation
import ModelKit

enum BrowserCameraRoutingJavaScript {
	private enum LocalizationKey: String {
		case managedOutputDeviceLabel = "browser_camera_managed_output_device_label"
	}

	private static let shimVersion = 1

	private static func localized(_ key: LocalizationKey) -> String {
		Bundle.module.localizedString(forKey: key.rawValue, value: key.rawValue, table: nil)
	}

	private static func makeConfiguration(
		from snapshot: BrowserCameraSessionSnapshot
	) -> BrowserCameraRendererRoutingConfigurationPayload {
		BrowserCameraRendererRoutingConfigurationPayload(
			snapshot: snapshot,
			managedDeviceLabel: localized(.managedOutputDeviceLabel)
		)
	}

	static func makeConfigurationPayload(from snapshot: BrowserCameraSessionSnapshot) -> String {
		makeConfiguration(from: snapshot).encodedJSONString()
	}

	static func makeConfigurationTransportMessage(
		from snapshot: BrowserCameraSessionSnapshot
	) -> BrowserCameraRendererTransportMessage {
		makeConfiguration(from: snapshot).transportMessage()
	}

	static func makeInstallScript(from snapshot: BrowserCameraSessionSnapshot) -> String {
		let configurationJSON = makeConfigurationTransportMessage(from: snapshot).jsonPayload

		return """
		(function() {
		  const nextConfig = \(configurationJSON);
		  const shimKey = "\(BrowserCameraRoutingScriptConstants.shimKey)";
		  const managedFrameStateKey = "\(BrowserCameraRoutingScriptConstants.managedFrameStateKey)";
		  const nativeCameraRoutingEventBridgeKey = "\(BrowserCameraRoutingScriptConstants.nativeEventBridgeKey)";
		  const routingChangeEventName = "\(BrowserCameraRoutingScriptConstants.routingChangeEventName)";
		  const cameraRoutingEventPromptMessage = "\(BrowserCameraRoutingScriptConstants.cameraRoutingEventPromptMessage)";
		  const shimVersion = \(Self.shimVersion);
		  const mediaDevices = navigator.mediaDevices;

		  function cloneConstraints(constraints) {
		    if (!constraints || typeof constraints !== "object") {
		      return constraints;
		    }
		    if (Array.isArray(constraints)) {
		      return constraints.slice();
		    }
		    return { ...constraints };
		  }

		  function hasExplicitVideoDevice(videoConstraints) {
		    return !!videoConstraints
		      && typeof videoConstraints === "object"
		      && Object.prototype.hasOwnProperty.call(videoConstraints, "deviceId");
		  }

		  function normalizedDeviceConstraintValues(deviceConstraint) {
		    if (typeof deviceConstraint === "string") {
		      return [deviceConstraint];
		    }
		    if (Array.isArray(deviceConstraint)) {
		      return deviceConstraint.filter(function(value) {
		        return typeof value === "string";
		      });
		    }
		    if (!deviceConstraint || typeof deviceConstraint !== "object") {
		      return [];
		    }

		    const values = [];
		    const exact = deviceConstraint.exact;
		    const ideal = deviceConstraint.ideal;
		    if (typeof exact === "string") {
		      values.push(exact);
		    } else if (Array.isArray(exact)) {
		      exact.forEach(function(value) {
		        if (typeof value === "string") {
		          values.push(value);
		        }
		      });
		    }
		    if (typeof ideal === "string") {
		      values.push(ideal);
		    } else if (Array.isArray(ideal)) {
		      ideal.forEach(function(value) {
		        if (typeof value === "string") {
		          values.push(value);
		        }
		      });
		    }
		    return values;
		  }

		  function requestsManagedDevice(videoConstraints, config) {
		    if (!config.exposesManagedDeviceIdentity || !config.managedDeviceID) {
		      return false;
		    }
		    if (!videoConstraints || typeof videoConstraints !== "object") {
		      return false;
		    }
		    return normalizedDeviceConstraintValues(videoConstraints.deviceId).some(function(value) {
		      return value === config.managedDeviceID;
		    });
		  }

		  function explicitBypassedDeviceIDs(constraints, config) {
		    if (!constraints || typeof constraints !== "object") {
		      return [];
		    }
		    const videoConstraints = constraints.video;
		    if (!videoConstraints || videoConstraints === true || typeof videoConstraints !== "object") {
		      return [];
		    }
		    const requestedDeviceIDs = normalizedDeviceConstraintValues(videoConstraints.deviceId);
		    if (requestedDeviceIDs.length === 0) {
		      return [];
		    }
		    if (requestsManagedDevice(videoConstraints, config)) {
		      return [];
		    }
		    return requestedDeviceIDs;
		  }

		  function requiresManagedVideoRouting(constraints, config) {
		    if (!constraints || typeof constraints !== "object") {
		      return false;
		    }

		    const videoConstraints = constraints.video;
		    if (videoConstraints == null || videoConstraints === false) {
		      return false;
		    }
		    if (videoConstraints === true) {
		      return true;
		    }
		    if (typeof videoConstraints !== "object") {
		      return false;
		    }
		    if (requestsManagedDevice(videoConstraints, config)) {
		      return true;
		    }
		    return !hasExplicitVideoDevice(videoConstraints);
		  }

		  function makeRoutingUnavailableError() {
		    const message = "Navigator Camera Output is unavailable.";
		    try {
		      return new DOMException(message, "NotReadableError");
		    } catch (_) {
		      const error = new Error(message);
		      error.name = "NotReadableError";
		      return error;
		    }
		  }

		  function attachManagedCanvasIfNeeded(canvas) {
		    if (!canvas || canvas.__navigatorCameraAttached) {
		      return;
		    }
		    if (!document || !document.documentElement || !document.documentElement.appendChild) {
		      return;
		    }
		    canvas.width = canvas.width || 1280;
		    canvas.height = canvas.height || 720;
		    canvas.style.position = "fixed";
		    canvas.style.pointerEvents = "none";
		    canvas.style.opacity = "0";
		    canvas.style.width = "1px";
		    canvas.style.height = "1px";
		    canvas.style.left = "-9999px";
		    canvas.style.top = "-9999px";
		    document.documentElement.appendChild(canvas);
		    canvas.__navigatorCameraAttached = true;
		  }

		  function drawPlaceholderFrame(state) {
		    if (!state || !state.context || !state.canvas) {
		      return;
		    }
		    state.context.fillStyle = "#000000";
		    state.context.fillRect(0, 0, state.canvas.width, state.canvas.height);
		  }

		  function ensureManagedFrameState() {
		    const existingState = window[managedFrameStateKey];
		    if (existingState) {
		      attachManagedCanvasIfNeeded(existingState.canvas);
		      return existingState;
		    }

		    const canvas = document && document.createElement
		      ? document.createElement("canvas")
		      : null;
		    const context = canvas && typeof canvas.getContext === "function"
		      ? canvas.getContext("2d", { alpha: false })
		      : null;
		    const state = {
		      canvas,
		      context,
		      lastFrameSequence: 0,
		      activeManagedTrackCount: 0,
		      nextManagedTrackSequence: 0,
		      nextManagedStreamSequence: 0
		    };
		    if (canvas) {
		      canvas.width = 1280;
		      canvas.height = 720;
		      attachManagedCanvasIfNeeded(canvas);
		    }
		    drawPlaceholderFrame(state);
		    window[managedFrameStateKey] = state;
		    return state;
		  }

		  function dispatchRoutingChange(config) {
		    try {
		      window.dispatchEvent(new CustomEvent(routingChangeEventName, { detail: config }));
		    } catch (_) {}
		  }

		  function managedDeviceVisibilityKey(config) {
		    if (!config || !config.exposesManagedDeviceIdentity || !config.managedDeviceID) {
		      return null;
		    }
		    return config.managedDeviceID;
		  }

		  function dispatchDeviceChangeIfNeeded(previousConfig, nextConfig) {
		    if (managedDeviceVisibilityKey(previousConfig) === managedDeviceVisibilityKey(nextConfig)) {
		      return;
		    }
		    if (!mediaDevices || typeof mediaDevices.dispatchEvent !== "function" || typeof Event !== "function") {
		      return;
		    }
		    try {
		      mediaDevices.dispatchEvent(new Event("devicechange"));
		    } catch (_) {}
		  }

		  function activeManagedConfig(fallbackConfig) {
		    return window[shimKey]?.config ?? fallbackConfig ?? nextConfig;
		  }

		  function emitCameraRoutingEvent(eventName, state, config, overrides) {
		    const payload = {
		      event: eventName,
		      activeManagedTrackCount: Math.max(
		        0,
		        state && typeof state.activeManagedTrackCount === "number"
		          ? state.activeManagedTrackCount
		          : 0
		      ),
		      managedTrackID: null,
		      managedDeviceID: config && config.managedDeviceID ? config.managedDeviceID : null,
		      requestedDeviceIDs: null,
		      preferredFilterPreset: config && config.preferredFilterPreset ? config.preferredFilterPreset : null,
		      errorDescription: null,
		      ...(overrides || {})
		    };
		    const payloadJSON = JSON.stringify(payload);
		    const nativeBridge = window[nativeCameraRoutingEventBridgeKey];
		    if (typeof nativeBridge === "function") {
		      try {
		        if (nativeBridge(payloadJSON) !== false) {
		          return;
		        }
		      } catch (_) {}
		    }
		    if (typeof window.prompt !== "function") {
		      return;
		    }
		    try {
		      window.prompt(cameraRoutingEventPromptMessage, payloadJSON);
		    } catch (_) {}
		  }

		  function routingErrorDescription(error) {
		    if (!error) {
		      return "Managed permission probe failed.";
		    }
		    if (typeof error === "string") {
		      return error;
		    }
		    if (typeof error.message === "string" && error.message.length > 0) {
		      return error.message;
		    }
		    if (typeof error.name === "string" && error.name.length > 0) {
		      return error.name;
		    }
		    return "Managed permission probe failed.";
		  }

		  function assignManagedRoutingMetadata(target, metadata) {
		    if (!target) {
		      return metadata;
		    }
		    try {
		      Object.defineProperty(target, "__navigatorCameraRouting", {
		        configurable: true,
		        value: metadata
		      });
		    } catch (_) {
		      try {
		        target.__navigatorCameraRouting = metadata;
		      } catch (_) {}
		    }
		    return metadata;
		  }

		  function makeManagedRoutingMetadata(config, overrides) {
		    return {
		      managed: true,
		      managedDeviceID: config.managedDeviceID || "",
		      managedDeviceLabel: config.managedDeviceLabel || "",
		      managedRoutingAvailability: config.managedRoutingAvailability,
		      outputMode: config.outputMode,
		      healthState: config.healthState,
		      publisherState: config.publisherState,
		      publisherTransportMode: config.publisherTransportMode || null,
		      preferredFilterPreset: config.preferredFilterPreset,
		      ...(overrides || {})
		    };
		  }

		  function nextManagedIdentity(state, sequenceKey, prefix) {
		    state[sequenceKey] = (state[sequenceKey] || 0) + 1;
		    return prefix + "-" + String(state[sequenceKey]);
		  }

		  function annotateEnumeratedVideoDevice(device, config) {
		    if (!device || device.kind !== "videoinput") {
		      return device;
		    }

		    assignManagedRoutingMetadata(device, {
		      routingEnabled: config.routingEnabled,
		      preferNavigatorCameraWhenPossible: config.preferNavigatorCameraWhenPossible,
		      genericVideoUsesManagedOutput: config.genericVideoUsesManagedOutput,
		      managedRoutingAvailability: config.managedRoutingAvailability,
		      preferredSourceID: config.preferredSourceID,
		      outputMode: config.outputMode,
		      healthState: config.healthState,
		      publisherState: config.publisherState,
		      publisherTransportMode: config.publisherTransportMode || null
		    });
		    return device;
		  }

		  function makeManagedDeviceEnumerationEntry(config) {
		    if (!config.exposesManagedDeviceIdentity || !config.managedDeviceID) {
		      return null;
		    }
		    return annotateEnumeratedVideoDevice({
		      deviceId: config.managedDeviceID,
		      groupId: "",
		      kind: "videoinput",
		      label: config.managedDeviceLabel || ""
		    }, config);
		  }

		  function makeManagedTrackConstraintError() {
		    const message = "Navigator Camera Output cannot switch devices on an active managed track.";
		    try {
		      return new DOMException(message, "OverconstrainedError");
		    } catch (_) {
		      const error = new Error(message);
		      error.name = "OverconstrainedError";
		      error.constraint = "deviceId";
		      return error;
		    }
		  }

		  function managedPermissionProbeConstraints(constraints, config) {
		    const routedConstraints = normalizedConstraints(constraints, config) || {};
		    const audioConstraints = Object.prototype.hasOwnProperty.call(routedConstraints, "audio")
		      ? routedConstraints.audio
		      : false;
		    let probeVideoConstraints = routedConstraints.video;

		    if (probeVideoConstraints === true && config.preferredSourceID) {
		      probeVideoConstraints = { deviceId: { exact: config.preferredSourceID } };
		    } else if (
		      probeVideoConstraints
		        && typeof probeVideoConstraints === "object"
		        && requestsManagedDevice(probeVideoConstraints, config)
		    ) {
		      const forwardedVideoConstraints = { ...probeVideoConstraints };
		      delete forwardedVideoConstraints.deviceId;
		      probeVideoConstraints = config.preferredSourceID
		        ? {
		            ...forwardedVideoConstraints,
		            deviceId: { exact: config.preferredSourceID }
		          }
		        : (
		            Object.keys(forwardedVideoConstraints).length === 0
		              ? true
		              : forwardedVideoConstraints
		          );
		    }

		    if (probeVideoConstraints == null || probeVideoConstraints === false) {
		      probeVideoConstraints = config.preferredSourceID
		        ? { deviceId: { exact: config.preferredSourceID } }
		        : true;
		    }

		    return {
		      audio: audioConstraints,
		      video: probeVideoConstraints
		    };
		  }

		  function stopStreamTracks(stream, trackKind) {
		    if (!stream || typeof stream.getTracks !== "function") {
		      return;
		    }
		    stream.getTracks().forEach(function(track) {
		      if (!track || (trackKind && track.kind !== trackKind) || typeof track.stop !== "function") {
		        return;
		      }
		      try {
		        track.stop();
		      } catch (_) {}
		    });
		  }

		  function decorateManagedVideoTrack(track, config) {
		    if (!track || track.__navigatorCameraRoutingManagedTrack) {
		      return track;
		    }

		    const state = ensureManagedFrameState();
		    const managedTrackID = nextManagedIdentity(
		      state,
		      "nextManagedTrackSequence",
		      "navigator-camera-track"
		    );
		    const originalGetSettings = typeof track.getSettings === "function"
		      ? track.getSettings.bind(track)
		      : null;
		    const originalGetConstraints = typeof track.getConstraints === "function"
		      ? track.getConstraints.bind(track)
		      : null;
		    const originalApplyConstraints = typeof track.applyConstraints === "function"
		      ? track.applyConstraints.bind(track)
		      : null;
		    const originalClone = typeof track.clone === "function"
		      ? track.clone.bind(track)
		      : null;
		    const originalStop = typeof track.stop === "function"
		      ? track.stop.bind(track)
		      : null;
		    try {
		      Object.defineProperty(track, "__navigatorCameraRoutingManagedTrack", {
		        configurable: true,
		        value: true
		      });
		      Object.defineProperty(track, "__navigatorCameraRoutingManagedTrackID", {
		        configurable: true,
		        value: managedTrackID
		      });
		      Object.defineProperty(track, "__navigatorCameraRoutingTrackStopped", {
		        configurable: true,
		        writable: true,
		        value: false
		      });
		    } catch (_) {}
		    assignManagedRoutingMetadata(
		      track,
		      makeManagedRoutingMetadata(activeManagedConfig(config), {
		        kind: "track",
		        managedTrackID: managedTrackID
		      })
		    );
		    state.activeManagedTrackCount = (state.activeManagedTrackCount || 0) + 1;
		    emitCameraRoutingEvent(
		      "track-started",
		      state,
		      activeManagedConfig(config),
		      { managedTrackID: managedTrackID }
		    );

		    function markManagedTrackStopped(eventName) {
		      if (track.__navigatorCameraRoutingTrackStopped) {
		        return;
		      }
		      try {
		        track.__navigatorCameraRoutingTrackStopped = true;
		      } catch (_) {}
		      state.activeManagedTrackCount = Math.max(0, (state.activeManagedTrackCount || 0) - 1);
		      emitCameraRoutingEvent(
		        eventName,
		        state,
		        activeManagedConfig(config),
		        { managedTrackID: managedTrackID }
		      );
		    }

		    if (originalGetSettings) {
		      try {
		        track.getSettings = function() {
		          const resolvedConfig = activeManagedConfig(config);
		          const settings = originalGetSettings() || {};
		          return {
		            ...settings,
		            deviceId: resolvedConfig.managedDeviceID || settings.deviceId || "",
		            groupId: settings.groupId || ""
		          };
		        };
		      } catch (_) {}
		    }

		    if (originalGetConstraints) {
		      try {
		        track.getConstraints = function() {
		          const resolvedConfig = activeManagedConfig(config);
		          const constraints = originalGetConstraints() || {};
		          if (!resolvedConfig.managedDeviceID || constraints.deviceId) {
		            return constraints;
		          }
		          return {
		            ...constraints,
		            deviceId: { exact: resolvedConfig.managedDeviceID }
		          };
		        };
		      } catch (_) {}
		    }

		    if (originalApplyConstraints) {
		      try {
		        track.applyConstraints = function(nextConstraints) {
		          const resolvedConfig = activeManagedConfig(config);
		          const requestedDeviceIDs = normalizedDeviceConstraintValues(
		            nextConstraints && nextConstraints.deviceId
		          );
		          if (requestedDeviceIDs.length === 0) {
		            return originalApplyConstraints(nextConstraints);
		          }
		          const requestsOnlyManagedDevice = !!resolvedConfig.managedDeviceID
		            && requestedDeviceIDs.every(function(value) {
		              return value === resolvedConfig.managedDeviceID;
		            });
		          if (!requestsOnlyManagedDevice) {
		            const constraintError = makeManagedTrackConstraintError();
		            emitCameraRoutingEvent(
		              "managed-track-device-switch-rejected",
		              state,
		              resolvedConfig,
		              {
		                managedTrackID: managedTrackID,
		                requestedDeviceIDs: requestedDeviceIDs,
		                errorDescription: routingErrorDescription(constraintError)
		              }
		            );
		            return Promise.reject(constraintError);
		          }
		          if (!nextConstraints || typeof nextConstraints !== "object") {
		            return Promise.resolve();
		          }
		          const forwardedConstraints = { ...nextConstraints };
		          delete forwardedConstraints.deviceId;
		          if (Object.keys(forwardedConstraints).length === 0) {
		            return Promise.resolve();
		          }
		          return originalApplyConstraints(forwardedConstraints);
		        };
		      } catch (_) {}
		    }

		    if (originalClone) {
		      try {
		        track.clone = function() {
		          const clonedTrack = originalClone();
		          if (!clonedTrack) {
		            return clonedTrack;
		          }
		          return decorateManagedVideoTrack(
		            clonedTrack,
		            activeManagedConfig(config)
		          );
		        };
		      } catch (_) {}
		    }

		    if (originalStop) {
		      try {
		        track.stop = function() {
		          markManagedTrackStopped("track-stopped");
		          return originalStop();
		        };
		      } catch (_) {}
		    }

		    if (typeof track.addEventListener === "function") {
		      try {
		        track.addEventListener("ended", function() {
		          markManagedTrackStopped("track-ended");
		        });
		      } catch (_) {}
		    }

		    return track;
		  }

		  function decorateManagedStream(stream, config) {
		    if (!stream || stream.__navigatorCameraRoutingManagedStream) {
		      return stream;
		    }

		    const state = ensureManagedFrameState();
		    const managedStreamID = nextManagedIdentity(
		      state,
		      "nextManagedStreamSequence",
		      "navigator-camera-stream"
		    );
		    const originalGetVideoTracks = typeof stream.getVideoTracks === "function"
		      ? stream.getVideoTracks.bind(stream)
		      : null;
		    const originalGetTracks = typeof stream.getTracks === "function"
		      ? stream.getTracks.bind(stream)
		      : null;
		    const originalClone = typeof stream.clone === "function"
		      ? stream.clone.bind(stream)
		      : null;
		    try {
		      Object.defineProperty(stream, "__navigatorCameraRoutingManagedStream", {
		        configurable: true,
		        value: true
		      });
		      Object.defineProperty(stream, "__navigatorCameraRoutingManagedStreamID", {
		        configurable: true,
		        value: managedStreamID
		      });
		    } catch (_) {}
		    assignManagedRoutingMetadata(
		      stream,
		      makeManagedRoutingMetadata(activeManagedConfig(config), {
		        kind: "stream",
		        managedStreamID: managedStreamID
		      })
		    );

		    if (originalGetVideoTracks) {
		      try {
		        stream.getVideoTracks = function() {
		          return originalGetVideoTracks().map(function(track) {
		            return decorateManagedVideoTrack(
		              track,
		              activeManagedConfig(config)
		            );
		          });
		        };
		      } catch (_) {}
		    }

		    if (originalGetTracks) {
		      try {
		        stream.getTracks = function() {
		          return originalGetTracks().map(function(track) {
		            if (!track || track.kind !== "video") {
		              return track;
		            }
		            return decorateManagedVideoTrack(
		              track,
		              activeManagedConfig(config)
		            );
		          });
		        };
		      } catch (_) {}
		    }

		    if (originalClone) {
		      try {
		        stream.clone = function() {
		          const clonedStream = originalClone();
		          if (!clonedStream) {
		            return clonedStream;
		          }
		          return decorateManagedStream(
		            clonedStream,
		            activeManagedConfig(config)
		          );
		        };
		      } catch (_) {}
		    }

		    return stream;
		  }

		  function makeManagedNavigatorStream(constraints) {
		    const activeConfig = window[shimKey]?.config ?? nextConfig;
		    const permissionProbeConstraints = managedPermissionProbeConstraints(constraints, activeConfig);
		    const audioConstraints = constraints && typeof constraints === "object"
		      ? constraints.audio
		      : false;
		    return originalGetUserMedia(permissionProbeConstraints).then(function(permissionProbeStream) {
		      const state = ensureManagedFrameState();
		      if (!state.canvas || typeof state.canvas.captureStream !== "function") {
		        stopStreamTracks(permissionProbeStream);
		        return Promise.reject(makeRoutingUnavailableError());
		      }

		      const managedCanvasStream = state.canvas.captureStream(30);
		      const managedStream = typeof MediaStream === "function"
		        ? new MediaStream()
		        : managedCanvasStream;
		      const videoTracks = managedCanvasStream.getVideoTracks
		        ? managedCanvasStream.getVideoTracks()
		        : [];
		      const primaryVideoTrack = videoTracks.length > 0
		        ? decorateManagedVideoTrack(videoTracks[0], activeConfig)
		        : null;
		      if (!primaryVideoTrack) {
		        stopStreamTracks(permissionProbeStream);
		        return Promise.reject(makeRoutingUnavailableError());
		      }
		      if (managedStream !== managedCanvasStream && typeof managedStream.addTrack === "function") {
		        managedStream.addTrack(primaryVideoTrack);
		      }
		      if (
		        audioConstraints
		          && permissionProbeStream
		          && typeof permissionProbeStream.getAudioTracks === "function"
		          && typeof managedStream.addTrack === "function"
		      ) {
		        permissionProbeStream.getAudioTracks().forEach(function(track) {
		          managedStream.addTrack(track);
		        });
		      }
		      stopStreamTracks(permissionProbeStream, "video");
		      if (!audioConstraints) {
		        stopStreamTracks(permissionProbeStream, "audio");
		      }
		      return decorateManagedStream(managedStream, activeConfig);
		    }).catch(function(error) {
		      emitCameraRoutingEvent(
		        "permission-probe-failed",
		        ensureManagedFrameState(),
		        activeConfig,
		        { errorDescription: routingErrorDescription(error) }
		      );
		      return Promise.reject(error);
		    });
		  }

		  function normalizedConstraints(constraints, config) {
		    if (!config.routingEnabled || !config.preferNavigatorCameraWhenPossible || !config.preferredSourceID) {
		      return constraints;
		    }

		    const nextConstraints = cloneConstraints(constraints) ?? {};
		    const videoConstraints = nextConstraints.video;

		    if (videoConstraints === true || videoConstraints == null) {
		      nextConstraints.video = { deviceId: { exact: config.preferredSourceID } };
		      return nextConstraints;
		    }

		    if (typeof videoConstraints !== "object") {
		      return nextConstraints;
		    }

		    if (hasExplicitVideoDevice(videoConstraints)) {
		      return nextConstraints;
		    }

		    nextConstraints.video = {
		      ...videoConstraints,
		      deviceId: { exact: config.preferredSourceID }
		    };
		    return nextConstraints;
		  }

		  if (!mediaDevices || typeof mediaDevices.getUserMedia !== "function") {
		    window[shimKey] = {
		      version: shimVersion,
		      config: nextConfig,
		      unsupported: true,
		      receiveFrame: function() {},
		      clearFrame: function() {},
		      getManagedStream: function() {
		        return Promise.reject(makeRoutingUnavailableError());
		      },
		      applyConfig: function(updatedConfig) {
		        this.config = updatedConfig;
		        dispatchRoutingChange(updatedConfig);
		        return { ...this.config };
		      },
		      getConfig: function() {
		        return { ...this.config };
		      }
		    };
		    dispatchRoutingChange(nextConfig);
		    return "unsupported";
		  }

		  const existingShim = window[shimKey];
		  if (existingShim && existingShim.version === shimVersion) {
		    if (typeof existingShim.applyConfig === "function") {
		      existingShim.applyConfig(nextConfig);
		    } else {
		      const previousConfig = existingShim.config;
		      existingShim.config = nextConfig;
		      dispatchDeviceChangeIfNeeded(previousConfig, nextConfig);
		      dispatchRoutingChange(nextConfig);
		    }
		    return "updated";
		  }

		  const originalGetUserMedia = mediaDevices.getUserMedia.bind(mediaDevices);
		  const originalEnumerateDevices = typeof mediaDevices.enumerateDevices === "function"
		    ? mediaDevices.enumerateDevices.bind(mediaDevices)
		    : null;
		  window[shimKey] = {
		    version: shimVersion,
		    config: nextConfig,
		    originalGetUserMedia,
		    originalEnumerateDevices,
		    applyConfig: function(updatedConfig) {
		      const previousConfig = this.config;
		      this.config = updatedConfig;
		      dispatchDeviceChangeIfNeeded(previousConfig, updatedConfig);
		      dispatchRoutingChange(updatedConfig);
		      return { ...this.config };
		    },
		    receiveFrame: function(frame) {
		      const state = ensureManagedFrameState();
		      if (!frame) {
		        state.lastFrameSequence = 0;
		        drawPlaceholderFrame(state);
		        return;
		      }
		      if (!frame.imageDataURL || typeof Image !== "function") {
		        return;
		      }

		      const image = new Image();
		      image.onload = function() {
		        if (!state.canvas || !state.context) {
		          return;
		        }
		        if (frame.sequence && frame.sequence < state.lastFrameSequence) {
		          return;
		        }
		        state.lastFrameSequence = frame.sequence || state.lastFrameSequence;
		        const frameWidth = frame.width || image.naturalWidth || state.canvas.width;
		        const frameHeight = frame.height || image.naturalHeight || state.canvas.height;
		        if (frameWidth > 0 && frameHeight > 0
		          && (state.canvas.width !== frameWidth || state.canvas.height !== frameHeight)) {
		          state.canvas.width = frameWidth;
		          state.canvas.height = frameHeight;
		        }
		        state.context.drawImage(image, 0, 0, state.canvas.width, state.canvas.height);
		      };
		      image.src = frame.imageDataURL;
		    },
		    clearFrame: function() {
		      const state = ensureManagedFrameState();
		      state.lastFrameSequence = 0;
		      drawPlaceholderFrame(state);
		    },
		    getManagedStream: function(constraints) {
		      const activeConfig = activeManagedConfig(nextConfig);
		      return makeManagedNavigatorStream(constraints).then(function(stream) {
		        return decorateManagedStream(stream, activeConfig);
		      });
		    },
		    getConfig: function() {
		      return { ...this.config };
		    }
		  };

		  mediaDevices.getUserMedia = function(constraints) {
		    const activeConfig = window[shimKey]?.config ?? nextConfig;
		    const shouldUseManagedNavigatorRouting = activeConfig.genericVideoUsesManagedOutput
		      && requiresManagedVideoRouting(constraints, activeConfig);
		    const bypassedDeviceIDs = explicitBypassedDeviceIDs(constraints, activeConfig);
		    if (activeConfig.failClosedOnManagedVideoRequest
		      && shouldUseManagedNavigatorRouting) {
		      return Promise.reject(makeRoutingUnavailableError());
		    }
		    if (shouldUseManagedNavigatorRouting) {
		      return window[shimKey].getManagedStream(constraints);
		    }
		    if (activeConfig.routingEnabled
		      && activeConfig.preferNavigatorCameraWhenPossible
		      && bypassedDeviceIDs.length > 0) {
		      emitCameraRoutingEvent(
		        "explicit-device-bypassed",
		        ensureManagedFrameState(),
		        activeConfig,
		        { requestedDeviceIDs: bypassedDeviceIDs }
		      );
		    }
		    const routedConstraints = normalizedConstraints(constraints, activeConfig);
		    return originalGetUserMedia(routedConstraints).then(function(stream) {
		      try {
		        Object.defineProperty(stream, "__navigatorCameraRouting", {
		          configurable: true,
		          value: {
		            genericVideoUsesManagedOutput: activeConfig.genericVideoUsesManagedOutput,
		            managedRoutingAvailability: activeConfig.managedRoutingAvailability,
		            outputMode: activeConfig.outputMode,
		            healthState: activeConfig.healthState,
		            publisherState: activeConfig.publisherState,
		            publisherTransportMode: activeConfig.publisherTransportMode || null,
		            preferredFilterPreset: activeConfig.preferredFilterPreset
		          }
		        });
		      } catch (_) {}
		      return stream;
		    });
		  };

		  if (originalEnumerateDevices) {
		    mediaDevices.enumerateDevices = function() {
		      const activeConfig = window[shimKey]?.config ?? nextConfig;
		      return originalEnumerateDevices().then(function(devices) {
		        const annotatedDevices = devices.map(function(device) {
		          return annotateEnumeratedVideoDevice(device, activeConfig);
		        });
		        const managedDevice = makeManagedDeviceEnumerationEntry(activeConfig);
		        if (!managedDevice) {
		          return annotatedDevices;
		        }
		        const hasManagedDevice = annotatedDevices.some(function(device) {
		          return device && device.deviceId === managedDevice.deviceId;
		        });
		        if (hasManagedDevice) {
		          return annotatedDevices;
		        }
		        return annotatedDevices.concat([managedDevice]);
		      });
		    };
		  }

		  dispatchRoutingChange(nextConfig);

		  return "installed";
		})();
		"""
	}
}
