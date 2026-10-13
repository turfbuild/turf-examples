# The product's reference architecture: a small data lake. A VPC for the
# compute that will query it, a raw and a curated bucket, a Glue catalog
# database over them, an Athena workgroup to query with, and the role Athena
# and Glue assume. Ordinary Terraform; nothing here is Turf-specific.
#
# Resources rather than the registry's VPC module, on purpose: a step of
# installer.turf.hcl can be invoked before anything is applied (the README's
# "Run a step without an account"), and the engine evaluates the whole
# configuration for that — a module's count-indexed resources have no
# instances to index until they exist.

locals {
  name = "${var.product_name}-${var.tenant}"
  tags = {
    Product = var.product_name
    Tenant  = var.tenant
    Managed = "turf"
  }
}

resource "aws_vpc" "lake" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = local.name })
}

resource "aws_subnet" "private" {
  for_each = { a = 0, b = 1 }

  vpc_id            = aws_vpc.lake.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, each.value)
  availability_zone = "${var.region}${each.key}"
  tags              = merge(local.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_s3_bucket" "raw" {
  bucket = "${local.name}-raw"
  tags   = local.tags
}

resource "aws_s3_bucket" "curated" {
  bucket = "${local.name}-curated"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "curated" {
  bucket                  = aws_s3_bucket.curated.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_glue_catalog_database" "lake" {
  name         = replace(local.name, "-", "_")
  location_uri = "s3://${aws_s3_bucket.curated.bucket}/"
  tags         = local.tags
}

resource "aws_athena_workgroup" "lake" {
  name = local.name

  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.curated.bucket}/athena-results/"
    }
  }

  tags = local.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com", "athena.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lake" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "lake" {
  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.curated.arn, "${aws_s3_bucket.curated.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "lake" {
  name   = "${local.name}-lake"
  role   = aws_iam_role.lake.id
  policy = data.aws_iam_policy_document.lake.json
}
