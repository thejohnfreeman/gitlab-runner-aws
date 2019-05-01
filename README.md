# gitlab-runner-aws

This project documents configuration and tools for operating an autoscaling
continuous integration fleet powered by [GitLab][], Amazon Web Services (AWS),
Docker, and [Docker Machine][].

[GitLab]: https://gitlab.com/
[Docker Machine]: https://docs.docker.com/machine/overview/


## Overview

There are a number of very detailed and thorough documents on `gitlab.com`
covering how to autoscale GitLab Runners, but they are very long, slightly
scattered, and easy to get lost in. In this document, I will try to collate
the instructions that I used from them:

- [Runners autoscale configuration](https://docs.gitlab.com/runner/configuration/autoscale.html)
- [Install and register GitLab Runner for autoscaling with Docker Machine](https://docs.gitlab.com/runner/executors/docker_machine.html)
- [Autoscaling GitLab Runner on AWS](https://docs.gitlab.com/runner/configuration/runner_autoscale_aws)
- [Autoscale GitLab CI/CD runners and save 90% on EC2 costs](https://about.gitlab.com/2017/11/23/autoscale-ci-runners/)
- [Install a proxy container registry](https://docs.gitlab.com/runner/install/registry_and_cache_servers.html#install-a-proxy-container-registry)

These instructions assume you are familiar with AWS and GitLab Runner. I have
separately written beginner-friendly introductions to both:

- [A gentle introduction to scripting Amazon EC2](https://thejohnfreeman.com/blog/2019/01/18/a-gentle-introduction-to-scripting-amazon-ec2/)
- [Understanding GitLab Runner](https://thejohnfreeman.com/blog/2019/03/22/understanding-gitlab-runner/)

Here is the basic outline for deploying a new autoscaling GitLab Runner fleet
on AWS with Docker Machine:

1. Prepare an S3 bucket for caching build dependencies
1. Configure the host environment
1. Initialize Docker Machine
1. Register, configure, and start GitLab Runner


### 0. Prepare an S3 bucket for caching build dependencies

This step is necessary only if you want to enable
[caching](https://docs.gitlab.com/ee/ci/caching/). Creating an S3 bucket is
free; you are only charged for the data you store in it.

```shell
$ aws s3 mb s3://gitlab-runners-cache
```

Once you've created a bucket, you might want to [configure its
lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/dev/object-lifecycle-mgmt.html)
to delete old files. The [sample configuration in this
project](./lifecycle.json) deletes all files older than 90 days.

```shell
$ aws s3api put-bucket-lifecycle-configuration \
  --bucket gitlab-runners-cache \
  --lifecycle-configuration file://lifecycle.json
```


### 1. Configure the host environment

In short, you need a machine with GitLab Runner, Docker, and Docker Machine
installed on it. The easiest way is to launch an instance using an Amazon
Machine Image (AMI) published by the [ami-gitlab-runner
project](https://github.com/thejohnfreeman/ami-gitlab-runner), and [the
Makefile in this project](./Makefile)<sup id="ref-signals"
name="ref-signals">[1](#fn-signals)</sup> will help you do just that, once
you've satisfied its assumptions:

- You have the [AWS CLI](https://aws.amazon.com/cli/) installed and
    configured.
- You have a security group named `gitlab-runners` with port 22 open for
    inbound SSH connections.
- The AMI you've chosen (set by the `image_id` variable) is available in your
    default region.

If you need to change the AMI, region, or security group, then take a minute
to edit the Makefile. You can quickly inspect an AMI from the command line:

```shell
$ aws ec2 describe-images \
  --image-ids ami-0b316c366679a59d7 \
  --query 'Images[0].[Name, Tags]' \
  --output text \
```

When you run `make`, it will create a key pair, launch an instance, and
connect to it over ssh. On subsequent runs, it will ssh to the same instance
(assuming you have not removed any of the files it created in this directory).
If you want to tear down the instance and delete the key pair to start over,
run `make clean`.


### 2. Initialize Docker Machine

This step is the consequence of what I consider a failure of GitLab Runner to
properly initialize its dependencies. Sadly, it falls to us to
[create the first Docker Machine](
https://docs.gitlab.com/runner/executors/docker_machine.html#configuring-gitlab-runner
). Paraphrasing, the first Docker Machine using the EC2 driver will create an
AWS key pair in a manner unsafe for concurrency, but GitLab Runner
may create multiple Docker Machines concurrently, which means you have to
create the first Docker Machine before GitLab Runner does.

You can pass the same [driver
options](https://docs.docker.com/machine/drivers/aws/) you'll use for the
GitLab Runner to make sure they'll work. At the least, you should pass
`--amazonec2-region` so that the key pair is created in the right region. If
you don't pass `--amazonec2-security-group`, then Docker Machine will create
one called `docker-machine`.

```
$ docker-machine create \
  --driver amazonec2 \
  --amazonec2-region us-east-2 \
  --amazonec2-security-group gitlab-runners \
  test-machine
$ docker-machine rm -y test-machine
```


### 3. Register, configure, and start GitLab Runner

Once you've registered a GitLab Runner, you'll need to edit its configuration
for autoscaling. This project has an example [`config.toml`](./config.toml)
that you can copy from. You'll need to fill in your own AWS API keys. If any
part of the configuration is foreign to you, please consult the [advanced
configuration documentation][advanced].

[advanced]: https://docs.gitlab.com/runner/configuration/advanced-configuration.html

Do not use the option `amazonec2-private-address-only`. It prevents your
worker machines from reaching Docker Hub.

After you're finished editing the configuration, restart the service:

```shell
$ sudo systemctl restart gitlab-runner
```





<sup id="fn-signals" name="fn-signals">1</sup> It would be nice to have
a [Terraform][] template for launching the instance, but their [`aws_key_pair`
resource](https://www.terraform.io/docs/providers/aws/r/key_pair.html) is
incapable of creating a key pair (it can only use an existing key pair).
[↩](#ref-signals)

[Terraform]: https://www.terraform.io/
