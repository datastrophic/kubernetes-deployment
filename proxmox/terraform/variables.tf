variable "pm_api_url" {
  default = "https://192.168.2.220:8006/api2/json"
}

variable "pm_node" {
  default = "pve"
}

variable "pm_user" {
  default = ""
}

variable "pm_password" {
  default = ""
}

variable "ssh_key_file" {
  default = "~/.ssh/id_rsa.pub"
}
