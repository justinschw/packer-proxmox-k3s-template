packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "iso_file" {
  type = string
}

variable "cloudinit_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "cores" {
  type    = string
  default = "2"
}

variable "disk_format" {
  type    = string
  default = "raw"
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "disk_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "cpu_type" {
  type    = string
  default = "kvm64"
}

variable "memory" {
  type    = string
  default = "2048"
}

variable "network_vlan" {
  type    = string
  default = ""
}

variable "machine_type" {
  type    = string
  default = ""
}

variable "proxmox_api_password" {
  type      = string
  sensitive = true
}

variable "proxmox_api_user" {
  type = string
}

variable "proxmox_host" {
  type = string
}

variable "proxmox_node" {
  type = string
}

source "proxmox-iso" "debian" {
  proxmox_url              = "https://${var.proxmox_host}/api2/json"
  insecure_skip_tls_verify = true
  username                 = var.proxmox_api_user
  token                    = var.proxmox_api_password

  template_description = "Built from ${basename(var.iso_file)} on ${formatdate("YYYY-MM-DD hh:mm:ss ZZZ", timestamp())}"
  node                 = var.proxmox_node
  network_adapters {
    bridge   = "vmbr0"
    firewall = true
    model    = "virtio"
    vlan_tag = var.network_vlan
  }
  disks {
    disk_size    = var.disk_size
    format       = var.disk_format
    io_thread    = true
    storage_pool = var.disk_storage_pool
    type         = "scsi"
  }
  scsi_controller = "virtio-scsi-single"

  http_directory = "./"
  boot_wait      = "10s"
  boot_command   = ["<esc><wait>auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"]
  boot_iso {
    type = "scsi"
    iso_file = var.iso_file
    unmount = true
  }

  cloud_init              = true
  cloud_init_storage_pool = var.cloudinit_storage_pool

  vm_name  = "debian-13-k3s-template"
  cpu_type = var.cpu_type
  os       = "l26"
  memory   = var.memory
  cores    = var.cores
  sockets  = "1"
  machine  = var.machine_type

  # Note: this password is needed by packer to run the file provisioner, but
  # once that is done - the password will be set to random one by cloud init.
  ssh_password = "packer"
  ssh_username = "root"
  ssh_timeout  = "120m"
  ssh_port = 22
}

build {
  sources = ["source.proxmox-iso.debian"]


  provisioner "file" {
    destination = "/etc/cloud/cloud.cfg"
    source      = "cloud.cfg"
  }

  provisioner "shell" {
    inline = [
      # k3s installation
      "curl -sfL https://get.k3s.io | sh -",
      "mkdir -p /etc/systemd/system/k3s.service.d",

      # cloud-init
      "systemctl enable qemu-guest-agent",
      "echo 'datasource_list: [ NoCloud, ConfigDrive ]' | tee /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "echo 'disable_root: true' | tee -a /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "echo 'ssh_pwauth: false' | tee -a /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "cloud-init clean --machine-id",
      "rm -rf /var/lib/cloud/*",

      # build artifact creation
      "echo debian_version=$(cat /etc/debian_version) >> /tmp/versions.env",
      "echo k3s_version=$(k3s --version | awk '{print $3}') >> /tmp/versions.env",
      "echo '{ \"debian_version\": \"$(cat /etc/debian_version)\", \"k3s_version\": \"$(k3s --version | awk '{print $3}')\" }' > /tmp/build-info.json"
    ]
  }

  # k3s overrides
  provisioner "file" {
    destination = "/etc/systemd/system/k3s.service.d/override.conf"
    source      = "override.conf"
  }

  # Save artifacts
  provisioner "file" {
    source      = "/tmp/build-info.json"
    destination = "build-info.json"
    direction   = "download"
  }

  provisioner "file" {
    source      = "/etc/rancher/k3s/k3s.yaml"
    destination = "k3s.yaml"
    direction   = "download"
  }

}
