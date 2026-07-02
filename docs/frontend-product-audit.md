# ARTH Frontend Product Audit

Audience: Indian salaried taxpayers, age 25-45. Goal: premium, trust-first tax
intelligence app that demonstrates product thinking without weakening privacy.

## Product Direction

ARTH should feel like a serious finance product, not a tax calculator demo.
The first session must prove four things quickly:

- ARTH finds missed deductions without PAN or ITR uploads.
- User data is treated carefully and can be deleted.
- The diagnostic is short, guided, and worth completing.
- Results turn into next actions, not just a number.

## Screen Audit

| Screen | Current role | Main issue | Priority fix |
|--------|--------------|------------|--------------|
| Splash | Session routing | Good but slow at 2.5s and visually thin | Faster brand pulse, premium status copy |
| Auth | Account creation/sign-in | Form-first, weak product/trust framing | Member-style access screen with trust rail |
| Welcome | Product promise | Single static pitch, no swipe narrative | 3-card trust story: savings, no PAN, 3-min diagnostic |
| Questions | Tax diagnostic | Long list feels mechanical; weak section context | Sectioned diagnostic with stable chrome and help copy |
| Gap Reveal | Result moment | Strong reveal, but not yet a dashboard | Convert into Tax Cockpit with next best action |
| Regime Comparison | Utility module | Dense and isolated | Make it a cockpit insight card plus detailed drilldown |
| Deduction Cards | Gap list | Useful but table-like | Premium cards, urgency, evidence, progress cues |
| Deduction Detail | Action detail | Needs stronger decision hierarchy | Clear why/what/how, deadline, evidence checklist |
| Action Plan | To-do list | Useful but not motivating | Next-best-action queue with progress and impact |
| Progress Tracker | Completion view | Timeline utility exists but low emotional pull | FY progress, upcoming deadlines, completion streak |
| Share Card | Virality/demo | Fine utility, needs polish | Premium summary card and safe copy |
| Settings | Account/privacy | Strongest screen today; some copy overclaims | Keep deletion visible, tighten privacy language |
| Budget Alert | Future module | Feels separate from tax journey | Recast as future tax habit feature |

## State Audit

| State | Current pattern | Issue | Target |
|-------|-----------------|-------|--------|
| Loading | Mostly spinners | Dead time, low trust | Skeletons, branded progress, short tax insights |
| Error | Retry widget exists | Good base, inconsistent placement | One premium empty/error/offline system |
| Empty | Some screens handle zero gaps | Needs consistent action path | Explain state, show next useful action |
| Offline | Sync fallback exists | UI does not always explain source | Sync badge: saved locally / synced / retrying |
| Narrow phone | Widget tests exist | Needs stronger real-screen constraints | 320px QA with stable buttons/nav/cards |
| Reduced motion | Not explicit | Animations may feel heavy on low-end Android | Respect disableAnimations and shorten motion |

## Priority Backlog

1. Add premium design primitives: scaffold, app bar, metric cards, trust badges,
   skeletons, state panels, and branded loading.
2. Rebuild splash/auth/welcome as trust-first onboarding.
3. Reframe questions as a guided tax diagnostic with section context.
4. Convert gap reveal into Tax Cockpit while keeping existing result routes.
5. Harmonize modules with a 4-tab mental model: Discover, Actions, Progress,
   Profile.
6. Add narrow-phone and reduced-motion widget coverage.

## Guardrails

- No PAN capture in this phase.
- No document upload, no new sensitive storage, no backend API change.
- No tax engine or tax data edits.
- No fake feature claims. Future modules must be labelled as coming soon.
- Prefer clarity and performance over decorative glass.
