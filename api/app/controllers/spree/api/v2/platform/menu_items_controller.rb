module Spree
  module Api
    module V2
      module Platform
        class MenuItemsController < ResourceController
          def reposition
            spree_authorize! :update, @moved_item if spree_current_user.present?

            @moved_item = scope.find(params[:id])
            @new_parent = scope.find(params[:new_parent_id])
            new_index = params[:new_position_idx].to_i

            if @moved_item && @new_parent && new_index
              @moved_item.move_to_child_with_index(@new_parent, new_index)
            else
              head :bad_request
            end

            if @moved_item.save
              render_serialized_payload { serialize_resource(resource) }
            end
          end

          private

          def model_class
            Spree::MenuItem
          end
        end
      end
    end
  end
end
