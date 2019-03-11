variable "aws_region" {
  description = "Oregon region"
  default     = "us-west-2"
}

variable "ip_address" {
  description = "Your IP Address to restrict access to the scanner interaces."
  default     = "0.0.0.0/32"
}

variable "key_name" {
  description = "The name of the key that will be applied to all instances for authentication."
  default     = "testing-key"
}

variable "red_hat_ami" {
  description = "Redhat AMI ID"
  default     = "ami-036affea69a1101c9"
}
