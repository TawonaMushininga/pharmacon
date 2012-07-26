require 'spree/core/validators/email'

module Spree
  class Order < ActiveRecord::Base
    include Spree::OrderComponents::Address
    include Spree::OrderComponents::LineItems
    include Spree::OrderComponents::Adjustments
    include Spree::OrderComponents::Payment
    include Spree::OrderComponents::Shipment

    token_resource

    attr_accessible :number, :shipping_method_id, :email, :use_billing, :special_instructions

    if Spree.user_class
      belongs_to :user, :class_name => Spree.user_class.to_s
    else
      belongs_to :user
    end

    has_many :state_changes, :as => :stateful
    has_many :inventory_units
    has_many :return_authorizations, :dependent => :destroy

    # Needs to happen before save_permalink is called
    before_validation :generate_order_number, :on => :create

    before_create :link_by_email

    # TODO: validate the format of the email as well (but we can't rely on authlogic anymore to help with validation)
    validates :email, :presence => true, :email => true, :if => :require_email

    make_permalink :field => :number

    class_attribute :update_hooks
    self.update_hooks = Set.new

    # order state machine (see http://github.com/pluginaweek/state_machine/tree/master for details)
    state_machine :initial => 'cart', :use_transactions => false do

      event :next do
        transition :from => 'cart',     :to => 'address'
        transition :from => 'address',  :to => 'delivery'
        transition :from => 'delivery', :to => 'payment', :if => :payment_required?
        transition :from => 'delivery', :to => 'complete'
        transition :from => 'confirm',  :to => 'complete'

        # note: some payment methods will not support a confirm step
        transition :from => 'payment',  :to => 'confirm',
                                        :if => Proc.new { |order| order.payment_method && order.payment_method.payment_profiles_supported? }

        transition :from => 'payment', :to => 'complete'
      end

      event :cancel do
        transition :to => 'canceled', :if => :allow_cancel?
      end
      event :return do
        transition :to => 'returned', :from => 'awaiting_return'
      end
      event :resume do
        transition :to => 'resumed', :from => 'canceled', :if => :allow_resume?
      end
      event :authorize_return do
        transition :to => 'awaiting_return'
      end

      before_transition :to => 'complete' do |order|
        begin
          order.process_payments!
        rescue Core::GatewayError
          !!Spree::Config[:allow_checkout_on_gateway_error]
        end
      end

      before_transition :to => 'delivery', :do => :remove_invalid_shipments!

      after_transition :to => 'complete', :do => :finalize!
      after_transition :to => 'delivery', :do => :create_tax_charge!
      after_transition :to => 'payment',  :do => :create_shipment!
      after_transition :to => 'resumed',  :do => :after_resume
      after_transition :to => 'canceled', :do => :after_cancel

    end

    def self.by_number(number)
      where(:number => number)
    end

    def self.between(start_date, end_date)
      where(:created_at => start_date..end_date)
    end

    def self.by_customer(customer)
      joins(:user).where("#{Spree.user_class.table_name}.email" => customer)
    end

    def self.by_state(state)
      where(:state => state)
    end

    def self.complete
      where('completed_at IS NOT NULL')
    end

    def self.incomplete
      where(:completed_at => nil)
    end

    # Use this method in other gems that wish to register their own custom logic that should be called after Order#updat
    def self.register_update_hook(hook)
      self.update_hooks.add(hook)
    end

    def to_param
      number.to_s.to_url.upcase
    end

    def completed?
      !! completed_at
    end

    # Indicates whether or not the user is allowed to proceed to checkout.  Currently this is implemented as a
    # check for whether or not there is at least one LineItem in the Order.  Feel free to override this logic
    # in your own application if you require additional steps before allowing a checkout.
    def checkout_allowed?
      line_items.count > 0
    end

    # Is this a free order in which case the payment step should be skipped
    def payment_required?
      total.to_f > 0.0
    end

    # Indicates whether there are any backordered InventoryUnits associated with the Order.
    def backordered?
      return false unless Spree::Config[:track_inventory_levels]
      inventory_units.backorder.present?
    end

    # Returns the relevant zone (if any) to be used for taxation purposes.  Uses default tax zone
    # unless there is a specific match
    def tax_zone
      zone_address = Spree::Config[:tax_using_ship_address] ? ship_address : bill_address
      Zone.match(zone_address) || Zone.default_tax
    end

    # Indicates whether tax should be backed out of the price calcualtions in cases where prices
    # include tax but the customer is not required to pay taxes in that case.
    def exclude_tax?
      return false unless Spree::Config[:prices_inc_tax]
      return tax_zone != Zone.default_tax
    end


    def allow_cancel?
      return false unless completed? and state != 'canceled'
      %w{ready backorder pending}.include? shipment_state
    end

    def allow_resume?
      # we shouldn't allow resume for legacy orders b/c we lack the information necessary to restore to a previous state
      return false if state_changes.empty? || state_changes.last.previous_state.nil?
      true
    end

    # Associates the specified user with the order.
    def associate_user!(user)
      self.user = user
      self.email = user.email
      # disable validations since they can cause issues when associating
      # an incomplete address during the address step
      save(:validate => false)
    end

    # FIXME refactor this method and implement validation using validates_* utilities
    def generate_order_number
      record = true
      while record
        random = "R#{Array.new(9){rand(9)}.join}"
        record = self.class.where(:number => random).first
      end
      self.number = random if self.number.blank?
      self.number
    end

    def name
      if (address = bill_address || ship_address)
        "#{address.firstname} #{address.lastname}"
      end
    end

    # Finalizes an in progress order after checkout is complete.
    # Called after transition to complete state when payments will have been processed
    def finalize!
      touch :completed_at
      InventoryUnit.assign_opening_inventory(self)
      # lock any optional adjustments (coupon promotions, etc.)
      adjustments.optional.each { |adjustment| adjustment.update_column('locked', true) }
      deliver_order_confirmation_email

      self.state_changes.create({
        :previous_state => 'cart',
        :next_state     => 'complete',
        :name           => 'order' ,
        :user_id        => (User.respond_to?(:current) && User.current.try(:id)) || self.user_id
      }, :without_protection => true)
    end

    def deliver_order_confirmation_email
      begin
        OrderMailer.confirm_email(self).deliver
      rescue Exception => e
        logger.error("#{e.class.name}: #{e.message}")
        logger.error(e.backtrace * "\n")
      end
    end

    # Helper methods for checkout steps
    def rate_hash
      @rate_hash ||= available_shipping_methods(:front_end).collect do |ship_method|
        next unless cost = ship_method.calculator.compute(self)
        ShippingRate.new( :id => ship_method.id,
                          :shipping_method => ship_method,
                          :name => ship_method.name,
                          :cost => cost)
      end.compact.sort_by { |r| r.cost }
    end

    def paid?
      payment_state == 'paid'
    end

    def insufficient_stock_lines
      line_items.select &:insufficient_stock?
    end

    def merge!(order)
      order.line_items.each do |line_item|
        self.add_variant(line_item.variant, line_item.quantity)
      end
      order.destroy
    end

    def empty!
      line_items.destroy_all
      adjustments.destroy_all
    end

    # Utility methods
    def completed_payment_total
      payments.completed.map(&:amount).sum
    end

    def line_item_total
      line_items.map(&:amount).sum
    end

    def eligible_adjustments_total
      adjustments.eligible.map(&:amount).sum
    end

    def last_payment_failed?
      payments.present? and payments.last.state == 'failed'
    end

    def update!
      OrderUpdater.new(self).update!
    end

    def build_line_item(attributes={})
      line_items.build(attributes)
    end

    private
      def link_by_email
        self.email = user.email if self.user
      end

      # Determine if email is required (we don't want validation errors before we hit the checkout)
      def require_email
        return true unless new_record? or state == 'cart'
      end

      def after_cancel
        restock_items!

        #TODO: make_shipments_pending
        OrderMailer.cancel_email(self).deliver
      end

      def restock_items!
        line_items.each do |line_item|
          InventoryUnit.decrease(self, line_item.variant, line_item.quantity)
        end
      end

      def after_resume
        unstock_items!
      end

      def unstock_items!
        line_items.each do |line_item|
          InventoryUnit.increase(self, line_item.variant, line_item.quantity)
        end
      end
  end
end
