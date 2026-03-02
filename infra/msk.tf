# MSK Serverless - Kafka for streaming (pay-per-throughput, scales to zero)
# Glue Streaming reads from Kafka; Lambda can produce/consume

data "aws_vpc" "default" {
  count   = var.enable_msk ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.enable_msk ? 1 : 0
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

resource "aws_msk_serverless_cluster" "main" {
  count = var.enable_msk ? 1 : 0

  cluster_name = replace(local.name, "-", "_")

  vpc_config {
    subnet_ids = data.aws_subnets.default[0].ids
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }
}
