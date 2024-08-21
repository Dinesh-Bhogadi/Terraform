provider "aws" {
  region = "us-west-2"
}

# Create VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Create Subnet
resource "aws_subnet" "main_subnet" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"
}

# Security Group
resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "ec2_role" {
  name = "ec2_role"

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
}

resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# Launch Template
resource "aws_launch_template" "ec2_template" {
  name_prefix   = "example-template"
  image_id      = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI
  instance_type = "t2.micro"

  key_name = "your-key-name"  # replace with your key pair

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_instance_profile.name
  }

  network_interfaces {
    security_groups = [aws_security_group.allow_ssh.id]
    associate_public_ip_address = true
    subnet_id = aws_subnet.main_subnet.id
  }

  user_data = <<-EOF
              #!/bin/bash
              yum install -y aws-cli
              EOF
}

# Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.main_subnet.id]
  launch_template {
    id      = aws_launch_template.ec2_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "autoscaled-vm"
    propagate_at_launch = true
  }
}

# CloudWatch CPU Utilization Alarm - Scale Up
resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_name          = "scale_up_on_high_cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_up_policy.arn]
}

# CloudWatch CPU Utilization Alarm - Scale Down
resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_name          = "scale_down_on_low_cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 30

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_down_policy.arn]
}

# Scaling Policies
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "scale_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "scale_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}
