Implement $ARGUMENTS (one requirement ID). Start in plan mode: list files,
risks, tests, verification; wait for my approval.
Scope: only what the acceptance criteria demand, in the mode(s) named.
Include: loading/empty/error/offline states per screen-state matrix;
VoiceOver labels; Dynamic Type; DE/FR/IT/EN strings; experiment events per
docs/experiment/metrics.md; domain rules in api/ only.
Verify: unit tests + narrowest useful UI or API test; ./scripts/ci-check.sh;
./scripts/screenshot.sh for affected screens (light, dark, largest text)
and inspect the images. Fix failures you caused.
Finish: re-read the diff against the acceptance criteria, commit, push the
phase-* branch, open a PR whose description lists requirement IDs,
evidence, and anything you could not verify. Never merge.
