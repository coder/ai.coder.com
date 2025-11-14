terraform {}

variable "patches" {
  type = list(object({
    op    = string
    path  = string
    value = optional(any)
  }))
  # Added validation because invalid JSON Patch operations cause runtime errors
  validation {
    condition     = alltrue([for p in var.patches : contains(["add", "remove", "replace", "move", "copy", "test"], p.op)])
    error_message = "Each patch op must be one of: add, remove, replace, move, copy, test."
  }
  # Added validation because invalid JSON Patch paths cause runtime errors
  validation {
    condition     = alltrue([for p in var.patches : p.path != "" && can(regex("^/", p.path))])
    error_message = "Each patch path must not be empty and must start with /."
  }
}

output "manifest" {
  value = yamlencode(var.patches)
}