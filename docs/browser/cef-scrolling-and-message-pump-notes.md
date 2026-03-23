# CEF Scrolling and Message Pump Notes

## Purpose

This document captures the recent investigation into why Navigator’s page scrolling looked materially worse than Chrome on some image-heavy pages, and why the final fix is a hybrid scheduler instead of a pure external-message-pump implementation.

It exists so future engineers do not have to rediscover the same facts by reading git history or re-running the same experiments.

## Problem Summary

Navigator was rendering and scrolling some pages worse than Chrome, especially when:

- a page was loading many large assets
- the user started scrolling immediately after first load
- the page was doing sustained compositor work during scroll

The initial symptom looked like generic “CEF scroll jank,” but the actual behavior was more specific:

- with the old integration, scrolling felt quantized compared to Chrome
- with a pure external-message-pump experiment, the page would often bootstrap and render correctly
- the first scroll could work briefly and then stall until some other event, such as switching tabs, woke the browser again

## Key Setup Difference Versus Chrome

Before this work, Navigator drove CEF with a fixed local timer via `cef_do_message_loop_work()`.

That differed from Chrome’s normal model in an important way:

- Chrome lets Chromium schedule browser-process work itself
- Navigator quantized browser/compositor/input progress onto a host timer

That difference matters most under active input and heavy compositor load.

## Experiments Run

### 1. External message pump

We added a browser-process `cef_app_t` wrapper and implemented `CefBrowserProcessHandler::OnScheduleMessagePumpWork`.

The initial experiment switched Navigator to:

- `external_message_pump = 1`
- no always-on fixed Swift timer
- CEF-requested wakeups scheduled on the AppKit main thread

This improved parity with Chrome in principle, but it exposed a second issue.

### 2. Bootstrap wakeup fixes

The first version of the external-pump experiment could leave the browser on a blank white surface because the scheduler was not always kicked promptly enough during bootstrap.

We fixed that by forcing an immediate pump:

- after successful CEF initialization
- after native browser creation

That resolved the blank-surface bootstrap issue.

### 3. Host clipping A/B

We also tested whether host-view clipping and rounded-corner composition were the primary cause of the regression.

Result:

- disabling clipping was useful as an A/B diagnostic
- it was not the root cause of the stall
- normal rounded/clipped browser presentation was restored as the default

## Root Cause of the Remaining Scroll Stall

The remaining bug was:

- first scroll worked for a short time
- scrolling then stopped
- switching tabs away and back revived it

The logs showed:

- the page loaded fully
- title, favicon, and address callbacks all arrived
- the renderer did not crash

That pointed away from rendering failure and toward scheduler starvation.

The most likely explanation is:

- pure external pumping was good enough to bootstrap and load the page
- but in this embed, CEF/Chromium did not reliably continue scheduling wakeups during the first active input/compositor session
- once those wakeups stopped, Navigator had no fallback and the browser stopped making scroll progress

Tab switching likely revived the browser because it generated enough browser activity to restart scheduling.

## Current Design

Navigator now uses a hybrid approach.

### Primary scheduler

External CEF pumping remains the primary scheduler:

- CEF requests work through `OnScheduleMessagePumpWork`
- Navigator schedules the requested wakeup on the AppKit main thread

### Fallback watchdog

Navigator also runs a short-lived local fallback pump during recent activity.

Current behavior:

- browser activity refreshes a fallback window
- while that window is active, Navigator continues calling `CEFBridge_DoMessageLoopWork()`
- when activity stops, the watchdog naturally falls away

This keeps the external pump as the main path while preventing the browser from starving during active scrolling if CEF stops asking for wakeups transiently.

## Why This Is a Workaround

This is intentionally pragmatic, not architecturally pure.

It is a workaround because:

- a perfectly behaving external-pump integration would not need a watchdog
- the fallback window is tuned behavior rather than a hard upstream contract
- the design compensates for a scheduling gap instead of fully explaining it

It is still the right current tradeoff because:

- it fixes a real user-visible regression
- it is narrow in scope
- it preserves most of the benefit of external pumping
- it is safer than returning to permanent fixed-rate pumping for all cases

## Current Files of Interest

- [BrowserRuntime.swift](/Users/rk/Developer/Navigator/BrowserRuntime/Sources/BrowserRuntime/BrowserRuntime.swift)
  - host-side fallback watchdog and runtime activity tracking
- [MiumCEFBridgeNative.mm](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/MiumCEFBridgeNative.mm)
  - external-pump bridge, browser-process app wrapper, bootstrap kicks, and scheduling
- [CEF_THREADING.md](/Users/rk/Developer/Navigator/MiumKit/Sources/MiumKit/CEF_THREADING.md)
  - thread-ownership and main-thread CEF invariants

## Commits

The work landed in two main commits:

- `95bcbdcc4` — `Add experimental external CEF message pump`
- `efe19f8f1` — `Add fallback pump for external CEF scheduling`

## Follow-Up Questions

If we want to reduce the workaround over time, the next questions to answer are:

- why pure external pumping under-schedules active scroll/compositor work in this embed
- whether specific CEF callbacks or browser focus/visibility transitions should refresh the fallback window more precisely
- whether the fallback window should be shorter, adaptive, or display-linked
- whether there is a more principled hybrid model recommended for macOS CEF windowed rendering in this exact integration shape
