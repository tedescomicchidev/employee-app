Prepare release artefacts for $ARGUMENTS (version). Sources of truth: git
diff since the last tag, requirements, data inventory, existing metadata.
Distribution: Custom App via Apple Business Manager (or TestFlight only).
Produce in docs/release/: What's New (<= 4000 chars), description,
keywords (<= 100 bytes), App Review notes explaining enterprise Entra
sign-in and the reviewer account (no MFA, seeded data), TestFlight
"What to Test", privacy-label and privacy-manifest delta, screenshot
scenarios, export-compliance and age-rating answers, runbook updates.
Never invent features or privacy/accessibility claims. Mark anything
unverified HUMAN_CONFIRMATION_REQUIRED.
