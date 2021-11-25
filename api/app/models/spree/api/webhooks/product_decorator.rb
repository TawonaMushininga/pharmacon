module Spree
  module Api
    module Webhooks
      module ProductDecorator
        def self.prepended(base)
          def base.custom_webhook_events
            %w[product.back_in_stock product.backorderable product.discontinued product.out_of_stock]
          end
        end

        def discontinue!
          super
          queue_webhooks_requests!('product.discontinued')
        end
      end
    end
  end
end

Spree::Product.prepend(Spree::Api::Webhooks::ProductDecorator)

