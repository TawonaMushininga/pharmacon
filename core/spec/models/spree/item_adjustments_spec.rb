require 'spec_helper'

module Spree
  describe ItemAdjustments, :type => :model do
    let(:order) { create :order_with_line_items, line_items_count: 1 }
    let(:line_item) { order.line_items.first }

    let(:subject) { ItemAdjustments.new(line_item) }
    let(:order_subject) { ItemAdjustments.new(order) }

    context '#update' do
      it "updates a linked adjustment" do
        tax_rate = create(:tax_rate, :amount => 0.05)
        adjustment = create(:adjustment, order: order, source: tax_rate, adjustable: line_item)
        line_item.price = 10
        line_item.tax_category = tax_rate.tax_category

        subject.update
        expect(line_item.adjustment_total).to eq(0.5)
        expect(line_item.additional_tax_total).to eq(0.5)
      end
    end

    context "taxes and promotions" do
      let!(:tax_rate) do
        create(:tax_rate, :amount => 0.05)
      end

      let!(:promotion) do
        Spree::Promotion.create(:name => "$10 off")
      end

      let!(:promotion_action) do
        calculator = Calculator::FlatRate.new(:preferred_amount => 10)
        Promotion::Actions::CreateItemAdjustments.create calculator: calculator, promotion: promotion
      end

      before do
        line_item.price = 20
        line_item.tax_category = tax_rate.tax_category
        line_item.save
        create(:adjustment, order: order, source: promotion_action, adjustable: line_item)
      end

      context "tax included in price" do
        before do
          create(:adjustment,
            :source => tax_rate,
            :adjustable => line_item,
            :order => order,
            :included => true
          )
        end

        it "tax has no bearing on final price" do
          subject.update_adjustments
          line_item.reload
          expect(line_item.included_tax_total).to eq(0.5)
          expect(line_item.additional_tax_total).to eq(0)
          expect(line_item.promo_total).to eq(-10)
          expect(line_item.adjustment_total).to eq(-10)
        end

        it "tax linked to order" do
          order_subject.update_adjustments
          order.reload
          expect(order.included_tax_total).to eq(0.5)
          expect(order.additional_tax_total).to eq(00)
        end
      end

      context "tax excluded from price" do
        before do
          create(:adjustment,
            :source => tax_rate,
            :adjustable => line_item,
            :order => order,
            :included => false
          )
        end

        it "tax applies to line item" do
          subject.update_adjustments
          line_item.reload
          # Taxable amount is: $20 (base) - $10 (promotion) = $10
          # Tax rate is 5% (of $10).
          expect(line_item.included_tax_total).to eq(0)
          expect(line_item.additional_tax_total).to eq(0.5)
          expect(line_item.promo_total).to eq(-10)
          expect(line_item.adjustment_total).to eq(-9.5)
        end

        it "tax linked to order" do
          order_subject.update_adjustments
          order.reload
          expect(order.included_tax_total).to eq(0)
          expect(order.additional_tax_total).to eq(0.5)
        end
      end
    end

    context "best promotion is always applied" do
      let(:action1) { create(:promotion, :with_order_adjustment).actions.first }
      let(:action2) { create(:promotion, :with_order_adjustment).actions.first }
      let(:action3) { create(:promotion, :with_order_adjustment).actions.first }

      def create_adjustment(adjustable, amount, source)
        adjustable.adjustments.create({
          order: order, 
          amount: amount, 
          label: amount.to_s, 
          source: source, 
          state: 'closed'
        })
      end

      context 'with adjustments from multiple promotions' do 
        before do
          create_adjustment(order, -100, action1)
          create_adjustment(order, -200, action2)
          create_adjustment(order, -300, action3)
          create_adjustment(order, -500, nil)
        end

        it 'should make all but the most valuable promotion adjustment ineligible, leaving non promotion adjustments alone' do
          order.reload
          expect(order.adjustments.count).to eq(4)
          expect(order.adjustments.promotion.count).to eq(3)
          expect(order.adjustments.promotion.eligible.count).to eq(1)
          expect(order.promo_total).to eq(-300)
        end
      end

      context "when previously ineligible promotions become available" do
        let(:order_promo1) { create(:promotion, :with_order_adjustment, :with_item_total_rule, weighted_order_adjustment_amount: 5, item_total_threshold_amount: 10) }
        let(:order_promo2) { create(:promotion, :with_order_adjustment, :with_item_total_rule, weighted_order_adjustment_amount: 10, item_total_threshold_amount: 20) }
        let(:order_promos) { [ order_promo1, order_promo2 ] }
        let(:line_item_promo1) { create(:promotion, :with_line_item_adjustment, :with_item_total_rule, adjustment_rate: 2.5, item_total_threshold_amount: 10) }
        let(:line_item_promo2) { create(:promotion, :with_line_item_adjustment, :with_item_total_rule, adjustment_rate: 5, item_total_threshold_amount: 20) }
        let(:line_item_promos) { [ line_item_promo1, line_item_promo2 ] }
        let(:order) { create(:order_with_line_items, line_items_count: 1) }

        # Apply promotions in different sequences. Results should be the same.
        promo_sequences = [
          [ 0, 1 ],
          [ 1, 0 ]
        ]

        promo_sequences.each do |promo_sequence|
          it "should pick the best order-level promo according to current eligibility" do
            # apply both promos to the order, even though only promo1 is eligible
            order_promos[promo_sequence[0]].activate order: order
            order_promos[promo_sequence[1]].activate order: order

            order.reload
            expect(order.all_adjustments.count).to eq(2), "Expected two adjustments (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.count).to eq(1), "Expected one elegible adjustment (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.first.source.promotion).to eq(order_promo1), "Expected promo1 to be used (using sequence #{promo_sequence})"

            order.contents.add create(:variant, price: 10), 1
            order.save

            order.reload
            expect(order.all_adjustments.count).to eq(2), "Expected two adjustments (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.count).to eq(1), "Expected one elegible adjustment (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.first.source.promotion).to eq(order_promo2), "Expected promo2 to be used (using sequence #{promo_sequence})"
          end
        end

        promo_sequences.each do |promo_sequence|
          it "should pick the best line-item-level promo according to current eligibility" do
            # apply both promos to the order, even though only promo1 is eligible
            line_item_promos[promo_sequence[0]].activate order: order
            line_item_promos[promo_sequence[1]].activate order: order

            order.reload
            expect(order.all_adjustments.count).to eq(1), "Expected one adjustment (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.count).to eq(1), "Expected one elegible adjustment (using sequence #{promo_sequence})"
            # line_item_promo1 is the only one that has thus far met the order total threshold, it is the only promo which should be applied.
            expect(order.all_adjustments.first.source.promotion).to eq(line_item_promo1), "Expected line_item_promo1 to be used (using sequence #{promo_sequence})"

            order.contents.add create(:variant, price: 10), 1
            order.save

            order.reload
            expect(order.all_adjustments.count).to eq(4), "Expected four adjustments (using sequence #{promo_sequence})"
            expect(order.all_adjustments.eligible.count).to eq(2), "Expected two elegible adjustments (using sequence #{promo_sequence})"
            order.all_adjustments.eligible.each do |adjustment|
              expect(adjustment.source.promotion).to eq(line_item_promo2), "Expected line_item_promo2 to be used (using sequence #{promo_sequence})"
            end
          end
        end
      end
      
      context "multiple adjustments and the best one is not eligible" do
        let!(:promo_a) { create_adjustment(order, -100, action1) }
        let!(:promo_c) { create_adjustment(order, -300, action3) }

        before do
          promo_a.update_column(:eligible, true)
          promo_c.update_column(:eligible, false)
        end

        # regression for #3274
        it "still makes the previous best eligible adjustment valid" do
          expect(order.adjustments.promotion.eligible.first).to eq(promo_a)
        end
      end

      it "should only leave one adjustment even if 2 have the same amount" do
        create_adjustment(order, -100, action1)
        create_adjustment(order, -200, action2)
        create_adjustment(order, -200, action3)

        expect(order.adjustments.promotion.eligible.count).to eq(1)
        expect(order.adjustments.promotion.eligible.first.amount.to_i).to eq(-200)
      end
    end

    # For #4483
    context "callbacks" do
      class SuperItemAdjustments < Spree::ItemAdjustments
        attr_accessor :before_promo_adjustments_called,
                      :after_promo_adjustments_called,
                      :before_tax_adjustments_called,
                      :after_tax_adjustments_called

        set_callback :promo_adjustments, :before do |object|
          @before_promo_adjustments_called = true
        end

        set_callback :promo_adjustments, :after do |object|
          @after_promo_adjustments_called = true
        end

        set_callback :tax_adjustments, :before do |object|
          @before_tax_adjustments_called = true
        end

        set_callback :tax_adjustments, :after do |object|
          @after_tax_adjustments_called = true
        end
      end
      let(:subject) { SuperItemAdjustments.new(line_item) }

      it "calls all the callbacks" do
        subject.update_adjustments
        expect(subject.before_promo_adjustments_called).to be true
        expect(subject.after_promo_adjustments_called).to be true
        expect(subject.before_tax_adjustments_called).to be true
        expect(subject.after_tax_adjustments_called).to be true
      end
    end

    context 'with multiple adjustments from same promotion whose combined discount is larger than item + ship total' do 
      let(:order) { create(:order_with_line_items, line_items_price: 25) }
      let(:promotion) { create(:promotion) }
      let(:source1) { create_source }
      let(:source2) { create_source(percent_calculator) }
      let(:source3) { Spree::Promotion::Actions::FreeShipping.new }
      let(:source4) { create_source }
      let(:percent_calculator) { Spree::Calculator::FlatPercentItemTotal.new(preferred_flat_percent: 50) }

      def create_source(calculator=nil)
        Spree::Promotion::Actions::CreateAdjustment.new(calculator: calculator || create(:calculator))
      end

      before do 
        promotion.promotion_actions = [source1, source2, source3, source4]
        promotion.actions.each do |s| 
          s.perform(order: order)
        end       
      end

      it 'calculates the second discount as a percentage of the item total after the first discount is applied' do 
        expect(order.adjustments[1].amount).to eq(-7.5)
      end

      it "calculates discounts that together equal the item + ship total" do
        expect(order.all_adjustments.map(&:amount).reduce(&:+)).to eq(-1 * (order.item_total + order.ship_total))
      end

    end
  end
end