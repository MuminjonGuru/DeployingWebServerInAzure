variable "prefix" {
    description = "The prefix which should be used for all resources in this example"
}

variable "location" {
    description = "The Azure Region in which all resources in this example should be created."
}

variable "number_of_servers" {
  description = "Number of VMs to be created behind the Load Balancer"
  default = "2"
}

variable "server_name" {
  description = "prefix name of virtual machines generated."
  default = "GurusVM"
}

variable "username" {
    description = "The username for the VM Image"
}

variable "password" {
    description = "The Password for the VM Image"
}
