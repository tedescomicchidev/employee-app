# Open accessibility findings (A11Y-002, A11Y-003)

Found by `ios/AppUITests/AccessibilityAuditTests.swift` (system accessibility audit, iPhone 17 simulator,
2026-10-19). Colour tokens are human-owned (`docs/design/tokens.md`), so none of these were changed by the
agent. The audit test lists each as a known finding; a new finding fails the test. Remove an entry from
`isKnown` when it is resolved.

| # | Screen | Element | Audit result | Likely cause / decision needed |
|---|---|---|---|---|
| F1 | News | language chips (DE, IT) | Contrast "nearly passed" | `DSStatusKind.info`/`.neutral` chip colours at footnote size; token pair needs 4.5:1 (A11Y-003). |
| F2 | News | author and date line, language chips | Dynamic Type "partially unsupported" | All fonts are text styles, so this may be an audit quirk for rows that hide their children from VoiceOver (`.accessibilityElement(children: .ignore)`); not confirmed on a device. |
| F3 | News | announcement preview at the largest text size | Text clipped | `lineLimit(2)` on the preview in `FeedView`; the full text is one tap away, so decide whether the preview counts as critical content (A11Y-002). |
| F4 | Vacation | "My requests" row | Contrast **failed** | Not confirmed which token pair; needs a design check. |
| F5 | More | avatar initials "AM"; debug button | Contrast "nearly passed" | Avatar token pair. The debug button exists in DEBUG builds only. |

Passing in the same run: element descriptions (A11Y-001) and hit regions (A11Y-005) on News, Vacation,
Week, More and Approvals. A11Y-004 (Reduce Motion, Bold Text, Increase Contrast, Reduce Transparency) is
not covered.
