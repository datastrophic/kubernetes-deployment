# On-premises Kubernetes deployment
## Overview
This repository contains a reference implementation of bootstrapping and installation
of a Kubernetes cluster on-premises. The provided tooling can be used both as a basis
for personal projects and for educational purposes.

The goal of the project is to provide tooling for a "one-click" deployment of a fully
functional Kubernetes cluster for on-premises including support for `LoadBalancer`
service types, ingress, and storage.

Software used:
* `Ansible` for deployment automation
* `kubeadm` for Kubernetes cluster bootstrapping
* `containerd` container runtime
* `Calico` for pod networking
* `MetalLB` for exposing `LoadBalancer` type services
* `Istio` for ingress and traffic management

## Pre-requisites
* cluster machines/VMs should be provisioned and accessible over SSH
* it is recommended to use Ubuntu 20.04 as cluster OS
* the current user should have superuser privileges on the cluster nodes
* Ansible installed locally

## Quickstart
Installation consists of the following phases:
* prepare machines for Kubernetes installation
  * install common packages, disable swap, enable port forwarding, install container runtime
* Kubernetes installation
  * bootstrap control plane, install container networking, bootstrap worker nodes

To prepare machines for Kubernetes installation, run:
```
ansible-playbook -i ansible/inventory.yaml ansible/bootstrap.yaml -K
```

> **NOTE:** the bootstrap step usually required to run only once or when new nodes joined.

To install Kubernetes, run:
```
ansible-playbook -i ansible/inventory.yaml ansible/kubernetes-install.yaml -K
```

Once the playbook run completes, a kubeconfig file `admin.conf` will be fetched to the current directory. To verify
the cluster is up and available, run:
```
$> kubectl --kubeconfig=admin.conf get nodes
NAME                          STATUS   ROLES                  AGE     VERSION
control-plane-0.k8s.cluster   Ready    control-plane,master   4m40s   v1.21.6
worker-0                      Ready    <none>                 4m5s    v1.21.6
worker-1                      Ready    <none>                 4m5s    v1.21.6
worker-2                      Ready    <none>                 4m4s    v1.21.6
```

Consider running [sonobuoy](https://sonobuoy.io/) conformance test to validate the cluster configuration and health.    

To uninstall Kubernetes, run:
```
ansible-playbook -i ansible/inventory.yaml ansible/kubernetes-reset.yaml -K
```
This playbook will run `kubeadm reset` on all nodes, remove configuration changes, and stop Kubelets.


## MetalLB

To install MetalLB, check the configuration in [ansible/roles/metallb/templates/metallb-config.yaml](ansible/roles/metallb/templates/metallb-config.yaml) and update variables if needed. The address range must be relevant for the target
environment so the addresses can be allocated.

To install MetalLB, run:
```
ansible-playbook -i ansible/inventory.yaml ansible/metallb.yaml -K
```

## Istio

Istio provides multiple [installation options](https://istio.io/latest/docs/setup/install/).
To simplify the installation process, download and install `istioctl` from [releases page](https://github.com/istio/istio/releases/).

It is recommended to install Istio with the [default configuration profile](https://istio.io/latest/docs/setup/additional-setup/config-profiles/). This profile is recommended for production deployments and deploys a single ingress gateway.
To install Istio with the default profile, run:
```
istioctl install --set profile=default -y
```

Once Istio is installed, you can check that the Ingress Gateway is up and has an associated `Service`
of a `LoadBalancer` type with an IP address from MetalLB. Example:
```
kubectl get svc istio-ingressgateway --namespace istio-system

NAME                   TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)                                      AGE
istio-ingressgateway   LoadBalancer   10.107.130.40   192.168.50.150   15021:30659/TCP,80:31754/TCP,443:32354/TCP   75s
```
