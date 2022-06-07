resource "proxmox_vm_qemu" "control_plane" {
  name              = "control-plane.k8s.cluster"
  target_node       = "${var.pm_node}"

  clone             = "ubuntu-2004-cloudinit-template"

  os_type           = "cloud-init"
  cores             = 4
  sockets           = "1"
  cpu               = "host"
  memory            = 2048
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "15G"
    type            = "scsi"
    storage         = "local-lvm"
    iothread        = 1
  }

  network {
    model           = "virtio"
    bridge          = "vmbr0"
  }

  # cloud-init settings
  # adjust the ip and gateway addresses as needed
  ipconfig0         = "ip=192.168.2.221/24,gw=192.168.2.1"
  sshkeys = file("${var.ssh_key_file}")
}


resource "proxmox_vm_qemu" "worker_nodes" {
  count             = 3
  name              = "worker-${count.index+1}.k8s.cluster"
  target_node       = "${var.pm_node}"

  clone             = "ubuntu-2004-cloudinit-template"

  os_type           = "cloud-init"
  cores             = 2
  sockets           = "1"
  cpu               = "host"
  memory            = 1024
  scsihw            = "virtio-scsi-pci"
  bootdisk          = "scsi0"

  disk {
    size            = "10G"
    type            = "scsi"
    storage         = "local-lvm"
    iothread        = 1
  }

  network {
    model           = "virtio"
    bridge          = "vmbr0"
  }

  # cloud-init settings
  # adjust the ip and gateway addresses as needed
  ipconfig0         = "ip=192.168.2.23${count.index+1}/24,gw=192.168.2.1"
  sshkeys = file("${var.ssh_key_file}")
}
