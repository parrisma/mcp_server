import requests
import jwt
import json

# Keycloak configuration
KEYCLOAK_URL = "https://keycloak.test"
REALM = "openwebui"
CLIENT_ID = "openwebui"
USERNAME = "test"
PASSWORD = "password"

# Construct token URL
token_url = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/token"

# Build payload
payload = {
    "client_id": CLIENT_ID,
    "client_secret": "Ppw64yIeodS9O3QifhMnOjzCj6uBnck0",
    "grant_type": "password",
    "username": USERNAME,
    "password": PASSWORD,
    "scope": "openid profile email"
}

# Request the token
# verify=False skips TLS validation for self-signed certs
response = requests.post(token_url, data=payload, verify=False)

if response.status_code == 200:
    token_data = response.json()
    access_token = token_data["access_token"]
    print("Access token received:")
    decoded = jwt.decode(access_token, options={
                         "verify_signature": False}, algorithms=["RS256"])
    # Pretty-print the claims
    print("📜 Decoded token payload:")
    print(json.dumps(decoded, indent=2))

    userinfo_url = f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/userinfo"
    headers = {"Authorization": f"Bearer {access_token}"}

    user_response = requests.get(userinfo_url, headers=headers, verify=False)

    print(user_response.json())

    if user_response.ok:
        print("User info:")
        print(user_response.json())
    else:
        print("Failed to authenticate:")
        print(f"Status code: {response.status_code}")
        print(response.text)
else:
    print("Failed to authenticate:")
    print(f"Status code: {response.status_code}")
    print(response.text)
