#!/usr/bin/env bash

EDG_COORDINATOR_ADDR=$(basename $(minikube -n emojivoto service --url --https=true coordinator-client-svc))
EDG_COORDINATOR_HOST=${EDG_COORDINATOR_ADDR%:*}
EDG_COORDINATOR_PORT=${EDG_COORDINATOR_ADDR#"$EDG_COORDINATOR_HOST"}
EDG_COORDINATOR_PORT=${EDG_COORDINATOR_PORT#:}
echo "$EDG_COORDINATOR_HOST coordinator-client-svc" | sudo tee -a /etc/hosts
export EDG_COORDINATOR_SVC="coordinator-client-svc:$EDG_COORDINATOR_PORT"
echo "[+] Done! You can reach the ClientAPI @ $EDG_COORDINATOR_SVC"