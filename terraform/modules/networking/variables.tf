variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_id" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}
