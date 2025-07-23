from jose import jwt
from fastapi import Request, HTTPException
from fastapi.security import HTTPBearer
import httpx

OIDC_ISSUER = "https://keycloak.test/realms/openwebui"
OIDC_JWKS_URL = f"{OIDC_ISSUER}/protocol/openid-connect/certs"
OIDC_AUDIENCE = "openwebui"
security = HTTPBearer()

# Cached JWKs
jwks = httpx.get(OIDC_JWKS_URL).json()

def verify_token(request: Request):
    token = security(request)
    try:
        claims = jwt.decode(token.credentials, jwks, algorithms=["RS256"], audience=OIDC_AUDIENCE)
        return claims
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")