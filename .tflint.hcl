config {
  module = true
  force  = false
}

plugin "aws" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_unused_required_providers" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true

  format = "snake_case"
}

rule "aws_instance_invalid_type" {
  enabled = true
}

rule "aws_resource_missing_tags" {
  enabled = true

  tags = [
    "Environment",
    "Project",
    "Owner"
  ]
}
