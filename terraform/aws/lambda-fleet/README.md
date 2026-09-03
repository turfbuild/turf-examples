# AWS Lambda Fleet

Deploys a fleet of identical AWS Lambda functions behind one shared execution
role, then patches all of them in place by changing a single variable.

The interesting run is the second one. Most infrastructure work is not standing
things up — it is changing a lot of things that already exist, at once, without
breaking any of them. Re-running this example with a different `greeting` plans
exactly *N* update-in-place changes and nothing else.

## Resources Created

- `aws_iam_role.lambda_exec` — one execution role shared by the whole fleet
- `aws_iam_role_policy_attachment.lambda_policy` — attaches `AWSLambdaBasicExecutionRole`
- `aws_lambda_function.hello[*]` — `fleet_size` copies of the same handler
- `data.archive_file.hello` — builds the deployment package from `hello-world/` at plan time

## Prerequisites

1. An AWS account with permission to manage Lambda functions and IAM roles.
2. Credentials on the default chain — `aws sso login`, `AWS_PROFILE`, or
   `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. The provider reads them from the
   environment of the process running turf.
3. Nothing else. There is no S3 bucket, no API Gateway, and no build step: the
   `.zip` is produced by the `archive_file` data source when you plan.

## Usage

```bash
turf -C terraform/aws/lambda-fleet up
```

Then confirm the functions actually run:

```bash
aws lambda invoke --function-name turf-hello-0 \
  --payload '{}' --cli-binary-format raw-in-base64-out /tmp/out.json
cat /tmp/out.json
# {"statusCode":200,...,"message":"Hello, World!","function":"turf-hello-0"}
```

### Patch the fleet

Change the greeting and run `up` again. Every function is updated in place —
no replacements, no downtime, one change per function:

```bash
turf -C terraform/aws/lambda-fleet up --var greeting='Patched by Turf'
```

```bash
aws lambda invoke --function-name turf-hello-0 \
  --payload '{}' --cli-binary-format raw-in-base64-out /tmp/out.json
cat /tmp/out.json
# {"statusCode":200,...,"message":"Patched by Turf","function":"turf-hello-0"}
```

The handler reads `GREETING` from its environment rather than a string literal
precisely so that this is checkable by invoking the function, instead of only by
reading the state file.

### Resize the fleet

```bash
turf -C terraform/aws/lambda-fleet up --var fleet_size=25
```

Growing the fleet creates only the new functions; the existing ones plan as
no-ops. Shrinking destroys the ones above the new count.

### Change the handler

Edit `hello-world/hello.js` and run `up`. The `archive_file` data source
rebuilds the package, `source_code_hash` moves with it, and every function
re-deploys the new code.

## Variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `aws_region` | `us-west-2` | Region for all resources |
| `name_prefix` | `turf-hello` | Prefix for the role and every function name |
| `fleet_size` | `5` | How many functions to deploy |
| `greeting` | `Hello, World!` | `GREETING` env var — the patch surface |
| `runtime` | `nodejs22.x` | Lambda runtime |

## Outputs

- `function_names` — names of every function in the fleet
- `function_arns` — ARNs of every function in the fleet
- `role_arn` — ARN of the shared execution role
- `greeting` — the greeting currently deployed

## Cost

Effectively zero. Lambda bills invocations and duration, not existence, so idle
functions cost nothing however many you create; code storage is free well past
what this example uses, and IAM is free. A handful of verification invokes sits
inside the perpetual free tier.

## Cleanup

```bash
turf -C terraform/aws/lambda-fleet destroy
```

One thing `destroy` will leave behind: AWS creates a CloudWatch log group named
`/aws/lambda/<function>` the first time a function is invoked. Those groups are
not declared in this configuration, so turf does not manage them and correctly
does not delete them. Remove them by hand if you want a clean account:

```bash
aws logs delete-log-group --log-group-name /aws/lambda/turf-hello-0
```
