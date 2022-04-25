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
    export status=$(helm history airflow -n airflow --max 1 2>/dev/null | grep -i FAILED)

    if [[ $status ]]
    then
        echo "INFO: Previous Release Failed. Uninstalling"
        helm uninstall airflow -n airflow
        sleep 10
    fi
    helm upgrade --install airflow apache-airflow/airflow -n airflow \
        --create-namespace \
        --debug \ 
        --set executor=LocalExecutor \
        --set statsd.enabled=false \
        --set triggerer.enabled=false
        
    export status=$(helm history airflow -n airflow --max 1 2>/dev/null | grep -i FAILED)
    if [[ $status ]]
    then
        echo "INFO: Release Failed. Rolling Back"
        helm rollback airflow -n airflow
    else
        echo "--------------------------------------------------------"
        echo "INFO: Checking Components"
        echo "--------------------------------------------------------"
        release=$(helm ls -n airflow | grep airflow | awk -F " " '{print $8}')
        if [[ $release == "deployed" ]]
        then
            echo "INFO: Airflow Successfully Deployed."
            echo "INFO: Checking if all pods are running"
            pods=$(kubectl get pods -n airflow | awk -F " " '{print $3}' | tail -n +2)
            if [[ $pods == "" ]]
            then
                echo "--------------------------------------------------------"
                echo "INFO: No pods found."
                echo "--------------------------------------------------------"
                flag=1
            else
                for pod in $pods
                do
                    if [[ $pod != "Running"  ]]
                    then
                        echo "--------------------------------------------------------"
                        echo "Some pods not running."
                        echo "--------------------------------------------------------"
                        flag=1
                        break
                    fi
                done
            fi
            if [[ $flag != 1 ]]
            then
                echo "--------------------------------------------------------"
                echo "INFO: To access the UI from the browser at http://localhost:8080"
                echo "INFO: Run command kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow"
                echo "--------------------------------------------------------"
            else
                echo "Restarting Pods."
                kubectl delete pods -n airflow --all
                echo "Waiting for Pods to Restart"
                kubectl wait --for=jsonpath='{.status.phase}'=Running pod -l component=webserver -n airflow
            fi
            helm history airflow -n airflow --max 1
        else
            echo "--------------------------------------------------------"
            echo "INFO: Deployment Failed"
            echo "--------------------------------------------------------"
            helm uninstall airflow -n airflow
        fi
    fi
fi
