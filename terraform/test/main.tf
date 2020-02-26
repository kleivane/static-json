terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region  = "eu-north-1"
  version = "~> 2.47"
}

locals {
  url         = "test.skysett.net"
  environment = "test"
}

variable "app_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = 80
}
variable "container_name" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = "static-json"
}

data "aws_iam_policy" "AmazonECSTaskExecutionRolePolicy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "backend" {
  name               = module.bekk_test_static_json_label.id
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = module.bekk_test_static_json_label.tags
}


resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.backend.name
  policy_arn = data.aws_iam_policy.AmazonECSTaskExecutionRolePolicy.arn
}

module "bekk_test_static_json_label" {
  source      = "git::https://github.com/cloudposse/terraform-null-label.git?ref=0.16.0"
  name        = "static-json"
  attributes  = ["public"]
  environment = local.environment


  tags = {
    "managed_by" = "terraform"
  }
}

resource "aws_ecs_task_definition" "backend" {
  family = module.bekk_test_static_json_label.id
  container_definitions = templatefile("task-definitions/service.json.tpl", {
    app_image = "525817628861.dkr.ecr.eu-north-1.amazonaws.com/static-json@sha256:6edd73d5bd08e7e2d36d203bd403254c1a8e53e0c89251c063780c1470736c19",
    app_port  = var.app_port
  })
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.backend.arn
  requires_compatibilities = ["FARGATE"]
  memory                   = "512"
  cpu                      = "256"
  tags                     = module.bekk_test_static_json_label.tags
}


resource "aws_ecs_service" "backend" {
  name            = module.bekk_test_static_json_label.id
  cluster         = aws_ecs_cluster.backend.id
  desired_count   = 1
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"

  network_configuration {
    #    security_groups = [aws_security_group.ecs_tasks.id]
    subnets = aws_subnet.private.*.id
  }

  #  load_balancer {
  #    target_group_arn = aws_alb_target_group.app.id
  #    container_name   = var.container_name
  #    container_port   = var.app_port
  #  }

  # Allow external changes without Terraform plan difference
  # Dermed kan desired_count kunne bruke autoscaling uten at terraform apply vil kjøre endringer
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [
    #    aws_alb_listener.front_end,
    aws_iam_role_policy_attachment.ecs_task_execution
  ]

  tags = module.bekk_test_static_json_label.tags

}

resource "aws_ecs_cluster" "backend" {
  name = module.bekk_test_static_json_label.id
  tags = module.bekk_test_static_json_label.tags
}
