# Services

## Docker Desktop

Ensure WSL integration is turned on with Ubuntu

## Swarm File

The [swarm yml file](simple-oauth-dev-stack.yml) defines all of the following services

### KeyCloak

This acts as the oauth server.

To verify the oauth integration with openwebui and the attached services we define users in here.

Assume a clean install

1. [http://localhost:8081](http://localhost:8081)
1. Admin Console
1. Login with default user [admin] and [password]
1. Now we [integrate](https://docs.openwebui.com/features/sso/keycloak/) KeyCloak with OpenWebUi
1. Create realm openwebui
1. Create Client
    1. Capability Config
        1. Client authentication = on
    1. Login Settings
        1. Valid redirect URL: <http://localhost:8080/oauth/oidc/callback> = keyCloak as keycloak is running on localhost and redirecting to itself.
        2. Web Origins: <http://localhost:8080>
1. Run the verification [script](scripts/key-cloak-verify.sh)

### Litellm

1. Login [http://localhost:4000/ui/](http://localhost:4000/ui/)
    1. login as admin, the password is the LITELLM_MASTER_KEY in the [stack yml](simple-oauth-dev-stack.yml)
    1. Create team mcp_tools
    1. Create a virtual key, team mcp_tool, key type = Default (API & Mgmt)
    1. Test LiteLLM

        ```
        curl -X 'GET' 'http://localhost:4000/v1/mcp/server/health' -H 'accept: application/json' -H "Authorization: Bearer sk-<key from above>"
        ```

1. All set-up is done via the [litellm-config.yaml](litellm-config.yaml)
    1. To change LiteLLM settings, edit litellm-config.yaml
        1. Then force the service to reload the config:

           ```
           docker service update --force openwebui_stack_litellm
           docker service update --force openwebui_stack_openwebui
           ```

### Openwebui

1. Login as Admin
