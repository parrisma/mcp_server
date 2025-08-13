#!/bin/bash

# Check if the required number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <key> <value> <group>"
    exit 1
fi

# Assign command line arguments to variables
KEY="$1"
VALUE="$2"
GROUP="$3"

curl -X POST "http://localhost:8123/mcp" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "secure_datagroup-put_key_value",
    "arguments": {
      "key": "'"${KEY}"'",
      "value": "'"${VALUE}"'",
      "group": "'"${GROUP}"'"
    }
  }'


curl -X POST "http://localhost:8123/mcp" \
  -H "Authorization: Bearer <REDACTED>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "secure_datagroup-put_key_value",
    "arguments": {
      "key": "name",
      "value": "mark",
      "group": "people"
    }
  }'
