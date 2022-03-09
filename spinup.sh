#!/usr/bin/env bash
#For Ubuntu
Check if kubectl is installed
var=$(dpkg -s kubectl | grep Status)
if [[  $var != "Status: install ok installed" ]] 
then
    sudo apt-get update
    sudo apt-get install -y apt-transport-https ca-certificates curl
    echo "Kubectl not present. Installing now."
    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
    kubectl version --client
else
    echo "Kubectl already present"
fi

Check if helm is installed
var=$(dpkg -s helm | grep Status)
if [[  $var != "Status: install ok installed" ]] 
then
    echo "Helm not present. Installing now."
    curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
    sudo apt-get install apt-transport-https --yes
    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install helm
else
    echo "Helm already present"
fi

Check if minikube is installed
var=$(dpkg -s minikube | grep Status)
if [[  $var != "Status: install ok installed" ]] 
then
    echo "Minikube not present. Installing now."
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
    sudo dpkg -i minikube_latest_amd64.deb
else
    echo "Minikube already Present"
fi

#create cluster if not present
cluster=$(minikube status | grep "not found" | awk -F "." '{print $1}' | cut -d' ' -f2-)
if [[ $cluster ==  ' Profile "minikube" not found' ]]
then
    echo "Creating Minikube Cluster"
    minikube start
    helm repo add apache-airflow https://airflow.apache.org
    helm upgrade --install airflow apache-airflow/airflow -n airflow --create-namespace --debug
fi

#deploy airflow if not running 
status=$(minikube status | grep apiserver)
echo "Current Minikube status:" $status
if [[ $status == "apiserver: Paused" ]]
then 
    echo "Unpausing Minikube"
    minikube unpause
elif [[ $status == "apiserver: Stopped" ]]
then
    echo "Restarting Minikube"
    minikube start
elif [[ $status == "apiserver: Running" ]]
then
    echo "Checking if all pods are running"
    pods=$(kubectl get pods -n airflow | awk -F " " '{print $3}' | tail -n +2)
    if [[ $pods == "" ]]
    then 
        echo "No pods found."
        flag=1
    else
        for pod in $pods
        do
            if [[ $pod != "Running"  ]]
            then
                echo "Some pods not running."
                flag=1
                break
            fi
        done
    fi
    if [[ $flag ]]
    then 
        helm upgrade --install airflow apache-airflow/airflow --namespace airflow --create-namespace --debug
    fi
fi
echo "Waiting for Webserver Pod to Spin Up"
kubectl wait --for=condition=ready pod -l component=webserver -n airflow
release=$(helm ls -n airflow | grep airflow | awk -F " " '{print $8}')
if [[ $release == "deployed" ]]
then
    echo "All components of Airflow are running."
    echo "To access the UI from the browser at http://localhost:8080, Run command kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow"
    echo "To upgrade airflow, run helm upgrade airflow apache-airflow/airflow --namespace airflow -f values.yaml --debug"
else
    echo "Airflow Deployment failed."
fi
