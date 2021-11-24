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

## Kubernetes Dashboard
Install Kubernetes Dashboard following the [docs](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/). At the moment of writing, it is sufficient to run:
```
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.4.0/aio/deploy/recommended.yaml
```

To access the dashboard UI, run `kubectl proxy` and open this link in your browser:
[localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/).

To login into the Dashboard, it is recommended to create a user as per the [Dashboard docs](https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md):
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
```

Once the user is created, we can get the login token:
```
kubectl -n kubernetes-dashboard get secret $(kubectl -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}"
```

Alternatively, it is possible to use an default token from the `kube-system` namespace, however, the RBAC for it
is more narrow and wouldn't allow to observe all the namespaces and resources:
```
 kubectl --namespace kube-system get secret -o name | grep default-token | xargs kubectl --namespace kube-system get -o jsonpath='{.data.token}'
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

### Example deployment exposed via Istio Ingress Gateway
#### Deploying Nginx
To verify the installation, MetalLB, Ingress Gateway, and Istio configuration let's create
a test Nginx `Deployment`:
```
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - image: nginx
        name: nginx

---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: nginx
  name: nginx
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: nginx
  type: ClusterIP
```

To verify the deployment, run:
```
 kubectl port-forward service/nginx 8080:80
 ```
The Nginx welcome page should be available at [localhost:8080](http://localhost:8080/).

#### Exposing Nginx deployment with Istio `Gateway` and `VirtualService`
To expose a deployment via Istio ingress gateway it is first required to create a [Gateway](https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/).

We will create a shared `Gateway` in the `istio-system` namespace with a wildcard host pattern so it can be reused
by other deployments. The deployments will be routed by the `VirtualServices` using the URL path later on.
It is also possible to create a `Gateway` per application but for the demo purposes, a path-based routing
seems to be more convenient.
```
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: shared-gateway
  namespace: istio-system
spec:
  selector:
    # Use the default Ingress Gateway installed by Istio
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

Now, we should define the route and [create a VirtualService](https://istio.io/latest/docs/reference/config/networking/virtual-service/) to route the traffic to Nginx `Service`:
 ```
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
 name: nginx
spec:
 hosts:
 - "*"
 gateways:
 - nginx-gateway
 http:
 - name: "nginx-test"
   match:
   - uri:
       prefix: "/nginx-test"
   rewrite:
     uri: "/"
   route:
   - destination:
       host: nginx.default.svc.cluster.local
       port:
         number: 80
```

The `VirtualService` defines a prefix `prefix: "/nginx-test"` so that all requests
to the `<Enpoint URL>/nginx-test` will be routed to the Nginx `Service`.
The endpoint URL is a load balancer address of the Istio Ingress Gateway.
It comes handy to discover and export it to an environment variable for later use:
```
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway --namespace istio-system -o yaml -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Now, we can verify that the deployment is exposed via the gateway at `http://$INGRESS_HOST/nginx-test`.

## Secure Istio Gateways and Cert-manager
In order to expose a service via HTTPS, it is required to configure a secure
Istio Gateway. For this task, we will use cert-manager to issue a certificate
for the Istio IngressGateway address and provide it to the Secure `Gateway`.

To install the Cert-manager, run:
```
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.0/cert-manager.yaml
```

### Create a Certificate Authority
First, we need to create a CA key and certificate to provide to the Cert-manager
`ClusterIssuer`. The CA is meant to function as an internal tool for creating certificates.
We will use [cfssl](https://github.com/cloudflare/cfssl) but any other appropriate
tool can be used instead.

Create a CSR (Certificate Signing Request) file in json format. For example, `csr.json`:
```json
{
    "CN": "Homelab, Inc.",
    "key": {
           "algo": "rsa",
           "size": 2048
    },
    "names": [
             {
                    "C": "US",
                    "L": "San Francisco",
                    "O": "Homelab",
                    "OU": "PVE",
                    "ST": "California"
             }
    ]
}
```

Then, run `cfssl` to generate the initial CA key and certificate:
```
cfssl gencert -initca csr.json | cfssljson -bare ca
```

Create a Kubernetes Secret to hold the key and certificate, as per [cert-manager docs](https://cert-manager.io/docs/configuration/ca/#deployment):
```
kubectl create secret tls ca-secret \
  --cert=ca.pem \
  --key=ca-key.pem
```

### Create an `Issuer` and issue a `Certificate` for the IngressGateway

> It is important to deploy the certificate into the same namespace where the istio-ingressgateway
is running so it can mount it. [Link to the documentation](https://istio.io/latest/docs/ops/integrations/certmanager/#istio-gateway).

To create a self-signed `ClusterIssuer`, run:
```
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: ca-issuer
  namespace: istio-system
spec:
  ca:
    secretName: ca-secret
EOF
```
More issuer configuration options available in the [Cert-manager docs](https://cert-manager.io/docs/configuration/).

Discover the `IngressGateway` IP address to use in the certificate:
```
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway --namespace istio-system -o yaml -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

The `Certificate` would look as follows (we'll be using the IP address from the previous step in the `ipAddresses` field):
```
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: gateway-cert
  namespace: istio-system
spec:
  secretName: gateway-cert
  ipAddresses:
  - "${INGRESS_HOST}"
  duration: 2160h # 90d
  renewBefore: 360h # 15d
  subject:
    organizations:
      - Homelab
  issuerRef:
    name: ca-issuer
    kind: Issuer
EOF
```

Verify the `Certificate` is created:
```
kubectl get cert -o wide -n istio-system

NAME           READY   SECRET         ISSUER      STATUS                                          AGE
gateway-cert   True    gateway-cert   ca-issuer   Certificate is up to date and has not expired   5s
```

### Create a secure Istio `Gateway`
Create a secure Istio `Gateway` that uses the certificate created at the previous step.
The `Gateway` can be created in any namespace:
```
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: secure-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPs
    tls:
      mode: SIMPLE
      credentialName: gateway-cert
    hosts:
    - "*"
EOF
```

And now we need to create a `VirtualService` to route the traffic. We'll use the
Nginx deployment from the [previous step](#example-deployment-exposed-via-istio-ingress-gateway).

```
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
 name: nginx-secure
spec:
 hosts:
 - "*"
 gateways:
 - secure-gateway
 http:
 - name: "nginx-secure"
   match:
   - uri:
       prefix: "/nginx-secure"
   rewrite:
     uri: "/"
   route:
   - destination:
       host: nginx.default.svc.cluster.local
       port:
         number: 80
EOF
```

Now, we can verify that the deployment is exposed via the gateway at `https://$INGRESS_HOST/nginx-secure`.

## Container Attached Storage
There is a plenty of storage solutions on Kubernetes. At the moment of writing,
[OpenEBS](https://openebs.io/) looked like a good fit for having storage installed
with minimal friction.

For the homelab setup, a [local hostpath](https://openebs.io/docs/user-guides/localpv-hostpath)
provisioner should be sufficient, however, OpenEBS provides multiple options for
a replicated storage backing Persistent Volumes.

To use only host-local Persistent Volumes, it is sufficient to install a lite
version of OpenEBS:
```
kubectl apply -f https://openebs.github.io/charts/openebs-operator-lite.yaml
```

Once the Operator is installed, create a `StorageClass` and annotate it as **default**:
```
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-hostpath
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
    openebs.io/cas-type: local
    cas.openebs.io/config: |
      - name: StorageType
        value: "hostpath"
      - name: BasePath
        value: "/var/openebs/local/"
provisioner: openebs.io/local
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF
```

## Verifying the installation
The following instructions are based on the official [OpenEBS documentation](https://openebs.io/docs/user-guides/localpv-hostpath#install-verification).

Create a `PersistentVolumeClaim`:
```
kubectl apply -f - <<EOF
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: local-hostpath-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1G
EOF
```

Create a `Pod` to consume the PVC:
```
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-openebs-volume
spec:
  volumes:
  - name: local-storage
    persistentVolumeClaim:
      claimName: local-hostpath-pvc
  containers:
  - name: main
    image: busybox
    command:
       - sh
       - -c
       - 'while true; do echo "`date` [`hostname`] Hello from OpenEBS Local PV." >> /mnt/store/greet.txt; sleep $(($RANDOM % 5 + 300)); done'
    volumeMounts:
    - mountPath: /mnt/store
      name: local-storage
EOF
```

Verify the data is written to the volume:
```
kubectl exec test-openebs-volume -- cat /mnt/store/greet.txt

# Example output:
Fri Nov 12 01:22:22 UTC 2021 [test-openebs-volume] Hello from OpenEBS Local PV.
```

You might also want to `kubectl describe pod test-openebs-volume` to check the details
about the mounted volume.

Cleanup:
```
kubectl delete pod test-openebs-volume
kubectl delete pvc local-hostpath-pvc
```

## Exposing Kubernetes Dashboard via Secure Istio Gateway

**TODO:** add information on security implications

In order to expose the Kubernetes Dashboard via Istio Ingress Gaway, it is
important to take into account that the Dashboard is running as a HTTPS service but
the previously deployed `Gateway` terminates TLS and sends unencrypted traffic to
the upstream services. Istio provides a custom resource called `DestinationRule`
that allows to define traffic and load balancing policies for the upstream services.

> NOTE: In the following example, the Kubernetes Dashboard will be exposed at the
root path of the URL: `https://<endpoint URL>/`. Making it available at a subpath
turned out to be a time consuming initiative involving EnvoyFilter or Nginx
Proxy Pods. None of these seems to be worth the effort for the HomeLab environment,
so in this guide the Dashboard UI will be available at the root URL path of the
Ingress.

```
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kubernetes-dashboard
  namespace: kubernetes-dashboard
spec:
  hosts:
  - "*"
  gateways:
  - default/secure-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: kubernetes-dashboard.kubernetes-dashboard.svc.cluster.local
        port:
          number: 443
EOF
```

```
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: kubernetes-dashboard
  name: kubernetes-dashboard
spec:
  host: kubernetes-dashboard.kubernetes-dashboard.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
EOF
```

Now, we can access the dashboard via the gateway at `https://$INGRESS_HOST/`.

A shortcut for the Ingress host discovery:
```
export INGRESS_HOST=$(kubectl get svc istio-ingressgateway --namespace istio-system -o yaml -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```
