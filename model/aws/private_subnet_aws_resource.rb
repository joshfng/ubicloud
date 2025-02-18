# frozen_string_literal: true

require_relative "../../model"

class PrivateSubnetAwsResource < Sequel::Model
  include ResourceMethods
  one_to_one :private_subnet, key: :id
  many_to_one :customer_aws_account

  def self.ubid_type
    UBID::TYPE_ETC
  end
end
