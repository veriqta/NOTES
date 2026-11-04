package veriqta.terraform_test
import rego.v1
import data.veriqta.terraform.violations

test_database_replacement if {
 v := violations with input as {"resource_changes":[{"address":"db","type":"aws_db_instance","change":{"actions":["delete","create"],"after":{"storage_encrypted":true}}}]}
 some finding in v
 finding.rule == "destructive"
}
test_public_database if {
 v := violations with input as {"resource_changes":[{"address":"db","type":"aws_db_instance","change":{"actions":["update"],"after":{"storage_encrypted":true,"publicly_accessible":true}}}]}
 some finding in v
 finding.rule == "public-database"
}
