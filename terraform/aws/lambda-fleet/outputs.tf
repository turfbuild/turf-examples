output "function_names" {
  description = "Names of every function in the fleet."
  value       = aws_lambda_function.hello[*].function_name
}

output "function_arns" {
  description = "ARNs of every function in the fleet."
  value       = aws_lambda_function.hello[*].arn
}

output "urls" {
  description = "Public URL of every function in the fleet."
  value       = aws_lambda_function_url.public[*].function_url
}

output "role_arn" {
  description = "ARN of the shared execution role."
  value       = aws_iam_role.lambda_exec.arn
}

output "greeting" {
  description = "The greeting currently deployed to the fleet."
  value       = var.greeting
}
