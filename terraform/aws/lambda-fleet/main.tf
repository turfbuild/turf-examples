# A fleet of identical AWS Lambda functions behind one shared execution role.
#
# The point of the example is the SECOND run, not the first. Changing
# var.greeting rewrites an environment variable on every function in the fleet,
# so a re-plan is N update-in-place changes and nothing else — the shape a real
# fleet spends its life in. Changing var.fleet_size grows or shrinks it.

# The deployment package, built from source at plan time. The zip lands next to
# this configuration and is regenerated whenever hello-world/ changes, so
# source_code_hash below moves with the source and the fleet re-deploys.
data "archive_file" "hello" {
  type        = "zip"
  source_dir  = "${path.module}/hello-world"
  output_path = "${path.module}/hello-world.zip"
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

  filename         = data.archive_file.hello.output_path
  source_code_hash = data.archive_file.hello.output_base64sha256

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
