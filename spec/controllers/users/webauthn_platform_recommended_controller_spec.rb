require 'rails_helper'

RSpec.describe Users::WebauthnPlatformRecommendedController do
  let(:user) { create(:user) }
  let(:current_sp) { create(:service_provider) }

  before do
    controller.session[:sp] = {
      issuer: current_sp.issuer,
      acr_values: Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
      request_url: 'http://example.com',
    }
    stub_sign_in(user) if user
  end

  it 'includes appropriate before_actions' do
    expect(controller).to have_actions(
      :before,
      :confirm_two_factor_authenticated,
      :apply_secure_headers_override,
    )
  end

  describe '#new' do
    subject(:response) { get :new }

    it 'assigns sign_in_flow instance variable from session' do
      controller.session[:sign_in_flow] = :example

      response

      expect(assigns(:sign_in_flow)).to eq(:example)
    end

    it 'logs analytics event' do
      stub_analytics

      response

      expect(@analytics).to have_logged_event(:webauthn_platform_recommended_visited)
    end
  end

  describe '#create' do
    let(:params) { {} }
    subject(:response) { post :create, params: params }

    it 'logs analytics event' do
      stub_analytics

      response

      expect(@analytics).to have_logged_event(
        :webauthn_platform_recommended_submitted,
        opted_to_add: false,
      )
    end

    it 'updates user record to mark as having dismissed recommendation' do
      freeze_time do
        expect { response }.to change { user.webauthn_platform_recommended_dismissed_at }
          .from(nil)
          .to(Time.zone.now)
      end
    end

    it 'does not assign recommended session value' do
      expect { response }.not_to change { controller.user_session[:webauthn_platform_recommended] }
        .from(nil)
    end

    context 'user is creating account' do
      before do
        allow(controller).to receive(:in_account_creation_flow?).and_return(true)
        controller.user_session[:mfa_selections] = []
      end

      it 'redirects user to consent screen' do
        expect(response).to redirect_to(sign_up_completed_path)
      end

      context 'mfa selections already completed' do
        # Regression: If duplicate submission occurs (e.g. pressing back button), selections is
        # already cleared from session, but the user is still in the account creation flow.

        before do
          controller.user_session[:mfa_selections] = nil
        end

        it 'redirects user to consent screen' do
          expect(response).to redirect_to(sign_up_completed_path)
        end
      end
    end

    context 'user opted to add' do
      let(:params) { { add_method: 'true' } }

      it 'logs analytics event' do
        stub_analytics

        response

        expect(@analytics).to have_logged_event(
          :webauthn_platform_recommended_submitted,
          opted_to_add: true,
        )
      end

      it 'redirects user to set up platform authenticator' do
        expect(response).to redirect_to(webauthn_setup_path(platform: true))
      end

      context 'user is creating account' do
        before do
          allow(controller).to receive(:in_account_creation_flow?).and_return(true)
        end

        it 'adds recommended session value during recommendation flow' do
          expect { response }.to change { controller.user_session[:webauthn_platform_recommended] }
            .from(nil).to(true)
        end
      end
    end
  end
end
