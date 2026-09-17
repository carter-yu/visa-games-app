# ADR 0001 — Native macOS kiosk boundary

Status: Accepted for bootstrap

## Context

The original Visa Games browser app proved the core ritual but exposed browser-controlled escape paths: document-fullscreen exit affordances, browser tabs/navigation, and YouTube embed UI outside the app's control.

## Decision

Build the successor as a native macOS application using Swift with SwiftUI and AppKit where needed.

The native app will:

- own the top-level window;
- support borderless/fullscreen kiosk presentation;
- hide normal app chrome during child mode;
- avoid exposing a general browser view;
- keep parent controls behind a parent-authenticated boundary;
- persist app state locally;
- treat visa expiry as an absolute timestamp;
- expose approved media through a controlled playback surface;
- log remaining platform escape paths during development.

## Security boundary

The app is responsible for its own process and windows. It is **not** treated as a complete macOS device-management boundary.

For household deployment, the intended stack is:

1. Visa Games native app;
2. dedicated non-admin macOS child user;
3. macOS Screen Time / parental restrictions as appropriate;
4. startup/login configuration that launches Visa Games automatically;
5. no ordinary browser or unrelated apps available to the child account where practical.

If stronger guarantees are later required, evaluate managed-device / MDM single-app capabilities separately.

## Consequences

- We do not carry forward browser fullscreen re-entry hacks as core architecture.
- We do not rely on hiding browser-owned UI with CSS overlays.
- Media integration must be evaluated against native playback and provider policy constraints.
- The first phase is a native shell and kiosk-state test, not a feature-for-feature rewrite.
