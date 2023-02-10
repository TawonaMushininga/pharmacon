module Spree
  module TranslatableResourceScopes
    extend ActiveSupport::Concern

    class_methods do
      # To be used when joining on the resource itself does not automatically join on its translations table
      # This method is to be used when you've already joined on the translatable table itself
      def join_translation_table(translatable_class)
        translatable_class_foreign_key = "#{translatable_class.table_name.singularize}_id"
        joins("LEFT OUTER JOIN #{translatable_class::Translation.table_name} #{translatable_class.translation_table_alias}
             ON #{translatable_class.translation_table_alias}.#{translatable_class_foreign_key} = #{translatable_class.table_name}.id
             AND #{translatable_class.translation_table_alias}.locale = '#{Mobility.locale}'")
      end
    end
  end
end
