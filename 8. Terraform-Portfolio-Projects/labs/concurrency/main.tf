terraform { required_version = ">= 1.10, < 2.0" }
variable "release" {
  type    = string
  default = "v1"
}
resource "terraform_data" "release" { input = var.release }
output "release" { value = terraform_data.release.output }
