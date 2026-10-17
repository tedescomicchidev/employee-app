# Employee App PoC: brief
Company: Swiss retailer, 100 employees, stores + HQ, languages DE/FR/IT (+EN).
Goal: prove (1) Work IQ works from a custom iOS app, (2) Foundry agents let
employees reach the same outcomes faster than classic forms/feeds.
Users: CEO/Comms (publish), Employees (read, vacation), Managers (approve).
Features, each in CLASSIC and AGENT mode:
  1. Company announcements (CEO -> all / by region, store, role).
  2. Vacation: balance, request, approve, team coverage, cantonal holidays.
  3. Optional weekly briefing from my own calendar via Work IQ.
Measure: time on task, taps, errors, completion, satisfaction, cost/task.
Constraints: Entra ID sign-in; Azure Switzerland North where available;
  azd-deployable; iOS 17+; distribution as Custom App via Apple Business Manager.
Out of scope: sick leave/health data, payroll, Android, Teams client.
Demo tenant: m365cpi55218196.onmicrosoft.com; seeded users: CEO, 2 managers, 8 employees.
