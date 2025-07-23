#!/bin/sh
curl -vk https://keycloak.test/realms/openwebui/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=openwebui" \
  -d "client_secret=Ppw64yIeodS9O3QifhMnOjzCj6uBnck0" \
  -d "username=test" \
  -d "password=password" \
  -d "grant_type=password"
