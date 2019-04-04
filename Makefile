.PHONY : ssh

.DEFAULT_GOAL := ssh

# Ubuntu 18.04 with GitLab Runner, Docker, and Docker Machine
image_id ?= ami-0b316c366679a59d7
ssh_user ?= ubuntu
id := gitlab-ci-bastion

# We use this rule pattern to make sure the checkpoint file is not created
# unless the command exits successfully:
#
# target :
# 	command > $@.tmp
# 	mv $@.tmp $@

# Create the key pair.
key :
	touch $@.tmp
	chmod 600 $@.tmp
	aws ec2 create-key-pair \
		--key-name ${id}-key \
		--query 'KeyMaterial' \
		--output text \
		> $@.tmp
	mv $@.tmp $@

# Launch the instance.
instance : key
	aws ec2 run-instances \
		--count 1 \
		--image-id ${image_id} \
		--instance-type t3.micro \
		--key-name ${id}-key \
		--security-groups gitlab-runners \
		--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value="GitLab Runner Bastion"}]' \
		--query 'Instances[0].InstanceId' \
		--output text \
		| tee $@.tmp
	mv $@.tmp $@

# We deliberately use recursive expansion to read IDs from checkpoints.
instance_id = $(shell cat instance)

# Wait for the instance to reach the "running" state.
running : instance
	aws ec2 wait instance-running --instance-ids ${instance_id}
	touch $@

# Get the public IP address for the instance.
address : running
	aws ec2 describe-instances \
		--instance-ids ${instance_id} \
		--query 'Reservations[0].Instances[0].PublicIpAddress' \
		--output text \
		| tee $@.tmp
	mv $@.tmp $@

address = $(shell cat address)

# Connect to the instance.
ssh : address key running
	ssh \
		-o UserKnownHostsFile=/dev/null \
		-o StrictHostKeyChecking=no \
		-o PasswordAuthentication=no \
		-i key \
		${ssh_user}@${address}

clean :
	-aws ec2 terminate-instances --instance-ids ${instance_id}
	-aws ec2 delete-key-pair --key-name ${id}-key
	rm -f key instance running address
