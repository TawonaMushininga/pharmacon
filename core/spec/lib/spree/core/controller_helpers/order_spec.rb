require 'spec_helper'

class FakesController < ApplicationController
  include Spree::Core::ControllerHelpers::Order
end

describe Spree::Core::ControllerHelpers::Order, type: :controller do
  controller(FakesController) {}

  let(:user)                { create(:user)              }
  let(:order)               { create(:order, user: user) }
  let(:request_guest_token) { nil                        }

  before do
    allow(controller).to receive_messages(
      try_spree_current_user: user,
      cookies: double(signed: { guest_token: request_guest_token })
    )
  end

  describe '#simple_current_order' do
    let(:request_guest_token) { order.guest_token }

    it 'returns an empty order' do
      expect(controller.simple_current_order.item_count).to eql(0)
    end

    it 'returns Spree::Order instance' do
      expect(controller.simple_current_order).to eql(order)
    end
  end

  describe '#current_order' do
    context 'create_order_if_necessary option is false' do
      let!(:order) { create :order, user: user }

      it 'returns current order' do
        expect(controller.current_order).to eql(order)
      end
    end

    context 'create_order_if_necessary option is true' do
      it 'creates new order' do
        expect do
          controller.current_order(create_order_if_necessary: true)
        end.to change(Spree::Order, :count).to(1)
      end
    end
  end

  describe '#associate_user' do
    before do
      allow(controller).to receive_messages(current_order: order)
    end

    context 'users email is blank' do
      let(:user) { create(:user, email: '') }

      it 'calls Spree::Order#associate_user! method' do
        expect_any_instance_of(Spree::Order).to receive(:associate_user!)
        controller.associate_user
      end
    end

    context 'user is not blank' do
      it 'does not calls Spree::Order#associate_user! method' do
        expect_any_instance_of(Spree::Order).not_to receive(:associate_user!)
        controller.associate_user
      end
    end
  end

  describe '#set_current_order' do
    let(:incomplete_order) { create(:order, user: user) }

    context 'when current order not equal to users incomplete orders' do
      before do
        allow(controller).to receive_messages(current_order: order)
      end

      it 'calls Spree::Order#merge! method' do
        expect(order).to receive(:merge!).with(incomplete_order, user)
        controller.set_current_order
      end
    end
  end

  describe '#current_currency' do
    it 'returns current currency' do
      Spree::Config[:currency] = 'USD'
      expect(controller.current_currency).to eql('USD')
    end
  end

  describe '#ip_address' do
    it 'returns remote ip' do
      expect(controller.ip_address).to eql(request.remote_ip)
    end
  end
end
