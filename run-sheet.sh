#!/bin/bash
# Pick a static Fail-over Virtual IP 
export CP_VIP=172.20.10.10

# Generating the secrets and
# Generating the machineconfig upon that
# STAND-ALONE
talosctl gen secrets
talosctl gen config talos-cncf-vienna-demo  https://$CP_VIP:6443 \
  --output-dir demo-1 \
  --config-patch-control-plane @patch.yaml \
  --with-secrets secrets.yaml \
  --with-docs=false \
  --with-examples=false \
  --with-cluster-discovery=true \
  --force

# Scripts to run VMs on VBox, each with  bridge network and on extra disk attached & --boot1 disk --boot2 dvd
./create-vm.sh talos-cncf-demo-1
./create-vm.sh talos-cncf-demo-2
VBoxManage startvm "talos-cncf-demo-1"
VBoxManage startvm "talos-cncf-demo-2"

# Move windows and activate Always-on-top 
# Read and Set the CP_DHCP_IP & W_DHCP_IP
export CP_DHCP_IP=172.20.10.2
export W_DHCP_IP=172.20.10.3

# Apply the generated machineconfigs
talosctl apply-config --insecure --nodes $CP_DHCP_IP --file demo-1/controlplane.yaml
talosctl apply-config --insecure --nodes $W_DHCP_IP --file demo-1/worker.yaml

# Check the IPs before continuing they might be changed


# The control-plane waits for the bootstrap command to apply the machineconfig
# and bootstrap the cluster
talosctl bootstrap --nodes $CP_DHCP_IP --endpoints $CP_DHCP_IP

# We use the Cluster VIP from now on, no longer DHCP IP...
# Set it in the talosconfig
talosctl config endpoint $CP_VIP && talosctl config node $CP_VIP


# See we can use it without shell
talosctl get services
talosctl get extensions
talosctl get disks
talosctl get mounts
talosctl usage --humanize /var/mnt/
talosctl ls /var/
talosctl etcd status
talosctl get addresses
talosctl edit machineconfig

talosctl upgrade --image factory.talos.dev/metal-installer/c9078f9419961640c712a8bf2bb9174933dfcf1da383fd8ea2b7dc21493f8bac:v1.14.0 -n $W_DHCP_IP

# Extract the KUBECONFIG
talosctl kubeconfig kc

# Feed flux to read the manifest and apply it to the cluster
flux push artifact oci://$CP_VIP:5000/apps:latest \
  --path="../apps" \
  --source="$(git config --get remote.origin.url)" \
  --revision="main@sha1:$(git rev-parse HEAD)" \
  --insecure-registry