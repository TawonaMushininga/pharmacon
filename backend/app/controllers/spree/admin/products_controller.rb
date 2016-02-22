module Spree
  module Admin
    class ProductsController < ResourceController
      helper 'spree/products'

      before_action :load_data, except: :index
      create.before :create_before
      helper_method :clone_object_url

      def show
        session[:return_to] ||= request.referer
        redirect_to action: :edit
      end

      def index
        session[:return_to] = request.url
        respond_with(@collection)
      end

      def update
        if params[:product][:taxon_ids].present?
          params[:product][:taxon_ids] = params[:product][:taxon_ids].split(',')
        end
        if params[:product][:option_type_ids].present?
          params[:product][:option_type_ids] = params[:product][:option_type_ids].split(',')
        end
        invoke_callbacks(:update, :before)
        if @object.update_attributes(permitted_resource_params)
          invoke_callbacks(:update, :after)
          flash[:success] = flash_message_for(@object, :successfully_updated)
          respond_with(@object) do |format|
            format.html { redirect_to location_after_save }
            format.js   { render layout: false }
          end
        else
          # Stops people submitting blank slugs, causing errors when they try to
          # update the product again
          @product.slug = @product.slug_was if @product.slug.blank?
          invoke_callbacks(:update, :fails)
          respond_with(@object)
        end
      end

      def destroy
        @product = Product.friendly.find(params[:id])
        @product.destroy

        flash[:success] = Spree.t('notice_messages.product_deleted')

        respond_with(@product) do |format|
          format.html { redirect_to collection_url }
          format.js  { render_js_for_destroy }
        end
      end

      def clone
        @new = @product.duplicate

        if @new.save
          flash[:success] = Spree.t('notice_messages.product_cloned')
        else
          flash[:error] = Spree.t('notice_messages.product_not_cloned')
        end

        redirect_to edit_admin_product_url(@new)
      end

      def stock
        @variants = @product.variants.includes(*variant_stock_includes)
        @variants = [@product.master] if @variants.empty?
        @stock_locations = StockLocation.accessible_by(current_ability, :read)
        if @stock_locations.empty?
          flash[:error] = Spree.t(:stock_management_requires_a_stock_location)
          redirect_to admin_stock_locations_path
        end
      end

      def taxons_tree
        @taxonomies = Spree::Taxonomy.all
        @taxonomy = Spree::Taxonomy.find_by(id: params[:taxonomy_id]) || Spree::Taxonomy.first
      end

      protected

      def location_after_save
        :back
      end

      def load_data
        @taxons = Taxon.order(:name)
        @option_types = OptionType.order(:name)
        @tax_category = TaxCategory.find_by(id: @product.tax_category_id)
        @shipping_category = ShippingCategory.find_by(id: @product.shipping_category_id)
      end

      def collection
        return @collection if @collection.present?
        params[:q] ||= {}
        params[:q][:deleted_at_null] ||= "1"

        params[:q][:s] ||= "id desc"
        @collection = super
        if params[:q].delete(:deleted_at_null) == '0'
          @collection = @collection.with_deleted
        end
        # @search needs to be defined as this is passed to search_form_for
        @search = search_results(params[:q]).ransack

        @collection = @search.result.
              distinct_by_product_ids(params[:q][:s]).
              includes(product_includes).
              page(params[:page]).
              per(params[:per_page] || Spree::Config[:admin_products_per_page])
        @collection
      end

      def search_results(params)
        if params[:id_eq].present?
          @collection.where(id: params[:id_eq])
        elsif params[:name_cont].present?
          @collection.with_translations(:en)
            .where("spree_product_translations.name LIKE ?", "%#{params[:name_cont]}%")
        elsif params[:legacy_supplier_sku_cont].present?
          @collection
            .where("legacy_supplier_sku like ?", "%#{params[:legacy_supplier_sku_cont]}%")
        elsif params[:variants_including_master_sku_cont].present?
          @collection.joins(:variants_including_master)
            .where("sku like ?", "%#{params[:variants_including_master_sku_cont]}%")
        else
          @collection
        end
      end

      def create_before
        return if params[:product][:prototype_id].blank?
        @prototype = Spree::Prototype.find(params[:product][:prototype_id])
      end

      def product_includes
        [{ variants: [:images], master: [:images, :default_price] }]
      end

      def clone_object_url(resource)
        clone_admin_product_url resource
      end

      private

      def variant_stock_includes
        [:images, stock_items: :stock_location, option_values: :option_type]
      end
    end
  end
end
