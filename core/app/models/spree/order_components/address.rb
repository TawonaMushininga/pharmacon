require 'active_support/concern'

module Spree
  module OrderComponents
    module Address
      extend ActiveSupport::Concern
      included do
        attr_accessible :bill_address_attributes, :ship_address_attributes

        belongs_to :bill_address, :foreign_key => :bill_address_id,
                                  :class_name => "Spree::Address"
        alias_attribute :billing_address, :bill_address

        belongs_to :ship_address, :foreign_key => :ship_address_id,
                                  :class_name => "Spree::Address"
        alias_attribute :shipping_address, :ship_address

        accepts_nested_attributes_for :bill_address
        accepts_nested_attributes_for :ship_address

        before_validation :clone_billing_address, :if => :use_billing?
        attr_accessor :use_billing
        end

        def billing_firstname
          bill_address.try(:firstname)
        end

        def billing_lastname
          bill_address.try(:lastname)
        end

        private

        def clone_billing_address
          if bill_address and self.ship_address.nil?
            self.ship_address = bill_address.clone
          else
            self.ship_address.attributes = bill_address.attributes.except('id', 'updated_at', 'created_at')
          end
          true
        end

        def use_billing?
          @use_billing == true || @use_billing == "true" || @use_billing == "1"
        end
    end
  end
end
