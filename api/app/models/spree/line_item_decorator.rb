Spree::LineItem.class_eval do
  attr_accessible :quantity, :variant_id, :price, :sku, :as => :api
end
