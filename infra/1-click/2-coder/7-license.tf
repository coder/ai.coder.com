variable "coder_license" {
  type      = string
  default   = ""
  sensitive = true
}

# resource "coderd_license" "enterprise" {
#   license = var.coder_license
# }

# data "http" "get-license" {

#   depends_on = [data.http.first-user]

#   url = "https://${data.dns_a_record_set.coder.addrs[0]}/api/v2/users/login"
#   insecure = true
#   method = "POST"
#   request_headers = {
#     Host = var.domain_name
#     Accept = "application/json"
#   }
#   request_body = jsonencode({
#     email    = var.coder_admin_email
#     password = var.coder_admin_password
#   })
# }