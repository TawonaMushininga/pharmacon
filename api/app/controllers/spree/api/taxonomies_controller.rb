module Spree
  module Api
    class TaxonomiesController < Spree::Api::BaseController

      def index
        @taxonomies = Taxonomy.accessible_by(current_ability, :read).order('name').includes(:root => :children).
                      ransack(params[:q]).result.
                      page(params[:page]).per(params[:per_page])
        render json: @taxonomies, meta: pagination(@taxonomies)
      end

      def show
        @taxonomy = Taxonomy.accessible_by(current_ability, :read).find(params[:id])
        if params[:set]
          render json: @taxonomy, 
                 serializer: Spree::NestedTaxonomySerializer,
                 root: :taxonomy
        else
          render json: @taxonomy
        end
      end

      # Because JSTree wants parameters in a *slightly* different format
      def jstree
        @taxonomy = Taxonomy.accessible_by(current_ability, :read).find(params[:id])
        render json: {
          data: @taxonomy.root.name,
          attr: { 
            id: @taxonomy.root.id,
            name: @taxonomy.root.name
          },
          state: "closed"
        }
      end

      def create
        authorize! :create, Taxonomy
        @taxonomy = Taxonomy.new(taxonomy_params)
        if @taxonomy.save
          render json: @taxonomy, status: 201
        else
          invalid_resource!(@taxonomy)
        end
      end

      def update
        authorize! :update, taxonomy
        if taxonomy.update_attributes(taxonomy_params)
          render json: taxonomy, status: 200
        else
          invalid_resource!(taxonomy)
        end
      end

      def destroy
        authorize! :destroy, taxonomy
        taxonomy.destroy
        render nothing: true, status: 204
      end

      private

      def taxonomy
        @taxonomy ||= Taxonomy.accessible_by(current_ability, :read).find(params[:id])
      end

      def taxonomy_params
        if params[:taxonomy] && !params[:taxonomy].empty?
          params.require(:taxonomy).permit(permitted_taxonomy_attributes)
        else
          {}
        end
      end
    end
  end
end
