require 'swagger_helper'

describe 'CMS Section API', swagger: true do
  include_context 'Platform API v2'

  resource_name = 'CMS Section'
  options = {
    include_example: 'product',
    filter_examples: [{ name: 'filter[name_eq]', example: 'Hero' }]
  }

  let!(:store) { Spree::Store.default }
  let!(:product) { create(:product) }
  let!(:cms_page) { create(:cms_feature_page, store: store) }
  let!(:cms_hero_section) { create(:cms_hero_image_section, cms_page: cms_page) }
  let!(:cms_image_gallery_section) { create(:cms_image_gallery_section, cms_page: cms_page) }
  let!(:cms_featured_article_section) { create(:cms_featured_article_section, cms_page: cms_page) }

  let(:id) { create(:cms_hero_image_section, cms_page: cms_page, linked_resource: product).id }
  let(:records_list) { create_list(:cms_hero_image_section, 2, cms_page: cms_page, linked_resource: product) }

  let(:valid_create_param_value) { build(:cms_hero_image_section, cms_page: cms_page, linked_resource: product).attributes }
  let(:valid_update_param_value) do
    {
      name: 'Super Hero'
    }
  end

  let(:invalid_param_value) do
    {
      name: ''
    }
  end

  let(:valid_update_position_param_value) do
    {
      new_position_idx: 2
    }
  end

  path "/api/v2/platform/#{resource_name.downcase.parameterize(separator: '_').pluralize}/{id}/reposition" do
    patch "Reposition a #{resource_name}" do
      tags resource_name.pluralize
      security [ bearer_auth: [] ]
      operationId "reposition-#{resource_name.downcase.parameterize}"
      description "Reposition a #{resource_name}"
      consumes 'application/json'
      parameter name: :id, in: :path, type: :string
      parameter name: resource_name.downcase.parameterize(separator: '_').to_sym, in: :body, schema: { '$ref' => '#/components/schemas/reposition_params' }

      let(resource_name.downcase.parameterize(separator: '_').to_sym) { valid_update_position_param_value }

      it_behaves_like 'record updated'
      it_behaves_like 'record not found', resource_name.downcase.parameterize(separator: '_').to_sym
      it_behaves_like 'authentication failed'
    end
  end

  include_examples 'CRUD examples', resource_name, options
end
