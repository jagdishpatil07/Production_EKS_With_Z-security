variable "ssh_key_name" {
  description = "The name of the SSH key pair to use for EKS worker nodes"
  type        = string
  default     = "KEY_AWS"
}
