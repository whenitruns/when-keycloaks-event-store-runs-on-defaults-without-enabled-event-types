#!/usr/bin/env bash
# Run Report #RR07, §4 (Reproduction). Every line of the report's §4 block appears below, in order and exactly as printed.
# Each step then runs the commands its lines print, one step per invocation; step 3 reads the realm from REALM
# (the report runs it for rr07, then for rr07-explicit); step 4 reads both. main.tf is the report's OpenTofu configuration, byte for byte.
#   ./reproduce.sh 0 | 1 | 2 | REALM=<realm> ./reproduce.sh 3 | 4 | 5 | 6
# Per the report (§3), step 3's wrong password and altered refresh token are rejected (HTTP 400), and step 1's drift check
# exits 0 (no changes) or 2 (changes), so the script does not stop on a non-zero exit.
set -uo pipefail
cd "$(dirname "$0")"

step_0() {
# 0. Start Keycloak 26.7.4 (official image, digest-pinned) in dev mode, with the event listener's
#    log category at debug so its success lines are visible, and wait until it has started.
#      docker run -d --name rr07-kc -p 8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c start-dev --log-level="INFO,org.keycloak.events:debug"
#      for i in $(seq 1 60); do docker logs rr07-kc 2>&1 | grep -E 'Keycloak 26\.7\.4 on JVM .* started' && break; sleep 3; done   # the startup line, at most 3 minutes
docker run -d --name rr07-kc -p 8080:8080 -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c start-dev --log-level="INFO,org.keycloak.events:debug"
for i in $(seq 1 60); do docker logs rr07-kc 2>&1 | grep -E 'Keycloak 26\.7\.4 on JVM .* started' && break; sleep 3; done   # the startup line, at most 3 minutes
}

step_1() {
# 1. Apply the OpenTofu configuration below (main.tf; OpenTofu 1.12.6, provider keycloak/keycloak 5.9.0),
#    then check for drift right away (exit code 0 = no changes, 2 = changes).
#      tofu init
#      tofu apply -auto-approve
#      tofu plan -detailed-exitcode
tofu init
tofu apply -auto-approve
tofu plan -detailed-exitcode
}

step_2() {
# 2. Read the saved types the server reports for each realm (admin token from the master realm).
#      TOKEN=$(curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://localhost:8080/realms/master/protocol/openid-connect/token | jq -r .access_token)
#      curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms/rr07/events/config | jq .
#      curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms/rr07-explicit/events/config | jq .
TOKEN=$(curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://localhost:8080/realms/master/protocol/openid-connect/token | jq -r .access_token)
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms/rr07/events/config | jq .
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/admin/realms/rr07-explicit/events/config | jq .
}

step_3() {
# 3. Generate the four events in each realm (run once with REALM=rr07, then with REALM=rr07-explicit).
#      T=http://localhost:8080/realms/$REALM/protocol/openid-connect/token
#      RT=$(curl -s -d grant_type=password -d client_id=rr07-app -d username=alice -d password=alice-pass-1 $T | jq -r .refresh_token)   # LOGIN
#      curl -s -d grant_type=password -d client_id=rr07-app -d username=alice -d password=wrong-password $T                                  # LOGIN_ERROR
#      curl -s -d grant_type=refresh_token -d client_id=rr07-app -d refresh_token="$RT" $T                                                   # REFRESH_TOKEN
#      curl -s -d grant_type=refresh_token -d client_id=rr07-app -d refresh_token="${RT}x" $T                                                # REFRESH_TOKEN_ERROR (altered token)
: "${REALM:?set REALM to rr07, then to rr07-explicit (see README)}"
T=http://localhost:8080/realms/$REALM/protocol/openid-connect/token
RT=$(curl -s -d grant_type=password -d client_id=rr07-app -d username=alice -d password=alice-pass-1 $T | jq -r .refresh_token)   # LOGIN
curl -s -d grant_type=password -d client_id=rr07-app -d username=alice -d password=wrong-password $T                                  # LOGIN_ERROR
curl -s -d grant_type=refresh_token -d client_id=rr07-app -d refresh_token="$RT" $T                                                   # REFRESH_TOKEN
curl -s -d grant_type=refresh_token -d client_id=rr07-app -d refresh_token="${RT}x" $T                                                # REFRESH_TOKEN_ERROR (altered token)
}

step_4() {
# 4. Query each realm's event store 5 seconds and 120 seconds after the last request (fresh admin token each time).
#      TOKEN=$(curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://localhost:8080/realms/master/protocol/openid-connect/token | jq -r .access_token)
#      for REALM in rr07 rr07-explicit; do echo "== $REALM"; curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8080/admin/realms/$REALM/events?max=100" | jq -r '.[].type' | sort | uniq -c; done
TOKEN=$(curl -s -d grant_type=password -d client_id=admin-cli -d username=admin -d password=change_me http://localhost:8080/realms/master/protocol/openid-connect/token | jq -r .access_token)
for REALM in rr07 rr07-explicit; do echo "== $REALM"; curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8080/admin/realms/$REALM/events?max=100" | jq -r '.[].type' | sort | uniq -c; done
}

step_5() {
# 5. Look at what the jboss-logging listener wrote for the same requests.
#      docker logs --timestamps rr07-kc 2>&1 | grep 'org.keycloak.events'
docker logs --timestamps rr07-kc 2>&1 | grep 'org.keycloak.events'
}

step_6() {
# 6. Tear down (the test container only).
#      docker rm -f rr07-kc
docker rm -f rr07-kc
}

case "${1:-}" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  3) step_3 ;;
  4) step_4 ;;
  5) step_5 ;;
  6) step_6 ;;
  *) echo "usage: $0 0 | 1 | 2 | 3 | 4 | 5 | 6  (one step per run, in order; step 3 needs REALM; see README)"; exit 2 ;;
esac
