require 'rails_helper'

RSpec.describe SignUp::RegistrationsController, devise: true do
  describe '#new' do
    it 'allows user to visit the sign up page' do
      get :new

      expect(response.status).to eq(200)
      expect(response).to render_template(:new)
    end

    it 'cannot be viewed by signed in users' do
      stub_sign_in

      subject.session[:sp] = { request_url: 'http://test.com' }

      get :new

      expect(response).to redirect_to account_path
    end

    it 'gracefully handles invalid formats' do
      @request.env['HTTP_ACCEPT'] = "nessus=bad_bad_value'"

      expect { get :new }
        .to raise_error(Mime::Type::InvalidMimeType)
    end

    it 'tracks visit event' do
      stub_analytics

      get :new

      expect(@analytics).to have_logged_event('User Registration: enter email visited')
    end

    context 'with source parameter' do
      it 'tracks visit event' do
        stub_analytics

        get :new

        expect(@analytics).to have_logged_event('User Registration: enter email visited')
      end
    end

    context 'IdV unavailable' do
      before do
        allow(IdentityConfig.store).to receive(:idv_available).and_return(false)
      end
      it 'redirects to idv vendor outage page when ial2 requested' do
        allow(controller).to receive(:ial2_requested?).and_return(true)
        get :new
        expect(response).to redirect_to(
          idv_unavailable_path(from: SignUp::RegistrationsController::CREATE_ACCOUNT),
        )
      end
    end
  end

  describe '#create' do
    let(:email) { 'new@example.com' }
    let(:email_language) { 'es' }
    let(:params) { { user: { email:, terms_accepted: '1', email_language: } } }

    before do
      stub_analytics
      stub_attempts_tracker
    end

    context 'when registering with a new email' do
      it 'tracks successful user registration' do
        allow(subject).to receive(:create_user_event)
        expect(@attempts_api_tracker).to receive(:user_registration_email_submitted).with(
          email:,
          success: true,
          failure_reason: nil,
        )

        post :create, params: params

        user = User.find_with_email('new@example.com')

        expect(@analytics).to have_logged_event(
          'User Registration: Email Submitted',
          success: true,
          rate_limited: false,
          email_already_exists: false,
          user_id: user.uuid,
          domain_name: 'example.com',
          email_language:,
        )

        expect(subject).to have_received(:create_user_event).with(:account_created, user)
      end

      it 'sets the users preferred email locale and sends an email in that locale' do
        post :create, params: params

        expect(User.find_with_email(email).email_language).to eq(email_language)

        mail = ActionMailer::Base.deliveries.last
        expect(mail.subject).to eq(
          I18n.t('user_mailer.email_confirmation_instructions.subject', locale: email_language),
        )
      end

      it 'sets the email in the session and redirects to sign_up_verify_email_path' do
        post :create, params: params

        expect(session[:email]).to eq(email)
        expect(response).to redirect_to(sign_up_verify_email_path)
      end

      it 'cannot be accessed by signed in users' do
        user = create(:user)
        stub_sign_in(user)

        post :create, params: params

        expect(response).to redirect_to account_path
      end
    end

    context 'with existing email' do
      let(:existing_user) { create(:user, email: 'test@example.com') }
      let(:email) { existing_user.email }

      it 'tracks successful user registration with existing email' do
        expect(subject).to_not receive(:create_user_event)
        expect(@attempts_api_tracker).to receive(:user_registration_email_submitted).with(
          email:,
          success: true,
          failure_reason: nil,
        )

        post :create, params: params

        expect(subject.session[:sign_in_flow]).to eq(:create_account)
        expect(@analytics).to have_logged_event(
          'User Registration: Email Submitted',
          success: true,
          rate_limited: false,
          email_already_exists: true,
          user_id: existing_user.uuid,
          domain_name: 'example.com',
          email_language:,
        )
      end
    end

    context 'when the email is invalid' do
      let(:email) { 'invalid@' }

      it 'tracks unsuccessful user registration' do
        expect(@attempts_api_tracker).to receive(:user_registration_email_submitted).with(
          email:,
          success: false,
          failure_reason: { email: [:invalid] },
        )

        post :create, params: params

        expect(@analytics).to have_logged_event(
          'User Registration: Email Submitted',
          success: false,
          rate_limited: false,
          error_details: { email: { invalid: true } },
          email_already_exists: false,
          user_id: 'anonymous-uuid',
          domain_name: 'invalid',
          email_language:,
        )
      end

      it 'renders new' do
        post :create, params: params

        expect(response).to render_template(:new)
      end
    end

    context 'when the email is nil' do
      let(:email) { nil }
      it 'renders new' do
        expect(@attempts_api_tracker).to receive(:user_registration_email_submitted).with(
          email: nil,
          success: false,
          failure_reason: { email: [:invalid] },
        )

        post :create, params: params

        expect(response).to render_template(:new)
      end
    end

    context 'when the email is a Hash' do
      let(:email) { { foo: 'bar' } }

      it 'renders new' do
        expect(@attempts_api_tracker).to receive(:user_registration_email_submitted).with(
          email: nil,
          success: false,
          failure_reason: { email: [:invalid] },
        )

        post :create, params: params

        expect(response).to render_template(:new)
      end
    end
  end
end
