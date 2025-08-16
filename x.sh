curl -v -H "Authorization: Bearer <REDACTED>" -H "Content-Type: application/json" "http://localhost:4000/v1/mcp/tools"

curl -X 'GET' \
  'http://localhost:4000/v1/mcp/server' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer <REDACTED>"


curl -X 'GET' \
  'http://localhost:4000/v1/mcp/server/health' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer <REDACTED>-kYdYzsKZg"

curl -X 'GET' \
  'http://localhost:4000/v1/mcp/server/71e8dd123158953d20757f00c04bd8d4' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer <REDACTED>"


curl -X 'GET' \
  'http://localhost:4000/mcp-rest/tools/list' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer <REDACTED>-kYdYzsKZg"

curl -X 'GET' \
  'http://localhost:4000/v1/mcp/access_groups' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer "


curl -X 'GET' \
  'http://localhost:4000/v1/mcp/server/71e8dd123158953d20757f00c04bd8d4/health' \
  -H 'accept: application/json' \
  -H "Authorization: Bearer <REDACTED>"


clear;curl -X POST "http://localhost:9000/mcp-rest/tools/call" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "secure_datagroup-put_key_value",
    "arguments": {
      "key": "name",
      "value": "Bobby123",
      "group": "people"
    }
  }'

  clear;curl -X POST "http://localhost:9000/mcp-rest/tools/call" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "secure_datagroup-get_value_by_key",
    "arguments": {
      "key": "name",
      "group": "people"
    }
  }'

clear;curl -X POST "http://localhost:8088/mcp-rest/tools/call/secure_datagroup-get_value_by_key" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {
      "key": "name",
      "group": "people"
    }
  }'

clear;curl -X POST "http://localhost:9000/mcp-rest/tools/call/secure_datagroup-get_value_by_key" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {
      "key": "name",
      "group": "people"
    }
  }'

clear;curl -X POST "http://localhost:9000/mcp-rest/tools/call/secure_datagroup-put_key_value" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "arguments": {
      "key": "name",
      "value": "Bobby123",
      "group": "people"
    }
  }'

  curl -GET "http://0.0.0.0:8088/health"

  curl -GET "http://localhost:8088/health"