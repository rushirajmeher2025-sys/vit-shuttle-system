# VIT Shuttle System — Antigravity Implementation Prompts
## Responsive UI/UX Improvement Plan

This document contains a project-wide instruction prompt and seven phase-specific prompts for improving the existing VIT Shuttle System web application with Google Antigravity.

## How to use this document

1. Open the existing VIT Shuttle System project/repository in Antigravity.
2. Send the **Project Rules / Initial Audit** prompt first.
3. Review Antigravity's audit before making changes.
4. Send **one phase prompt at a time**, in order.
5. Review the changes, run the checks, and test the affected pages before starting the next phase.
6. If a phase introduces a regression, fix it before continuing.

Do not ask Antigravity to implement all phases at once.

---

# PROMPT 0 — PROJECT RULES AND INITIAL AUDIT

You are improving my existing VIT Shuttle System web application. This is an iterative improvement project, not a request to rebuild the application from scratch.

## 1. Inspect before editing

Before changing any code:

- Inspect the repository, folder structure, framework, routing, styling system, reusable components, and available scripts.
- Identify the existing student, faculty, and driver portals.
- Understand the current map, shuttle information, navigation, and authentication flows.
- Identify existing functionality that must be preserved.
- Check whether a responsive design system, breakpoints, or shared design tokens already exist.
- Identify the files likely to be affected by the requested phase.
- Report your findings and proposed approach before making broad changes.

Do not assume the framework, libraries, APIs, or architecture without inspecting the code.

## 2. Preserve existing functionality

- Do not rebuild the application from scratch.
- Do not remove existing features simply to make the UI easier to implement.
- Do not replace functional integrations with hardcoded examples.
- Do not change backend APIs, authentication logic, database schemas, or routing unless the requested phase genuinely requires it.
- Reuse existing components and dependencies wherever practical.
- Avoid unnecessary dependencies and unrelated refactoring.
- Preserve the existing application identity and VIT Shuttle System branding.

## 3. Responsive design requirements

Build mobile-first, responsive layouts that adapt to available viewport dimensions. Do not rely exclusively on detecting whether the device is a phone, tablet, or laptop.

Use responsive CSS, flexible layouts, suitable breakpoints, and feature-appropriate behaviour. The application must remain usable on narrow phones, large phones, tablets, laptops, and large desktop displays.

Prevent horizontal overflow, overlapping elements, clipped content, awkward empty space, and controls that are too small to use comfortably. Ensure interactive maps resize correctly when their containers or layouts change.

## 4. Data integrity and security

- Do not invent live shuttle locations, ETAs, crowd levels, driver information, or operational statistics.
- Preserve existing real integrations.
- If the application uses mock or demonstration data, label it clearly.
- Never imply that simulated data is connected to a live system.
- Do not expose API keys, credentials, tokens, or other secrets.
- Do not weaken authentication or authorization to make a UI demo easier.

## 5. Implementation and verification

For every phase:

1. Inspect the relevant implementation.
2. Identify the smallest sensible set of changes.
3. Implement only the requested phase.
4. Reuse the existing design system and components.
5. Run available linting, build, type-checking, and tests where applicable.
6. Test affected pages at relevant viewport sizes using available browser tools.
7. Fix regressions caused by the changes.
8. Summarize files changed, improvements made, checks actually run, and unresolved issues.

Do not claim a test passed unless it was actually executed successfully. If a check cannot be run, state that clearly.

## 6. Scope control

Complete one phase at a time. Do not automatically begin the next phase. Do not make unrelated changes simply because you notice other possible improvements; list them separately as suggestions.

If a decision could break an existing feature, inspect the code and choose the safest compatible approach. If a required service or integration is unavailable, do not fabricate its behaviour.

The goal is a polished, consistent, accessible, responsive, and reliable VIT Shuttle System—not merely a visually attractive mockup.

## Initial audit task

For now, perform an audit only. Do not modify files yet.

Return:
- The detected framework, application structure, and run/build commands.
- A brief description of the current portals and key user flows.
- Existing responsive-design strengths and weaknesses.
- Potentially fragile areas, especially maps, navigation, authentication, and data integrations.
- The files/components most likely to need changes in Phase 1.
- A short, prioritized implementation plan.

Wait for me to review the audit before implementing Phase 1.

---

# PHASE 1 — RESPONSIVE DESIGN SYSTEM AND FOUNDATION

Using the project rules and your audit, improve the responsive design foundation of the existing application.

## Goals

