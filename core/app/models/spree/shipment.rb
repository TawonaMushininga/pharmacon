require 'ostruct'

module Spree
  class Shipment < ActiveRecord::Base
    belongs_to :order

    has_many :shipping_rates
    has_many :shipping_methods, :through => :shipping_rates

    belongs_to :address
    belongs_to :stock_location

    has_many :state_changes, :as => :stateful
    has_many :inventory_units, :dependent => :destroy
    has_one :adjustment, :as => :source, :dependent => :destroy

    before_create :generate_shipment_number
    after_save :ensure_correct_adjustment, :ensure_selected_shipping_rate, :update_order

    attr_accessor :special_instructions

    attr_accessible :order, :special_instructions, :stock_location_id,
                    :tracking, :address, :inventory_units, :selected_shipping_rate_id

    accepts_nested_attributes_for :address
    accepts_nested_attributes_for :inventory_units

    make_permalink :field => :number

    scope :with_state, lambda { |s| where(:state => s) }
    scope :shipped, with_state('shipped')
    scope :ready, with_state('ready')
    scope :pending, with_state('pending')
    scope :trackable, where("spree_shipments.tracking is not null
                             and spree_shipments.tracking != ''")

    def to_param
      number if number
      generate_shipment_number unless number
      number.to_s.to_url.upcase
    end

    def backordered?
      inventory_units.any? { |iu| iu.backordered? }
    end

    def shipped=(value)
      return unless value == '1' && shipped_at.nil?
      self.shipped_at = Time.now
    end

    def shipping_method
      shipping_rates.where(selected: true).first.try(:shipping_method) || shipping_rates.first.try(:shipping_method)
    end

    def add_shipping_method(shipping_method, selected=false)
      shipping_rates << Spree::ShippingRate.create(:shipping_method => shipping_method,
                                                                        :selected => selected)
    end

    def selected_shipping_rate
      shipping_rates.where(selected: true).first
    end

    def selected_shipping_rate_id
      selected_shipping_rate.try(:id)
    end

    def selected_shipping_rate_id=(id)
      shipping_rates.update_all(selected: false)
      shipping_rates.update(id, selected: true)
      self.save!
    end

    def ensure_selected_shipping_rate
      shipping_rates.exists?(selected: true) ||
        shipping_rates.limit(1).update_all(selected: true)
    end


    def currency
      order.nil? ? Spree::Config[:currency] : order.currency
    end

    # The adjustment amount associated with this shipment (if any.)  Returns only the first adjustment to match
    # the shipment but there should never really be more than one.
    def cost
      adjustment ? adjustment.amount : 0
    end

    alias_method :amount, :cost

    def display_cost
      Spree::Money.new(cost, { :currency => currency })
    end

    alias_method :display_amount, :display_cost

    # shipment state machine (see http://github.com/pluginaweek/state_machine/tree/master for details)
    state_machine :initial => 'pending', :use_transactions => false do
      event :ready do
        transition :from => 'pending', :to => 'ready', :if => lambda { |shipment|
          # Fix for #2040
          shipment.determine_state(shipment.order) == 'ready'
        }
      end

      event :pend do
        transition :from => 'ready', :to => 'pending'
      end

      event :ship do
        transition :from => 'ready', :to => 'shipped'
      end
      after_transition :to => 'shipped', :do => :after_ship

      event :cancel do
        transition :to => 'canceled', :from => ['pending', 'ready']
      end
      after_transition :to => 'canceled', :do => :after_cancel

      event :resume do
        transition :from => 'canceled', :to => 'ready', :if => lambda { |shipment|
          shipment.determine_state(shipment.order) == 'ready'
        }
        transition :from => 'canceled', :to => 'pending', :if => lambda { |shipment|
          shipment.determine_state(shipment.order) == 'ready'
        }
        transition :from => 'canceled', :to => 'pending'
      end
      after_transition :from => 'canceled', :to => ['pending', 'ready'], :do => :after_resume
    end

    def editable_by?(user)
      !shipped?
    end

    def manifest
      inventory_units.group_by(&:variant).map do |variant, units|
        states = {}
        units.group_by(&:state).each { |state, iu| states[state] = iu.count }
        OpenStruct.new(:variant => variant, :quantity => units.length, :states => states)
      end
    end

    def line_items
      if order.complete? and Spree::Config[:track_inventory_levels]
        order.line_items.select { |li| inventory_units.pluck(:variant_id).include?(li.variant_id) }
      else
        order.line_items
      end
    end

    def finalize!
      InventoryUnit.finalize_units!(inventory_units)
      manifest.each do |item|
        stock_location.unstock item.variant, item.quantity, self
      end
    end

    def after_cancel
      manifest.each do |item|
        stock_location.restock item.variant, item.quantity, self
      end
    end

    def after_resume
      manifest.each do |item|
        stock_location.unstock item.variant, item.quantity, self
      end
    end

    # Updates various aspects of the Shipment while bypassing any callbacks.  Note that this method takes an explicit reference to the
    # Order object.  This is necessary because the association actually has a stale (and unsaved) copy of the Order and so it will not
    # yield the correct results.
    def update!(order)
      old_state = state
      new_state = determine_state(order)
      update_column 'state', new_state
      after_ship if new_state == 'shipped' and old_state != 'shipped'
    end

    # Determines the appropriate +state+ according to the following logic:
    #
    # pending    unless order is complete and +order.payment_state+ is +paid+
    # shipped    if already shipped (ie. does not change the state)
    # ready      all other cases
    def determine_state(order)
      return 'canceled' if order.canceled?
      return 'pending' unless order.can_ship?
      return 'pending' if inventory_units.any? &:backordered?
      return 'shipped' if state == 'shipped'
      order.paid? ? 'ready' : 'pending'
    end

    def tracking_url
      @tracking_url ||= shipping_method.build_tracking_url(tracking)
    end

    def add(variant, quantity)
      #update line item
      order.add_variant(variant, quantity)

      #create inventory_units
      sold, back_order = stock_location.fill_status(variant, quantity)

      sold.times do
        inventory_units.create({:variant_id => variant.id,
                                          :state => 'sold'}, :without_protection => true)
      end

      back_order.times do
        inventory_units.create({:variant_id => variant.id,
                                         :state => 'backordered'}, :without_protection => true)
      end

      # adding to this shipment, and removing from stock_location
      stock_location.unstock variant, quantity, self
      update_order
    end


    def remove(variant, quantity)
      #destroy inventory_units
      variant_units = inventory_units.group_by(&:variant_id)
      if variant_units.include? variant.id

        variant_units = variant_units[variant.id].reject do |variant_unit|
          variant_unit.state == 'shipped'
        end.sort_by(&:state)

        if quantity > variant_units.size
          raise 'Shipment does not contain enough deletable inventory_units'
        end
        quantity.times do
          inventory_unit = variant_units.shift
          inventory_unit.destroy
        end
      else
        raise 'Variant does not belong to this shipment'
        #raise exception variant does not belong to shipment
      end

      #update line_item
      order.remove_variant(variant, quantity)

      reload

      destroy if inventory_units.size == 0

      # create stock_movement, we're removing from shipment,
      # and restocking it at location
      stock_location.restock variant.id, quantity, self
    end

    def to_package
      package = Stock::Package.new(stock_location, order)
      inventory_units.each do |inventory_unit|
        package.add inventory_unit.variant, 1, inventory_unit.state
      end
      package
    end

    private
      def generate_shipment_number
        return number unless number.blank?
        record = true
        while record
          random = "H#{Array.new(11) { rand(9) }.join}"
          record = self.class.where(:number => random).first
        end
        self.number = random
      end

      def description_for_shipping_charge
        "#{I18n.t(:shipping)} (#{shipping_method.name})"
      end

      def validate_shipping_method
        unless shipping_method.nil?
          errors.add :shipping_method, I18n.t(:is_not_available_to_shipment_address) unless shipping_method.include?(address)
        end
      end

      def after_ship
        inventory_units.each &:ship!
        adjustment.finalize!
        send_shipped_email
        touch :shipped_at
      end

      def send_shipped_email
        ShipmentMailer.shipped_email(self).deliver
      end

      def ensure_correct_adjustment
        if adjustment
          adjustment.originator = shipping_method
          adjustment.label = shipping_method.name
          if adjustment.open?
            adjustment.amount = selected_shipping_rate.cost
          end
          adjustment.save!
          adjustment.reload

        elsif shipping_method
          shipping_method.create_adjustment(shipping_method.adjustment_label, order, self, true)
          reload #ensure adjustment is present on later saves
        end
      end

      def update_order
        order.update!
      end
  end
end
