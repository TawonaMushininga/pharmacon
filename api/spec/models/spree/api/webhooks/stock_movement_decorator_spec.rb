require 'spec_helper'

describe Spree::Api::Webhooks::StockMovementDecorator do
  let(:stock_item) { create(:stock_item) }
  let(:stock_location) { variant.stock_locations.first }
  let(:body) { variant.tap(&:reload).send(:webhooks_body_for, event: params) }

  describe 'emitting product.back_in_stock' do
    let!(:store) { create(:store) }
    let!(:product) { create(:product, stores: [store]) }
    let!(:variant) { create(:variant, product: product) }
    let!(:variant2) { create(:variant, product: product) }
    let(:body) { product.send(:webhooks_body_for, event: params) }
    let(:params) { 'product.back_in_stock' }

    before { Spree::StockItem.update_all(backorderable: false) }

    context 'when all product variants are out of stock' do
      context 'when one of the variants is back in stock' do
        subject do
          stock_location.stock_movements.new.tap do |stock_movement|
            stock_movement.quantity = 1
            stock_movement.stock_item = stock_location.set_up_stock_item(variant)
            stock_movement.save
          end
          product.reload
        end

        it { expect { subject }.to emit_webhook_event(params) }
      end

      context 'when none of the variants is back in stock' do
        subject do
          stock_location.stock_movements.new.tap do |stock_movement|
            stock_movement.quantity = 0
            stock_movement.stock_item = stock_location.set_up_stock_item(variant)
            stock_movement.save
          end
          product.reload
        end

        it { expect { subject }.not_to emit_webhook_event(params) }
      end
    end

    context 'when other variant is already in stock' do
      subject do
        stock_location.stock_movements.new.tap do |stock_movement|
          stock_movement.quantity = 100
          stock_movement.stock_item = stock_location.set_up_stock_item(variant)
          stock_movement.save
        end
      end

      before do
        stock_location.stock_movements.new.tap do |stock_movement|
          stock_movement.quantity = 1
          stock_movement.stock_item = stock_location.set_up_stock_item(variant2)
          stock_movement.save
        end
      end

      it { expect { subject }.not_to emit_webhook_event(params) }
    end
  end

  describe 'emitting variant.back_in_stock' do
    let(:variant) { create(:variant, track_inventory: true) }
    let(:params) { 'variant.back_in_stock' }

    context 'when stock item was out of stock' do
      context 'when stock item changes to be in stock' do
        it do
          expect do
            variant.stock_items.update_all(backorderable: false)
            stock_location.stock_movements.new.tap do |stock_movement|
              stock_movement.quantity = 1 # does make it to be in stock
              stock_movement.stock_item = stock_location.set_up_stock_item(variant)
              stock_movement.save
            end
          end.to emit_webhook_event(params)
        end
      end

      context 'when stock item does not change to be in stock' do
        it do
          expect do
            variant.stock_items.update_all(backorderable: false)
            stock_location.stock_movements.new.tap do |stock_movement|
              stock_movement.quantity = 0 # does not make it to be in stock
              stock_movement.stock_item = stock_location.set_up_stock_item(variant)
              stock_movement.save
            end
          end.not_to emit_webhook_event(params)
        end
      end
    end

    context 'when stock item was in stock' do
      it do
        expect do
          # make in_stock? return false based on track_inventory, the easiest case
          variant.update(track_inventory: false)
          stock_location.stock_movements.new.tap do |stock_movement|
            stock_movement.quantity = 2
            stock_movement.stock_item = stock_location.set_up_stock_item(variant)
            stock_movement.save
          end
        end.not_to emit_webhook_event(params)
      end
    end
  end

  describe 'emitting variant.out_of_stock' do
    subject { stock_movement }

    let(:stock_movement) { create(:stock_movement, stock_item: stock_item, quantity: movement_quantity) }
    let(:params) { 'variant.out_of_stock' }
    let!(:variant) { stock_item.variant }

    before { Spree::StockItem.update_all(backorderable: false) }

    describe 'when the variant goes out of stock' do
      let(:movement_quantity) { -stock_item.count_on_hand }

      it 'emits the variant.out_of_stock event' do
        expect { subject }.to emit_webhook_event(params)
      end
    end

    describe 'when the variant does not go out of stock' do
      let(:movement_quantity) { -stock_item.count_on_hand + 1 }

      it 'does not emit the variant.out_of_stock event' do
        expect { subject }.not_to emit_webhook_event(params)
      end
    end

    describe 'when the variant was out of stock before the update and after the update' do
      before { stock_item.set_count_on_hand(0) }

      let(:movement_quantity) { 0 }

      it 'does not emit the variant.out_of_stock event' do
        expect { subject }.not_to emit_webhook_event(params)
      end
    end
  end
end
