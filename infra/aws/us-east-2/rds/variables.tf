variable "profile" {
  type = string
}

variable "region" {
  description = "The aws region for database deployment"
  type        = string
}

variable "coder_db_rds_id" {
  description = "Database name"
  type        = string
}

variable "coder_username" {
  description = "Database root username"
  type        = string
}

variable "coder_db_name" {
  description = "Database name"
  type        = string
}

variable "db_subnet_group_name" {
  description = "RDS DB Subnet Group Name"
  type        = string
}

variable "private_subnet_suffix" {
  description = "The deployed private subnet's suffix for the database."
  type        = string
}

variable "vpc_name" {
  description = "The deployed vpc id for the database"
  type        = string
}

variable "allocated_storage" {
  description = "The allocated storage size in gb"
  default     = "20"
  type        = string
}

variable "engine_version" {
  description = "The version to deploy"
  default     = "15.7"
  type        = string
}

variable "instance_class" {
  description = "The size of db instance class to deploy"
  default     = "db.m5.large"
  type        = string
}