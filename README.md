# Confidential Emoji.voto

A microservice application that allows users to vote for their favorite emoji,
and tracks votes received on a leaderboard. May the best emoji win.
The application is a fork of [linkerd's emojivoto](https://github.com/BuoyantIO/emojivoto) refactored as a confidential computing application.

The application is composed of the following 3 services:

* [emojivoto-web](emojivoto-web/): Web frontend and REST API
* [emojivoto-emoji-svc](emojivoto-emoji-svc/): gRPC API for finding and listing emoji
* [emojivoto-voting-svc](emojivoto-voting-svc/): gRPC API for voting and leaderboard

Confidential emojivoto is build as a confidential computing application:

* Each service runs in a confidential enclave using [EdgelessRT](https://github.com/edgelesssys/edgelessrt)
* The application is distributed, configured, and connected using [Marblerun](https://github.com/edgelesssys/marblerun)

![Emojivoto Topology](assets/emojivoto-topology.gif "Emojivoto Topology")

## Running

### In Minikube

Deploy the application to Minikube using the Marblerun.

1. Start Minikube

   Start with a fresh minikube and give it sufficient memory:

   ```bash
   minikube delete
   minikube start --memory=6g
   ```

1. Install Marblerun

    Deploy with [helm](https://helm.sh/docs/intro/install/)

    ```bash
    helm repo add edgeless https://helm.edgeless.systems/stable
    helm repo update
    ```

    Update the hostname with your cluster's FQDN or use localhost if you're running on minikube

    * If you're deploying on a cluster with nodes that support SGX1+FLC (e.g. AKS or minikube + Azure Standard_DC*s)

    ```bash
    helm install marblerun-coordinator edgeless/marblerun-coordinator \
        --create-namespace \
        -n marblerun \
        --set coordinator.hostname=mycluster.uksouth.cloudapp.azure.com
    ```

    * Otherwise

    ```bash
    helm install marblerun-coordinator edgeless/marblerun-coordinator \
        --create-namespace \
        -n marblerun \
        --set coordinator.resources=null \
        --set coordinator.simulation=1 \
        --set tolerations=null \
        --set coordinator.hostname=mycluster.uksouth.cloudapp.azure.com
    ```

    You can check with `kubectl get pods -n marblerun` that the Coordinator is running.

1. Pull the remote attestation configuration

    ```bash
    wget https://github.com/edgelesssys/marblerun/releases/latest/download/coordinator-era.json
    ```

1. Get the Coordinator's address and set the DNS

    ```bash
    kubectl -n marblerun port-forward svc/coordinator-client-api 25555:25555 --address localhost >/dev/null &
    export MARBLERUN=localhost:25555
    ```

1. Install the Edgeless Remote Attestation Tool
    1. Check [requirements](https://github.com/edgelesssys/era#requirements)
    2. See [install](https://github.com/edgelesssys/era#install)

1. Verify the Quote and get the Coordinator's Root-Certificate
    * If you're running on a cluster with nodes that support SGX1+FLC

        ```bash
        era -c coordinator-era.json -h $MARBLERUN -o marblerun.crt
        ```

    * Otherwise

        ```bash
        era -skip-quote -c coordinator-era.json -h $MARBLERUN -o marblerun.crt
        ```

1. Set the manifest

    ```bash
    curl --cacert marblerun.crt --data-binary @tools/manifest.json https://$MARBLERUN/manifest
    ```

    * If you're running emojivoto on a custom domain, you can set the certificate's CN accordingly

    ```bash
    manifest=$(sed 's/localhost/<your-domain>/g' tools/manifest.json)
    curl --cacert marblerun.crt --data-binary "$manifest" https://$MARBLERUN/manifest
    ```

1. Deploy emojivoto

    * If you're deploying on a cluster with nodes that support SGX1+FLC (e.g. AKS or minikube + Azure Standard_DC*s)

    ```bash
    helm install -f ./kubernetes/sgx_values.yaml emojivoto ./kubernetes --create-namespace -n emojivoto
    ```

    * Otherwise

    ```bash
    helm install -f ./kubernetes/nosgx_values.yaml emojivoto ./kubernetes --create-namespace -n emojivoto
    ```

    You can check with `kubectl get pods -n emojivoto` that all pods is running.

1. Install Marblerun-Certificate in your browser
    * **Warning** Be careful when adding certificates to your browser. We only do this temporarly for the sake of this demo. Make sure you don't use your browser for other activities in the meanwhile and remove the certificate afterwards.
    * Chrome:
        * Go to <chrome://settings/security>
        * Go to `"Manage certificates" > "Import..."`
        * Follow the "Certificate Import Wizard" and import the `marblerun.crt` of the previous step as a "Personal" certificate
    * Firefox:
        * Go to `Tools > Options > Advanced > Certificates: View Certificates`
        * Go to `Import...` and select the `marblerun.crt` of the previous step

1. Verify the manifest
    * You can verify the manifest on the client-side before using the app:

    ```bash
    tools/check_manifest.sh tools/manifest.json
    ```

    * If you're running with a custom domain

    ```
    echo -n $manifest > /tmp/manifest.json
    tools/check_manifest.sh /tmp/manifest.json
    ```


1. Use the app!

    ```bash
    sudo kubectl -n emojivoto port-forward svc/web-svc 443:443 --address 0.0.0.0
    ```

    * Browse to [https://localhost](https://localhost).
    * If your running on a custom domain browse to https://<your-domain>

### In AKS

We have provided a [script](tools/deploy_on_aks.sh) to deploy emojivoto in an AKS cluster:

```bash
tools/aks_install.sh <az_subscription_id> <az_resource_name> <az_cluster_name> <nodes> <cluster-domain>
# Example
tools/aks_install 00112233-04455-6677-8899-aabbccddeeff emoji emojivoto 5 uksouth.cloudapp.azure.com
```

The script requires the [bash Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) to be installed.
Further you need to be [logged in](https://docs.microsoft.com/en-us/cli/azure/authenticate-azure-cli) to your Azure account.

The following tasks are performed by the script:

1. Connect to your Azure Subscription ID
1. Optionally create the cluster
1. Retrieve the cluster credentials
1. Optionally install linkerd
1. Install Marblerun
1. Install an NGINX-Ingress-Controller
1. Associate domain names with LoadBalancer public IPs
    * marblerun-xxx.cluster-domain -> Marblerun Client API
    * emojivoto-xxx.cluster-domain -> NGINX-Ingress-Controller
1. Create an emojivoto deployment
1. Create an ingress resource to forward traffic via HTTPS-SNI
    * https://emojivoto-xxx.cluster-domain -> emojivoto

Uninstall with:
```bash
tools/aks_uninstall.sh <az_resource_name> <az_cluster_name>
```


### Generating some traffic

The `VoteBot` service can generate some traffic for you. It votes on emoji
"randomly" as follows:

* It votes for :doughnut: 15% of the time.
* When not voting for :doughnut:, it picks an emoji at random

If you're running the app using the instructions above, the VoteBot will have
been deployed and will start sending traffic to the vote endpoint.

If you'd like to run the bot manually:

```bash
export WEB_HOST=localhost:443 # replace with your web location
go run emojivoto-web/cmd/vote-bot/main.go
```

## Build

```bash
tools/install-dependencies.sh
mkdir -p build && pushd build && cmake .. && make && popd
```

## Docker

Build docker images:

```bash
docker buildx build --secret id=signingkey,src=<path to private.pem> --target release_web --tag ghcr.io/edgelesssys/emojivoto/web:latest .
docker buildx build --secret id=signingkey,src=<path to private.pem> --target release_emoji_svc --tag ghcr.io/edgelesssys/emojivoto/emoji-svc:latest .
docker buildx build --secret id=signingkey,src=<path to private.pem> --target release_voting_svc --tag ghcr.io/edgelesssys/emojivoto/voting-svc:latest .
```

## License

Copyright 2020 Buoyant, Inc. All rights reserved.\
Copyright 2020 Edgeless Systems GmbH. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
these files except in compliance with the License. You may obtain a copy of the
License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
