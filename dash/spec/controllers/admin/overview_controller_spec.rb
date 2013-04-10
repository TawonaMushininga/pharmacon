require 'spec_helper'

describe Spree::Admin::OverviewController do

  it "sets the locale preference" do
    @user = create(:admin_user)
    controller.stub :spree_current_user => @user
    Spree::Dash::Config.should_receive(:configured?).at_least(1).times.and_return(true)
    session[:last_jirafe_sync] = DateTime.now

    Spree::Dash::Config.locale = 'en_EN'
    spree_get :index, :locale => 'fr_FR'
    Spree::Dash::Config.locale.should eq 'fr_FR'
  end

  # Regression test for https://github.com/spree/spree/pull/2859
  it 'should respond to model_class as Spree::Dash' do
    controller.send(:model_class).should eql(Spree::Dash)
  end

end
