resource "aws_autoscaling_group" "main" {
  count = var.ha_mode ? 1 : 0

  name                = var.name
  max_size            = 1
  min_size            = 1
  desired_capacity    = 1
  health_check_type   = "EC2"
  vpc_zone_identifier = [var.subnet_id]

  launch_template {
    id = aws_launch_template.main.id
    # Using $Latest ensures ASG always uses the newest launch template version
    version = "$Latest"
  }

  # Depends on launch template to ensure it exists before ASG creation
  depends_on = [aws_launch_template.main]

  dynamic "tag" {
    for_each = lookup(var.tags, "Name", null) == null ? ["Name"] : []

    content {
      key                 = "Name"
      value               = var.name
      propagate_at_launch = true
    }
  }

  dynamic "tag" {
    for_each = var.tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = false
    }
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
    "GroupInServiceCapacity",
    "GroupPendingCapacity",
    "GroupStandbyCapacity",
    "GroupTerminatingCapacity",
    "GroupTotalCapacity",
    "WarmPoolDesiredCapacity",
    "WarmPoolWarmedCapacity",
    "WarmPoolPendingCapacity",
    "WarmPoolTerminatingCapacity",
    "WarmPoolTotalCapacity",
    "GroupAndWarmPoolDesiredCapacity",
    "GroupAndWarmPoolTotalCapacity"
  ]

  timeouts {
    delete = "15m"
  }

  # Lifecycle added because invalid subnet_id would cause ASG creation to fail
  lifecycle {
    precondition {
      condition     = length(var.subnet_id) > 0 && can(regex("^subnet-", var.subnet_id))
      error_message = "subnet_id must be a valid AWS subnet ID (starts with 'subnet-')"
    }
  }
}
