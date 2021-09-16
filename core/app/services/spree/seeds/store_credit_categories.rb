module Spree
  module Seeds
    class StoreCreditCategories
      prepend Spree::ServiceModule::Base

      def call
        # FIXME: we should use translations here
        Spree::StoreCreditCategory.find_or_create_by!(name: 'Default')
      end
    end
  end
end
