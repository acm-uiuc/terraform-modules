variable "function_to_warm" {
  type        = string
  description = "Name of the lambda function to warm"
}

variable "log_retention_days" {
  type        = number
  description = "Number of days to retain lambda warmer logs."
  default     = 7
}

variable "invoke_rate_string" {
  type        = string
  description = "EventBridge rate string for how often to call the lambda."
  default     = "rate(4 minutes)"
}


variable "num_desired_warm_instances" {
  type        = number
  description = "Number of warm lambda instances desired"
  default     = 3
}

variable "region" {
  type        = string
  description = "AWS Region to deploy to"
}
