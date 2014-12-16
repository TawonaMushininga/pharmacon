module Spree
  module AdjustmentSource
    extend ActiveSupport::Concern

    included do
      has_many :adjustments, as: :source
      before_destroy :deals_with_adjustments_for_deleted_source
    end

    protected

    def create_adjustment(order_id, adjustable, included = nil)
      amount = compute_amount(adjustable)
      return if amount == 0
      adjustments.new(order_id: order_id,
                      adjustable: adjustable,
                      label: label(amount),
                      amount: amount,
                      included: included).save
    end

    def create_unique_adjustment(order_id, adjustable)
      return if already_adjusted?(adjustable)
      create_adjustment(order_id, adjustable)
    end

    def create_unique_adjustments(order_id, adjustables)
      adjustables.where.not(id: already_adjusted(order_id)).map do |adjustable|
        create_adjustment(order_id, adjustable) if !block_given? || yield(adjustable)
      end.any?
    end

    private

    def already_adjusted(order_id)
      adjustments.where(order_id: order_id).pluck(:adjustable_id)
    end

    def already_adjusted?(adjustable)
      adjustments.where(adjustable: adjustable).exists?
    end

    def deals_with_adjustments_for_deleted_source
      adjustment_scope = adjustments.includes(:order).references(:spree_orders)

      # For incomplete orders, remove the adjustment completely.
      adjustment_scope.where("spree_orders.completed_at IS NULL").destroy_all

      # For complete orders, the source will be invalid.
      # Therefore we nullify the source_id, leaving the adjustment in place.
      # This would mean that the order's total is not altered at all.
      adjustment_scope.where("spree_orders.completed_at IS NOT NULL").each do |adjustment|
        adjustment.update_columns(
          source_id: nil,
          updated_at: Time.now,
        )
      end
    end
  end
end
