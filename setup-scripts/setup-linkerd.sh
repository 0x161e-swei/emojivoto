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

if [ ! -d $HOME/microservices/emojivoto-original ]; then
	mkdir -p $HOME/microservices
	cd $HOME/microservices
	echo "cloning repos"
	git clone https://github.com/BuoyantIO/emojivoto.git emojivoto-original
	cp -r emojivoto-original/kustomize emojivoto-original/kustomize-no-bot
	# remove vote-bot for preparing load test
	sed -i "s/\- vote\-bot.yml//g" emojivoto-original/kustomize-no-bot/deployment/kustomization.yml
fi

# start the minikube cluster
# sudo -E minikube start --driver=none --cni=cilium
sudo -E minikube start --driver=none
sudo chown -R $USER $HOME/.kube $HOME/.minikube

linkerd install | kubectl apply -f -

cd $HOME/microservices/emojivoto-original
kubectl kustomize kustomize-no-bot/statefulset/ | \
	linkerd inject - | \
	kubectl apply -f -

kubectl describe service web-svc -n emojivoto
sudo kubectl -n emojivoto port-forward svc/web-svc 30002:80 --address 0.0.0.0 &
sleep 1
ech "emojivoto web service up at port 30002 with HTTP"



###
# to delete service and uninstall linkerd control plane, run:
###

# kubectl kustomize kustomize-no-bot/statefulset/ | \
# 	linkerd inject - | \
# 	kubectl delete -f -

# linkerd uninstall | kubectl apply -f -