- Create a consistent visual system without changing the app's identity.
- Make shared layouts and components adapt to viewport width.
- Avoid duplicate, conflicting styles.
- Preserve existing behaviour and integrations.

## Instructions

1. Inspect the current CSS/styling approach and identify existing shared styles, tokens, and components.
2. Reuse and consolidate existing conventions where practical; do not introduce a second design system unnecessarily.
3. Establish or refine shared design tokens for:
   - Typography scale and line heights.
   - Spacing scale.
   - Border radius.
   - Borders and shadows.
   - Surface, text, and status colours, maintaining sufficient contrast.
   - Content widths and layout spacing.
4. Use fluid sizing where suitable, such as `min()`, `max()`, `clamp()`, flexible grids, and responsive containers.
5. Define breakpoints based on where the layout needs to change, not on assumptions about a specific device model.
6. Ensure forms, buttons, cards, tables, modals, sidebars, and navigation can shrink, wrap, scroll, or transform appropriately.
7. Prevent horizontal overflow, overlapping content, fixed-width layout failures, and text clipping.
8. Respect safe-area insets on supported mobile devices where relevant.
9. Keep touch targets comfortable and make focus states visible.
10. Do not redesign every page in this phase. Focus on shared foundations and the minimum components needed to support later phases.

## Verification

Check representative existing pages at:
- 360 × 800
- 390 × 844
- 768 × 1024
- 1366 × 768
- 1920 × 1080

Check intermediate widths if possible. Run available project checks and fix issues caused by this phase.

## Completion report

List the files changed, design tokens or shared components introduced/updated, viewport checks performed, test results, and any remaining issues. Do not begin Phase 2.

---

# PHASE 2 — RESPONSIVE LANDING PAGE AND PORTAL ENTRY

Improve the existing landing page and portal-selection experience using the responsive foundation from Phase 1.

## Goals

- Make the landing page clear, polished, and easy to use on every screen size.
- Help users understand and enter the appropriate portal.
- Preserve current routes, links, authentication, and branding.

## Instructions

1. Inspect the existing landing page and identify its current content, actions, portal cards, and navigation.
2. Preserve useful content and working destinations. Do not invent new services or claim capabilities that do not exist.
3. On desktop, use balanced content widths, clear hierarchy, and well-spaced portal cards.
4. On tablets, reduce columns and spacing where needed without making text or controls cramped.
5. On mobile, use a clear single-column or otherwise appropriate layout, readable headings, full-width controls when useful, and sensible spacing.
6. Ensure student, faculty, and driver portal entry points remain clear and accessible.
7. Make primary actions visually distinct, with visible hover, focus, active, and disabled states where applicable.
8. Ensure headers, footers, logos, and decorative elements do not cause overflow or crowd the main actions.
9. Avoid excessive animation, oversized hero sections, and decorative effects that slow down or obstruct use.
10. Preserve all existing links, route handling, and authentication requirements.

## Verification

Test the landing page at mobile, tablet, laptop, and desktop sizes. Test every portal entry point and any existing sign-in or navigation action. Check keyboard navigation, text contrast, and horizontal overflow.

## Completion report

Summarize the landing-page changes, routes/actions tested, viewport sizes checked, and unresolved issues. Do not begin Phase 3.

---

# PHASE 3 — STUDENT DASHBOARD AND SHUTTLE MAP

Improve the student-facing dashboard and map. Prioritize information clarity, responsive behaviour, and reliable interactions over decoration.

## Goals

- Make shuttle and stop information easy to understand.
- Provide a layout that works naturally on desktop and mobile.
- Preserve existing map, route, stop, ETA, and location integrations.
- Clearly distinguish real information from demonstration data.

## Instructions

1. Inspect the current student dashboard, map library, stop markers, shuttle markers, route details, and associated data flow before editing.
2. Preserve existing working map and data integrations. Do not replace them with a static image or fabricated live data.
3. For desktop, use an efficient layout that can show map content alongside relevant stop, route, or shuttle details without unnecessarily compressing the map.
4. For mobile, consider a map-first layout with an accessible expandable bottom sheet or panel for stops, shuttle details, and journey information, if compatible with the existing architecture.
5. Ensure the mobile panel does not permanently hide important map content or cover essential controls. Support opening, closing, expanding, and collapsing it using accessible controls.
6. Ensure map dimensions and rendering update correctly when a sidebar or bottom sheet opens, closes, or changes size. Use the map library's proper resize/invalidation mechanism if required.
7. Prevent map controls, markers, popups, legends, and attribution from overlapping or becoming inaccessible on small screens.
8. Make stop and shuttle details readable, with clear labels and status indicators.
9. Show ETAs, vehicle positions, occupancy/crowding, and service status only when supported by actual available data. If data is mock, stale, or unavailable, clearly communicate that state.
10. Provide useful loading, empty, unavailable, and error states. Do not display a fabricated successful result when a request fails.
11. Make important actions usable with touch, keyboard, and screen readers where practical.
12. Avoid adding new backend behaviour or changing data models unless essential. If a feature cannot be completed with the current backend, implement an honest UI state and report the dependency.

