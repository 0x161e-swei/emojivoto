#! /bin/bash

function check_pod_ready {
	POD_NAME=$1
	POD_CNT=$2
	echo "Checking $POD_NAME for $POD_CNT instances"
	POD_READY_CNT=`kubectl get pods -A | grep "$1" | wc -l`
	while [ $POD_READY_CNT != "$POD_CNT" ]; do
		echo  "Only $POD_READY_CNT/$POD_CNT ready for $POD_NAME"
		sleep 3
		POD_READY_CNT=`kubectl get pods -A | grep "$1" | wc -l`
	done
	echo  "$POD_READY_CNT/$POD_CNT ready for $POD_NAME"
	sleep 3
}

if [ ! -d $HOME/microservices/intel-device-plugins-for-kubernetes ]; then
	mkdir -p $HOME/microservices
	cd $HOME/microservices
	echo "cloning repos"
	git clone https://github.com/intel/intel-device-plugins-for-kubernetes
	git clone https://github.com/edgelesssys/helm.git
	git clone https://github.com/0x161e-swei/emojivoto.git
fi

# start the minikube cluster
# sudo -E minikube start --driver=none --cni=cilium
sudo -E minikube start --driver=none
sudo chown -R $USER $HOME/.kube $HOME/.minikube

# cert manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml

# wait for the cert-manager to be ready to accept requests
check_pod_ready "cert-manager.*1/1" "3"

# install device plugin and operator
kubectl apply -k $HOME/microservices/intel-device-plugins-for-kubernetes/deployments/sgx_plugin/overlays/epc-nfd/

# install marblerun
check_pod_ready "intel-sgx-plugin.*1/1" "1"
check_pod_ready "node-feature.*1/1" "2"
sleep 10
marblerun precheck
marblerun install --marblerun-chart-path $HOME/microservices/helm/marblerun-coordinator/
sleep 10

MARBLERUN_COORDINATOR=`kubectl get pods -A | grep "marblerun-coordinator" | awk '{print $2}'`
# wait for marblerun to be ready and check log
marblerun check
check_pod_ready "marblerun.*1/1" "2"
kubectl logs -n marblerun $MARBLERUN_COORDINATOR | grep -C 3 -i "seal"



MARBLERUN=localhost:4433
AZDCAP_DEBUG_LOG_LEVEL="INFO"
export AZDCAP_DEBUG_LOG_LEVEL
kubectl -n marblerun port-forward svc/coordinator-client-api 4433:4433 --address localhost >/dev/null &

AZDCAP_DEBUG_LOG_LEVEL="INFO" marblerun certificate root $MARBLERUN -o $HOME/marblerun.crt


cd $HOME/microservices/emojivoto
# AZDCAP_DEBUG_LOG_LEVEL="INFO" marblerun manifest set $HOME/microservices/emojivoto/tools/manifest.json $MARBLERUN
AZDCAP_DEBUG_LOG_LEVEL="INFO" marblerun manifest set $HOME/microservices/emojivoto/tools/manifest_remote_img.json $MARBLERUN
AZDCAP_DEBUG_LOG_LEVEL="INFO" marblerun status $MARBLERUN
AZDCAP_DEBUG_LOG_LEVEL="INFO" marblerun manifest get $MARBLERUN -o uploaded_manifest.sig
echo "remote manifest"
cat uploaded_manifest.sig
echo -e "\nlocal manifest"
sha256sum tools/manifest.json


kubectl create namespace emojivoto
marblerun namespace add emojivoto

# helm install -f ./kubernetes/sgx_values.yaml emojivoto ./kubernetes --create-namespace -n emojivoto
helm install -f ./kubernetes/sgx_values_remote_img.yaml emojivoto ./kubernetes --create-namespace -n emojivoto

# port forward the requests
# sudo kubectl -n emojivoto port-forward svc/web-svc 4400:443 --address 0.0.0.0 &
# sudo kubectl -n emojivoto port-forward svc/web-svc-http 8400:8080 --address 0.0.0.0 &



###
# to delete service and uninstall marblerun control plane, run:
###

# helm delete -n emojivoto emojivoto
# marblerun uninstall
