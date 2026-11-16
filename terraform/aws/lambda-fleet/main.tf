# A fleet of identical AWS Lambda functions behind one shared execution role.
#
# The point of the example is the SECOND run, not the first. Changing
# var.greeting rewrites an environment variable on every function in the fleet,
# so a re-plan is N update-in-place changes and nothing else — the shape a real
# fleet spends its life in. Changing var.fleet_size grows or shrinks it.

# The deployment package, committed beside the configuration. The configuration
# only reads it, so it plans the same from a checkout and from a read-only
# mount (the examples image), and on whichever engine pod a step lands.
# Rebuild it after changing hello-world/ (README, "The deployment package"):
# source_code_hash below moves with the file and the fleet re-deploys.
locals {
  package = "${path.module}/hello-world.zip"
}

# One role shared by the whole fleet. Lambda needs only permission to write its
# own logs, which is exactly what AWSLambdaBasicExecutionRole grants.
resource "aws_iam_role" "lambda_exec" {
  name = "${var.name_prefix}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "hello" {
  count = var.fleet_size

  function_name = "${var.name_prefix}-${count.index}"
  role          = aws_iam_role.lambda_exec.arn

  filename         = local.package
  source_code_hash = filebase64sha256(local.package)

  runtime = var.runtime
  handler = "hello.handler"

  # The handler reads its greeting from the environment rather than a literal,
  # which is what makes a patch observable: invoking a function proves the new
  # value reached the running code, not merely the state file.
  environment {
    variables = {
      GREETING = var.greeting
    }
  }
}

# A public URL per function, so anything that can reach the internet can prove
# the fleet answers: you with curl, or the agent in the verify action
# (verify.turf.hcl). No IAM auth on the URL; the permission below is what AWS
# requires before an unauthenticated URL answers.
resource "aws_lambda_function_url" "public" {
  count = var.fleet_size

  function_name      = aws_lambda_function.hello[count.index].function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "public" {
  count = var.fleet_size

  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.hello[count.index].function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# The release marker. Its input changes whenever the greeting, the fleet's URLs
# or the function code change, so the verify action in verify.turf.hcl runs
# after the first create and after every patch, once for the whole fleet, with
# the real URLs.
resource "terraform_data" "rollout" {
  input = {
    greeting = var.greeting
    urls     = aws_lambda_function_url.public[*].function_url
    code     = filebase64sha256(local.package)
  }

  depends_on = [aws_lambda_permission.public]
}
