package veriqta.terraform
import rego.v1

changes := object.get(input,"resource_changes",[])

violations contains {"address":r.address,"rule":"destructive","reason":"deletion or replacement"} if {
 some r in changes
 "delete" in r.change.actions
}
violations contains {"address":r.address,"rule":"encryption","reason":"RDS encryption is not proven"} if {
 some r in changes
 r.type == "aws_db_instance"
 not "delete" in r.change.actions
 object.get(r.change.after,"storage_encrypted",false) != true
}
violations contains {"address":r.address,"rule":"public-database","reason":"public RDS access"} if {
 some r in changes
 r.type == "aws_db_instance"
 r.change.after.publicly_accessible == true
}
violations contains {"address":r.address,"rule":"owner","reason":"missing owner tag"} if {
 some r in changes
 r.mode == "managed"
 r.type in {"aws_db_instance","aws_vpc","aws_s3_bucket","aws_eks_cluster","aws_iam_role","aws_sqs_queue"}
 object.get(object.get(object.get(r.change,"after",{}),"tags_all",{}),"Owner","") == ""
}
violations contains {"address":r.address,"rule":"public-ingress","reason":"public management port"} if {
 some r in changes
 r.type == "aws_vpc_security_group_ingress_rule"
 cidr := object.get(r.change.after,"cidr_ipv4",object.get(r.change.after,"cidr_ipv6",""))
 cidr in {"0.0.0.0/0","::/0"}
 not "delete" in r.change.actions
}
violations contains {"address":r.address,"rule":"iam-review","reason":"all IAM policy changes require policy-specific review"} if {
 some r in changes
 r.type in {"aws_iam_policy","aws_iam_role_policy"}
 r.change.actions != ["no-op"]
}

violations contains {"address":r.address,"rule":"unknown-ingress","reason":"unresolved network policy"} if {
 some r in changes
 r.type == "aws_vpc_security_group_ingress_rule"
 some key in {"cidr_ipv4","cidr_ipv6","ip_protocol","from_port","to_port"}
 object.get(object.get(r.change,"after_unknown",{}),key,false) == true
}
