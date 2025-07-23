#!/bin/bash
docker network rm home-net
docker network create --driver overlay home-net
docker stack rm openwebui_stack
docker stack deploy -c openwebui-stack.yml openwebui_stack
