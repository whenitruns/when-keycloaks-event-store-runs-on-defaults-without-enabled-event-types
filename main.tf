terraform {
  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "5.9.0"
    }
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = "admin"
  password  = "change_me"
  url       = "http://localhost:8080"
}

# Realm rr07: user events on, enabled_event_types left out.
resource "keycloak_realm" "rr07" {
  realm   = "rr07"
  enabled = true
}

resource "keycloak_realm_events" "rr07" {
  realm_id         = keycloak_realm.rr07.id
  events_enabled   = true
  events_listeners = ["jboss-logging"]
}

# Realm rr07-explicit: the same, with the four types listed.
resource "keycloak_realm" "rr07_explicit" {
  realm   = "rr07-explicit"
  enabled = true
}

resource "keycloak_realm_events" "rr07_explicit" {
  realm_id            = keycloak_realm.rr07_explicit.id
  events_enabled      = true
  events_listeners    = ["jboss-logging"]
  enabled_event_types = ["LOGIN", "LOGIN_ERROR", "REFRESH_TOKEN", "REFRESH_TOKEN_ERROR"]
}

# In each realm: a public client with direct access grants, and one user.
locals {
  realm_ids = {
    "rr07"          = keycloak_realm.rr07.id
    "rr07-explicit" = keycloak_realm.rr07_explicit.id
  }
}

resource "keycloak_openid_client" "app" {
  for_each                     = local.realm_ids
  realm_id                     = each.value
  client_id                    = "rr07-app"
  access_type                  = "PUBLIC"
  standard_flow_enabled        = false
  direct_access_grants_enabled = true
}

resource "keycloak_user" "alice" {
  for_each       = local.realm_ids
  realm_id       = each.value
  username       = "alice"
  email          = "alice@example.com"
  email_verified = true
  first_name     = "Alice"
  last_name      = "Example"

  initial_password {
    value     = "alice-pass-1"
    temporary = false
  }
}
