# frozen_string_literal: true

require_relative "../../model"

class CustomerAwsAccount < Sequel::Model
  include ResourceMethods
  one_to_one :private_subnet_aws_resource, key: :customer_aws_account_id
  one_to_one :nic_aws_resource, key: :customer_aws_account_id

  def self.ubid_type
    UBID::TYPE_ETC
  end
end
