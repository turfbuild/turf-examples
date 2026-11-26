output "function_names" {
  description = "Names of every function in the fleet."
  value       = aws_lambda_function.hello[*].function_name
}

output "function_arns" {
  description = "ARNs of every function in the fleet."
  value       = aws_lambda_function.hello[*].arn
  # An ARN carries the account id. Sensitive keeps it out of a chat transcript
  # and a screen share; read it with show_sensitive when you need it.
  sensitive = true
}

output "urls" {
  description = "Public URL of every function in the fleet."
  value       = aws_lambda_function_url.public[*].function_url
}

output "role_arn" {
  description = "ARN of the shared execution role."
  value       = aws_iam_role.lambda_exec.arn
  sensitive   = true
}

output "role_name" {
  description = "Name of the shared execution role. It changes when the role is rotated."
  value       = aws_iam_role.lambda_exec.name
}

output "greeting" {
  description = "The greeting currently deployed to the fleet."
  value       = var.greeting
}