## Verification

- Test map rendering and interaction at mobile, tablet, laptop, and desktop sizes.
- Open and close any responsive panel and verify the map resizes correctly.
- Test marker selection, stop details, existing route actions, and location controls where available.
- Check map loading, empty, and error states where they can be reproduced.
- Confirm no false claims of live data and no horizontal overflow.

## Completion report

List changed components, existing integrations preserved, interactions tested, viewport sizes checked, and any backend/data limitations. Do not begin Phase 4.

---

# PHASE 4 — ADAPTIVE NAVIGATION AND SHARED INTERACTION PATTERNS

Improve navigation across the application so that users can move between relevant pages and actions easily on desktop and mobile.

## Goals

- Make navigation consistent and predictable across portals.
- Adapt navigation to available space.
- Preserve role boundaries, routes, and authentication.

## Instructions

1. Inspect existing navigation components and route structure before changing them.
2. Reuse a shared navigation component where appropriate, but do not force student, faculty, and driver portals to share navigation items that should differ.
3. On wider screens, retain an appropriate horizontal navigation or sidebar layout according to the existing design.
4. On narrow screens, use a compact menu, drawer, or bottom navigation only where suitable for the app's information architecture.
5. Do not place too many items in a mobile bottom navigation. Keep only the most important destinations there and put secondary items in an accessible menu.
6. Clearly indicate the active route and preserve current route destinations.
7. Ensure menus can be opened and closed using touch and keyboard, have correct accessible labels, and do not trap focus incorrectly.
8. Close overlays when appropriate after navigation, and handle Escape where suitable.
9. Avoid navigation that obscures the map, important page content, or primary actions.
10. Maintain sensible behaviour during browser resizing and orientation changes.
11. Preserve authentication and authorization checks. Do not expose portal-only pages or actions to unauthorized users.

## Verification

Test all relevant navigation items and role-specific destinations. Check active states, keyboard controls, mobile menu opening/closing, browser resizing, and direct navigation to existing routes. Run available checks.

## Completion report

Summarize navigation changes, routes tested, responsive behaviour checked, and any unresolved issues. Do not begin Phase 5.

---

# PHASE 5 — RESPONSIVE DRIVER CONSOLE

Improve the existing driver console while prioritizing operational clarity, safe interaction, and preservation of existing functionality.

## Goals

- Make essential route, shift, and shuttle information easy to scan.
- Ensure controls remain usable on supported screen sizes.
- Avoid clutter and misleading operational information.

## Instructions

1. Inspect the existing driver console, available data, actions, and current permission checks.
2. Preserve existing driver workflows and backend integrations.
3. Present the most important supported information—such as current route, shift status, next stop, or vehicle status—with a clear visual hierarchy.
4. Do not invent telemetry, shift state, route progress, or live vehicle status. Clearly label demo or unavailable data.
5. Use a responsive card/grid layout on wide screens and a simple stacked layout on narrow screens.
6. Keep essential actions easy to identify, with sufficient spacing and clear labels.
7. Use confirmation or undo patterns for consequential actions where appropriate and compatible with the existing workflow.
8. Avoid tiny controls, dense tables that cannot be used on phones, distracting animations, and unnecessary decoration.
9. Make status information understandable without relying on colour alone.
10. Preserve authorization checks and avoid changing operational logic unless specifically required.
11. Do not encourage complex interaction while a vehicle is moving. Keep the interface simple and aligned with safe operational use.

## Verification

Test the console at mobile, tablet, laptop, and desktop sizes. Test existing actions where safe and possible, check loading/error states, confirm role restrictions, and ensure no misleading live-data claims are introduced.

## Completion report

List the changes, workflows and permissions checked, viewport sizes tested, and remaining issues. Do not begin Phase 6.

---

# PHASE 6 — RESPONSIVE FACULTY PORTAL

Improve the faculty portal while maintaining its existing purpose, routes, data, and access controls.

## Goals

- Make the portal readable and efficient on desktop and mobile.
- Present existing shuttle, route, stop, or service information clearly.
- Keep the experience visually consistent with the rest of the application.

