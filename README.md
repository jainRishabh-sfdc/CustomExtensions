# RPM Command — Salesforce core (Option B)

Remote patient monitoring for commercial / non-ACCESS RPM patients, built as a Salesforce 2GP managed package so any clinic can run it and any EMR can connect to it.

This drop is the backend core. No UI yet.

## What's in it

Data model (`force-app/main/default/objects`)
1. RPM_Patient__c — patient synced from the EMR (external id `EMR_Patient_Id__c`), consent date, billing lock (double-billing guard), BP targets, risk level
2. RPM_Device__c — cuff/scale by IMEI, stock status, battery, signal, last reading
3. RPM_Device_Assignment__c — who held which device and when, plus the handout checklist
4. RPM_Reading__c — each measurement, raw payload kept, dedupe by vendor event id
5. RPM_Alert__c — alert with severity, rule, 6-step workflow, SLA due time, protocol version, call record
6. RPM_Alert_Event__c — append-only history (update/delete blocked by trigger)
7. RPM_Time_Entry__c — care minutes, interactive-communication flag
8. RPM_Billing_Period__c — monthly reading-days, minutes, eligible CPT codes
9. RPM_Protocol__mdt — alert thresholds per clinic (Default record included)

Apex (`classes`)
1. RpmReadingApi — `POST /services/apexrest/rpm/v1/readings` (one object or array of up to 200)
2. RpmReadingService — validate, dedupe, match reading to patient at measurement time, update device telemetry
3. RpmAlertEngine — critical / high / low systolic, rising trend, silent device, low battery
4. RpmAlertWorkflow — New → Checked → Assigned → Patient Called → Provider Reviewed → Closed; critical needs the full call record
5. RpmBillingEngine — 99453, 99454, 99445, 99470, 99457, 99458 (rules version CPT-2026.1)
6. RpmRiskService — GREEN / YELLOW / RED
7. RpmNightlyBatch — nightly device check, billing recalc, risk refresh
8. Tests for all of the above (RpmTestFactory + 6 test classes)

Permission sets: RPM_Admin, RPM_Clinician, RPM_Integration.

Console UI (`lwc`, `tabs`, `applications`)
1. RPM Command app with the "RPM Command" console tab plus RPM Patients and RPM Devices object tabs
2. rpmConsole — shell with five boards: Today, Patients, Alerts, Devices, Billing
3. rpmToday — clickable KPIs and the to-do list (critical first, then by due time)
4. rpmPatients — roster with risk, BP chart (rpmBpChart), readings, stats, care-time logging, monthly billing card
5. rpmAlerts — six-step cards with the next action on each; critical call form (rpmCallModal)
6. rpmDevices — devices with patients, office stock, 4-step handout checklist (rpmHandoutModal), returns
7. rpmBilling — reading days, minutes, eligible codes and status per patient
8. RpmConsoleController (+ test) — the Apex behind the console
9. Look: Day / Night shift toggle (remembered per browser), care-time stopwatch in the header ("Log it" fills the minutes on the open patient), shared colour tokens in rpmConsole.css, building blocks in rpmStyles, modal look in rpmModalStyles
10. rpmFonts static resource — Plus Jakarta Sans and JetBrains Mono (SIL Open Font License), loaded by rpmConsole

## Run it

```bash
sf org login web --set-default-dev-hub --alias devhub
sf org create scratch --definition-file config/project-scratch-def.json --alias rpm --set-default --duration-days 30
sf project deploy start
sf org assign permset --name RPM_Admin
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20
```

Schedule the nightly job (Anonymous Apex):

```apex
System.schedule('RPM nightly', '0 0 2 * * ?', new RpmNightlyBatch());
```

## Post a reading

```bash
sf api request rest /services/apexrest/rpm/v1/readings --method POST --body '{
  "eventId":"sm-88123","imei":"356938035643809","measuredAt":"2026-08-09T07:41:00Z",
  "type":"Blood Pressure","systolic":181,"diastolic":112,"pulse":96,"battery":91,"signal":-69}'
```

Response: `{"received":1,"created":1,"duplicates":0,"unmatched":0,"alertsRaised":1,"errors":[]}`

## Things to verify before go-live

1. Billing rules — re-check against the CY2027 final rule and each commercial payer. Per-payer overrides are not built yet.
2. Alert thresholds — the Default protocol (150 call line, 180 emergency) must be signed off by the client's medical director.
3. Device vendor payload — Smart Meter's webhook format must be mapped to `RpmReadingInput` in the gateway; the gateway is not in this repo.
4. Namespace — set `namespace` in `sfdx-project.json` once you register one in a namespace org, before creating the first package version.

## Next builds

1. Device orders (bulk to office / direct to patient) and vendor RMA tracking
2. Notes / outreach log and audit exports (PDF / CSV)
3. Device gateway (AWS Lambda) for Smart Meter webhooks
4. EMR connectors: CSV patient import first, then Epic / athena FHIR
5. Per-payer billing rules
