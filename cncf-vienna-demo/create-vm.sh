#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${1:-cncf-demo-1}"
ISO_PATH="/home/reza/Downloads/metal-amd64.iso"
DISK_PATH="$HOME/VirtualBox VMs/${VM_NAME}/${VM_NAME}.vdi"
DISK_SIZE_MB=10000
DISK2_PATH="$HOME/VirtualBox VMs/${VM_NAME}/${VM_NAME}-disk2.vdi"
DISK2_SIZE_MB=20480

# 1. Create the VM
VBoxManage createvm --name "$VM_NAME" --ostype "Linux_64" --register

# 2. CPU / RAM
VBoxManage modifyvm "$VM_NAME" --cpus 2 --memory 8192

# 3. Bridged networking - VM gets a real IP on the host's LAN, no port forwards needed
BRIDGE_IF="wlp0s20f3"
VBoxManage modifyvm "$VM_NAME" --nic1 bridged --bridgeadapter1 "$BRIDGE_IF"

# 4. SATA controller for the hard disk
VBoxManage storagectl "$VM_NAME" --name "SATA" --add sata --controller IntelAhci
VBoxManage createmedium disk --filename "$DISK_PATH" --size "$DISK_SIZE_MB"
VBoxManage storageattach "$VM_NAME" \
  --storagectl "SATA" \
  --port 0 --device 0 \
  --type hdd \
  --medium "$DISK_PATH"

# 4b. Secondary data disk
VBoxManage createmedium disk --filename "$DISK2_PATH" --size "$DISK2_SIZE_MB"
VBoxManage storageattach "$VM_NAME" \
  --storagectl "SATA" \
  --port 1 --device 0 \
  --type hdd \
  --medium "$DISK2_PATH"

# 5. IDE controller for the optical drive, then attach the Talos ISO
VBoxManage storagectl "$VM_NAME" --name "IDE" --add ide --controller PIIX4
VBoxManage storageattach "$VM_NAME" \
  --storagectl "IDE" \
  --port 0 --device 0 \
  --type dvddrive \
  --medium "$ISO_PATH"

# 6. Boot order: optical first (to boot the Talos installer), then disk
VBoxManage modifyvm "$VM_NAME" --boot1 disk --boot2 dvd --boot3 none --boot4 none

echo "VM '$VM_NAME' created. Start it with: VBoxManage startvm \"$VM_NAME\""
