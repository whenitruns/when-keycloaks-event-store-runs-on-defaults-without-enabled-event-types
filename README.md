# When Keycloak's Event Store Runs on Defaults Without `enabled_event_types` — reproduction

When It Runs — Run Report #RR07 · Testing what infrastructure actually does.

Run Report: https://whenitruns.substack.com/p/when-keycloaks-event-store-runs-on

This repository holds the reproduction from the report above: the OpenTofu configuration printed in its §4 (Reproduction), byte for byte, and the commands its §4 prints, run one step at a time. Nothing here adds versions, configurations, or findings beyond the report.

## Setup pinned in the report

- Keycloak 26.7.4 from the official image `quay.io/keycloak/keycloak:26.7.4`, pinned by digest (`sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c`), in `start-dev` mode with the bootstrap-admin variables and the log level `INFO,org.keycloak.events:debug`.
- The keycloak provider v5.9.0 (`keycloak/terraform-provider-keycloak`), applied with OpenTofu 1.12.6; `curl` and `jq` for the REST calls.
- Verified on: 2026-09-26 (desk sources re-checked; Keycloak 26.7.4 and provider v5.9.0 were the latest releases) · lab measured 2026-09-27 on Keycloak 26.7.4 with provider v5.9.0 — re-verification against the then-current releases happens at publication.

## Not scripted here

The report describes these without printing a command for them, so they are not scripted:

- the timing of step 4 — the report queries the event store 5 seconds and 120 seconds after the last request, so run step 4 at those two times;
- reading the results side by side — which types each realm's saved-types list contains, and which events each realm's store holds.

## Files

| File | From the report |
|---|---|
| `main.tf` | §4 — the OpenTofu configuration for step 1, byte for byte |
| `reproduce.sh` | §4 — every line of its block, with the commands it prints, one step per run |

## Run order

On a test machine with Docker, OpenTofu and the provider as pinned above:

1. `./reproduce.sh 0` — start Keycloak 26.7.4 in dev mode and wait (at most 3 minutes) until its log shows the startup line.
2. `./reproduce.sh 1` — `tofu init`, `tofu apply -auto-approve`, then the drift check `tofu plan -detailed-exitcode` (exit code 0 = no changes, 2 = changes).
3. `./reproduce.sh 2` — the saved types the server reports for `rr07` and `rr07-explicit`.
4. `REALM=rr07 ./reproduce.sh 3`, then `REALM=rr07-explicit ./reproduce.sh 3` — the four requests in each realm.
5. `./reproduce.sh 4` — both realms' event stores, 5 seconds after the last request, and again 120 seconds after it.
6. `./reproduce.sh 5` — what the `jboss-logging` listener wrote.
7. `./reproduce.sh 6` — remove the test container.

## Expected observation

From the report (§3):

> **The saved types the server reports (`GET …/events/config`):** for `rr07`, `eventsEnabled: true`, `eventsListeners: ["jboss-logging"]`, and an `enabledEventTypes` list of 103 types that includes `LOGIN` and `LOGIN_ERROR` but not `REFRESH_TOKEN` or `REFRESH_TOKEN_ERROR` — the list the server returns when the realm's own list is empty (§1); for `rr07-explicit`, the four listed types.

> **The event store (`GET /admin/realms/<realm>/events`, at +5 s and +120 s):** the same at both times — `rr07` held two events, one `LOGIN` and one `LOGIN_ERROR`, and no `REFRESH_TOKEN` or `REFRESH_TOKEN_ERROR`; `rr07-explicit` held one of each of the four.

> **The listener (the `jboss-logging` lines in the container log):** in both realms, one line for each of the four types — `LOGIN` and `REFRESH_TOKEN` at `DEBUG`, `LOGIN_ERROR` and `REFRESH_TOKEN_ERROR` at `WARN` (the latter with `error="invalid_token"` and `reason="Invalid refresh token"`).

The report's own limits (§6):

> **Which other types are left out by default.** We name only the two we measured. To see which types your realm saves, read `GET /admin/realms/<realm>/events/config` or the saved-types list in the admin console.

> **Other versions.** Only Keycloak 26.7.4 with provider v5.9.0; we make no claim about other versions.

---

The team behind When It Runs maintains its own test environments and re-verifies findings when new releases change things; that is what the "Verified on" date means.

Licensed under the Apache License 2.0 — see `LICENSE`.
