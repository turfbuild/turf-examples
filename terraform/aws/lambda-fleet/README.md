# AWS Lambda Fleet

Deploys a fleet of identical AWS Lambda functions behind one shared execution
role, each with a public URL, then patches all of them in place by changing a
single variable. After every rollout a Turf action has the agent fetch each URL
and prove the fleet answers with the greeting the configuration declares.

The interesting run is the second one. Most infrastructure work is not standing
things up — it is changing a lot of things that already exist, at once, without
breaking any of them. Re-running this example with a different `greeting` plans
exactly *N* update-in-place changes and nothing else.

## Resources Created

- `aws_iam_role.lambda_exec` — one execution role shared by the whole fleet, its name generated from `name_prefix` so it can be rotated
- `aws_iam_role_policy_attachment.lambda_policy` — attaches `AWSLambdaBasicExecutionRole`
- `aws_lambda_function.hello[*]` — `fleet_size` copies of the same handler
- `aws_lambda_function_url.public[*]` and `aws_lambda_permission.public[*]` — a public URL per function
- `terraform_data.rollout` — the release marker the `verify` Turf action runs after

## Prerequisites

1. An AWS account with permission to manage Lambda functions and IAM roles.
2. Credentials the provider can find in Turf's engine, where it runs, not in your
   shell: the default profile in `~/.aws/config` (after `aws sso login`), a
   `profile` argument on the `provider "aws"` block, `AWS_PROFILE` in this
   directory's `mise.local.toml`, or `AWS_PROFILE` in `~/.homebrew/services/turf.env`
   (see [Running the examples](../../../README.md#running-the-examples)). An
   `AWS_PROFILE` exported in your shell does not reach the provider.
3. Nothing else. There is no S3 bucket, no API Gateway, and no build step: the
   package, `hello-world.zip`, is committed beside the configuration.

## Usage

```bash
turf -C terraform/aws/lambda-fleet up
```

The apply pauses once, at the `verify` Turf action
([`verify.turf.hcl`](verify.turf.hcl)): the agent driving Turf fetches every
function URL, checks each answers 200 with the declared greeting, and reports
back; a failed check halts the apply. tofu and terraform ignore that file by its
name.

Confirm it yourself with the `urls` output, or by invoking a function directly:

```bash
curl -s "$(turf -C terraform/aws/lambda-fleet output -json urls | jq -r '.[0]')"
# {"message":"Hello, World!","function":"turf-hello-0"}

aws lambda invoke --function-name turf-hello-0 \
  --payload '{}' --cli-binary-format raw-in-base64-out /tmp/out.json
cat /tmp/out.json
# {"statusCode":200,...,"message":"Hello, World!","function":"turf-hello-0"}
```

The URLs are public (`authorization_type = "NONE"`): anyone who has one can call
the function. They answer a greeting and nothing else; `destroy` removes them.

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

Edit `hello-world/hello.js`, rebuild the package, and run `up`:
`source_code_hash` moves with the file and every function re-deploys the new
code.

### The deployment package

`hello-world.zip` is committed, and the configuration only reads it. That is what
lets it run from a read-only mount (the [examples image](../../../README.md#configuration-images),
as [turfbuild/turf-kagent](https://github.com/turfbuild/turf-kagent) runs it) and
on an engine with several replicas, where a file written during the plan may not
be on the pod that applies. Rebuild it after changing the handler:

```bash
(cd terraform/aws/lambda-fleet/hello-world && zip -X ../hello-world.zip hello.js)
```

## Rotating the role

Replacing a resource though nothing in the configuration changed is `plan`'s
`replace` option, given at the round's plan gate (`tofu plan -replace`):

```text
up({ var: { … } })
plan({ convergence_id: "<from up>", replace: ["aws_iam_role.lambda_exec"] })
```

The plan shows both of Terraform's replacement orders at once:

- **the role is create-before-destroy**: its name is generated from a prefix and
  its `lifecycle` says `create_before_destroy`, so the new role is created
  first, every function is updated in place to assume it, and the old role is
  deleted last. The fleet answers the whole time, at the same URLs.
- **the policy attachment is destroy-then-create**, the default: the old one is
  detached before the new one is attached.

The role's ARN is part of `terraform_data.rollout`'s input, so the `verify`
action runs after a rotation and proves every function still answers.

Replacing a function is destroy-then-create, since two functions cannot share a
name. Name its URL and permission with it: AWS deletes both with the function,
and nothing in their arguments changes to say so.

```text
plan({ convergence_id: "<from up>", replace: [
  "aws_lambda_function.hello[0]",
  "aws_lambda_function_url.public[0]",
  "aws_lambda_permission.public[0]",
] })
```

## In CI/CD

[turfbuild/turf-agentic-workflows](https://github.com/turfbuild/turf-agentic-workflows)
runs this example from pull requests, with an agent in GitHub Agentic Workflows planning
on the pull request and applying to staging, then production, after the merge. Its
`infra/` is this configuration with an S3 backend and an `environment` per stage.

## In a cluster

[turfbuild/turf-kagent](https://github.com/turfbuild/turf-kagent) runs this example from
kagent on Kubernetes: the agent in a sandbox with no AWS credential, the engine holding a
key scoped to the fleet, a person approving every plan, and the agent fetching the URLs
through an egress policy that names them.

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
- `function_arns` — ARNs of every function in the fleet (sensitive: an ARN carries the account id)
- `urls` — public URL of every function in the fleet
- `role_arn` — ARN of the shared execution role (sensitive)
- `role_name` — name of the shared execution role; it changes when the role is rotated
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
