terraform { required_version = ">= 1.10, < 2.0" }
resource "terraform_data" "this" {
  input = { database = "veriqta-logical-database", schema = 1 }
}
output "database_identity" { value = terraform_data.this.id }