## Instructions

1. Inspect the existing faculty portal and identify its current features, information hierarchy, data sources, and permissions.
2. Preserve existing features and integrations. Do not add unverified capabilities or invent institutional data.
3. Use a clear page hierarchy, readable headings, consistent spacing, and appropriately grouped information.
4. On desktop, use columns or tables when they improve scanning and comparison.
5. On mobile, stack content or provide deliberate, accessible horizontal scrolling for wide data tables. Do not shrink text until it becomes unreadable.
6. Make forms, filters, search, status indicators, and actions adapt to narrow screens.
7. Provide useful loading, empty, error, and unavailable states.
8. Keep faculty-only information and actions protected by existing authorization logic.
9. Reuse the shared design tokens and components established in earlier phases.
10. Avoid adding unrelated features or changing the backend schema.

## Verification

Test faculty portal pages and existing actions at mobile, tablet, laptop, and desktop sizes. Check data states, permissions, keyboard navigation, and horizontal overflow.

## Completion report

Summarize the changes, routes and actions tested, viewport sizes checked, and any remaining issues. Do not begin Phase 7.

---

# PHASE 7 — RESPONSIVE QA, ACCESSIBILITY, AND REGRESSION AUDIT

Perform a focused quality pass across the existing application after Phases 1–6. This phase is for identifying and fixing issues within the agreed scope, not for adding a new redesign or unrelated features.

## 1. Viewport checks

Inspect the landing page and all relevant student, faculty, and driver portal screens at these viewport sizes:

- 360 × 800
- 390 × 844
- 768 × 1024
- 1366 × 768
- 1920 × 1080

Also check intermediate widths and portrait/landscape orientation where available.

These are test viewports, not rigid device categories. The UI should adapt smoothly between them.

## 2. Responsive layout audit

Check for:

- Horizontal page overflow.
- Overlapping or clipped text and components.
- Fixed-width elements that break narrow layouts.
- Unusable or obscured controls.
- Excessively narrow content or wasted space.
- Menus, dialogs, dropdowns, and bottom sheets that extend beyond the viewport.
- Tables that become unreadable on mobile.
- Map containers, markers, popups, controls, and attribution that fail to resize or overlap.
- Layout issues after browser resizing or orientation changes.

Fix issues introduced by the prior phases and any clear responsive defects within the agreed scope.

## 3. Accessibility checks

Check:

- Semantic headings and page structure.
- Labels for inputs and accessible names for icon-only controls.
- Keyboard navigation and visible focus states.
- Sufficient text and control contrast.
- Meaningful status labels that do not depend on colour alone.
- Usable touch targets and spacing.
- Dialog/menu focus behaviour and Escape handling where appropriate.
- Respect for reduced-motion preferences where animations exist.
- Text zoom and browser zoom where testable.

## 4. Functional regression checks

Verify the existing core flows, as applicable:

- Landing page and portal navigation.
- Existing authentication and role restrictions.
- Student dashboard and map interactions.
- Stop and shuttle details.
- Existing route or journey actions.
- Driver console actions that can safely be tested.
- Faculty portal actions.
- Loading, empty, unavailable, and error states.

Do not fabricate external service responses or mark an integration as working unless it was actually tested.

## 5. Technical checks

Run available linting, type checks, tests, and production build commands. Inspect the browser console and network errors if available. Fix regressions caused by the work. Do not hide errors by disabling lint rules or weakening type checks without a justified, documented reason.

## 6. Final report

Provide:
- A concise summary of fixes.
- Files changed.
- Viewports and pages actually tested.
- Commands and tests actually run, including pass/fail results.
- Known issues and limitations.
- Any recommendations that would require backend or infrastructure work.

Do not claim complete coverage if any pages, sizes, or checks could not be tested.

---

# OPTIONAL PROMPT — FIX A REGRESSION WITHOUT EXPANDING SCOPE

Use this if a phase breaks something:

A regression appeared after the most recent phase. Inspect the changes from that phase and identify the smallest safe correction. Preserve unrelated work and existing functionality. Reproduce the issue if possible, fix the root cause rather than hiding the symptom, and run the relevant checks again. Do not proceed to the next phase. Report the root cause, files changed, and verification performed.

# OPTIONAL PROMPT — REVIEW BEFORE APPLYING CHANGES

Use this if you want Antigravity to propose a plan first:

Review the requested phase against the current codebase. Do not edit files yet. Identify the exact files/components to change, the proposed approach, any risks to existing functionality, and how you will verify the result. Keep the plan limited to this phase and wait for my approval before implementation.
