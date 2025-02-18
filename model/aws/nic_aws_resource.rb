# frozen_string_literal: true

require_relative "../../model"

class NicAwsResource < Sequel::Model
  include ResourceMethods
  one_to_one :nic, key: :id
  one_to_one :customer_aws_account, key: :customer_aws_account_id

  def self.ubid_type
    UBID::TYPE_ETC
  end
end
