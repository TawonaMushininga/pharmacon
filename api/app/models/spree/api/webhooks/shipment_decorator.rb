module Spree
  module Api
    module Webhooks
      module ShipmentDecorator
        def after_ship
          super
          queue_webhooks_requests!('shipment.ship')
        end
      end
    end
  end
end

Spree::Shipment.prepend(Spree::Api::Webhooks::ShipmentDecorator)
