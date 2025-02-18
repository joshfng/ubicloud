# frozen_string_literal: true

require "aws-sdk-ec2"

class Prog::Aws::Allocator < Prog::Base
  subject_is :private_subnet_aws_resource

  label def create_aws_subnet
    vpc_response = client.create_vpc({cidr_block: "10.0.0.0/16", amazon_provided_ipv_6_cidr_block: true})
    private_subnet_aws_resource.update(vpc_id: vpc_response.vpc.vpc_id)
    hop_wait_vpc_created
  end

  label def wait_vpc_created
    vpc = client.describe_vpcs({filters: [{name: "vpc-id", values: [private_subnet_aws_resource.vpc_id]}]}).vpcs[0]
    puts "vpc: #{vpc}"
    if vpc.state == "available"
      hop_create_subnet
    end
    nap 1
  end

  label def create_subnet
    vpc_response = client.describe_vpcs({filters: [{name: "vpc-id", values: [private_subnet_aws_resource.vpc_id]}]}).vpcs[0]
    ipv_6_cidr_block = vpc_response.ipv_6_cidr_block_association_set[0].ipv_6_cidr_block.gsub("/56", "")
    subnet_response = client.create_subnet({
      vpc_id: vpc_response.vpc_id,
      cidr_block: "10.0.1.0/24",
      ipv_6_cidr_block: "#{ipv_6_cidr_block}/64",
      availability_zone: "us-east-1a"
    })

    subnet_id = subnet_response.subnet.subnet_id
    # Enable auto-assign ipv_6 addresses for the subnet
    client.modify_subnet_attribute({
      subnet_id: subnet_id,
      assign_ipv_6_address_on_creation: {value: true}
    })
    private_subnet_aws_resource.update(subnet_id: subnet_id)
    hop_wait_subnet_created
  end

  label def wait_subnet_created
    subnet_response = client.describe_subnets({filters: [{name: "subnet-id", values: [private_subnet_aws_resource.subnet_id]}]}).subnets[0]
    if subnet_response.state == "available"
      hop_create_route_table
    end
    nap 1
  end

  label def create_route_table
    # Step 3: Update the route table for ipv_6 traffic
    route_table_response = client.describe_route_tables({
      filters: [{name: "vpc-id", values: [private_subnet_aws_resource.vpc_id]}]
    })
    route_table_id = route_table_response.route_tables[0].route_table_id
    private_subnet_aws_resource.update(route_table_id: route_table_id)
    internet_gateway_response = client.create_internet_gateway
    internet_gateway_id = internet_gateway_response.internet_gateway.internet_gateway_id
    private_subnet_aws_resource.update(internet_gateway_id: internet_gateway_id)
    client.attach_internet_gateway({
      internet_gateway_id: internet_gateway_id,
      vpc_id: private_subnet_aws_resource.vpc_id
    })

    client.create_route({
      route_table_id: route_table_id,
      destination_ipv_6_cidr_block: "::/0",
      gateway_id: internet_gateway_id
    })

    client.create_route({
      route_table_id: route_table_id,
      destination_ipv_6_cidr_block: "::/0",
      gateway_id: internet_gateway_id
    })

    pop "subnet created"
  end

  label def create_network_interface
    # Step 4: Enable prefix delegation on the network interface
    network_interface_response = client.create_network_interface({
      subnet_id: private_subnet_aws_resource.subnet_id,
      ipv_6_prefix_count: 1 # Automatically assigns an ipv_6 prefix
    })
    network_interface_id = network_interface_response.network_interface.network_interface_id
    nic_aws_resource.update(network_interface_id: network_interface_id)
    hop_wait_network_interface_created
  end

  label def wait_network_interface_created
    network_interface_response = client.describe_network_interfaces({filters: [{name: "network-interface-id", values: [nic_aws_resource.network_interface_id]}]}).network_interfaces[0]
    if network_interface_response.status == "available"
      eip_response = client.allocate_address({
        domain: "vpc" # Required for VPC-based instances
      })

      # Associate the Elastic IP with your network interface
      client.associate_address({
        allocation_id: eip_response.allocation_id,
        network_interface_id: nic_aws_resource.network_interface_id
      })

      # nic_aws_resource.update(elastic_ip_id: eip_response.allocation_id)
      pop "eip created"
    end

    nap 1
  end

  label def launch_instance
    key_pair_response = client.create_key_pair({
      key_name: "aws-us-east-1-#{nic_aws_resource.id}"
    })
    key_pair_id = key_pair_response.key_pair.key_pair_id
    nic_aws_resource.update(key_pair_id: key_pair_id)

    instance_response = client.run_instances({
      image_id: "ami-04b4f1a9cf54c11d0", # Replace with an appropriate AMI ID for your region
      instance_type: "t2.micro",
      key_name: key_pair_id,
      min_count: 1,
      max_count: 1,
      network_interfaces: [{
        network_interface_id: nic_aws_resource.network_interface_id,
        device_index: 0
      }],
      placement: {
        availability_zone: "us-east-1a" # Replace with your desired AZ
      },
      block_device_mappings: [
        {
          device_name: "/dev/xvda", # Root volume device name
          ebs: {
            volume_size: 8, # Size in GiB
            delete_on_termination: true, # Automatically delete when instance is terminated
            volume_type: "gp2" # General Purpose SSD
          }
        }
      ]
    })
    instance_id = instance_response.instances[0].instance_id
    nic_aws_resource.update(instance_id: instance_id)
    hop_wait_instance_created
  end

  label def wait_instance_created
    instance_response = client.describe_instances({filters: [{name: "instance-id", values: [nic_aws_resource.instance_id]}]}).reservations[0].instances[0]
    puts "instance_response: #{instance_response}"
    if instance_response.state.name == "running"
      hop_wait
    end
    nap 1
  end

  label def wait
    nap 1
  end

  def nic_aws_resource
    @nic_aws_resource ||= NicAwsResource[strand.stack.first["nic_id"]]
  end

  def access_key
    private_subnet_aws_resource.customer_aws_account.aws_account_access_key
  end

  def secret_key
    private_subnet_aws_resource.customer_aws_account.aws_account_secret_access_key
  end

  def region
    private_subnet_aws_resource.customer_aws_account.location
  end

  def client
    @client ||= Aws::EC2::Client.new(access_key_id: access_key, secret_access_key: secret_key, region: region)
  end
end
