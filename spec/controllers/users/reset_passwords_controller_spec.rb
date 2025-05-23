require 'rails_helper'

RSpec.describe Users::ResetPasswordsController, devise: true do
  let(:password_error_message) do
    t('errors.attributes.password.too_short.other', count: Devise.password_length.first)
  end
  let(:success_properties) { { success: true } }

  describe '#edit' do
    let(:user) { instance_double('User', uuid: '123') }
    let(:email_address) { instance_double('EmailAddress') }

    before do
      stub_analytics
      stub_attempts_tracker
    end

    context 'when token is passed via the params' do
      it 'redirects to the clean edit password url with token stored in session' do
        get :edit, params: { reset_password_token: 'foo' }
        expect(response).to redirect_to(edit_user_password_url)
        expect(session[:reset_password_token]).to eq('foo')
      end
    end

    context 'no user matches token' do
      let(:token) { 'foo' }
      before do
        session[:reset_password_token] = token
      end

      it 'redirects to page where user enters email for password reset token' do
        expect(@attempts_api_tracker).to receive(:forgot_password_email_confirmed).with(
          success: false,
          failure_reason: { user: [:blank] },
        )

        get :edit

        expect(@analytics).to have_logged_event(
          'Password Reset: Token Submitted',
          success: false,
          error_details: { user: { blank: true } },
        )
        expect(response).to redirect_to new_user_password_path
        expect(flash[:error]).to eq t('devise.passwords.invalid_token')
      end
    end

    context 'token expired' do
      let(:token) { 'foo' }
      before do
        session[:reset_password_token] = token
      end
      let(:user) { instance_double('User', uuid: '123') }

      before do
        allow(User).to receive(:with_reset_password_token).with(token).and_return(user)
        allow(User).to receive(:with_reset_password_token).with('bar').and_return(nil)
        allow(user).to receive(:reset_password_period_valid?).and_return(false)
      end

      context 'no user matches token' do
        before do
          session[:reset_password_token] = 'bar'
        end

        it 'redirects to page where user enters email for password reset token' do
          expect(@attempts_api_tracker).to receive(:forgot_password_email_confirmed).with(
            success: false,
            failure_reason: { user: [:blank] },
          )

          get :edit

          expect(@analytics).to have_logged_event(
            'Password Reset: Token Submitted',
            success: false,
            error_details: { user: { blank: true } },
          )
          expect(response).to redirect_to new_user_password_path
          expect(flash[:error]).to eq t('devise.passwords.invalid_token')
        end
      end

      context 'token expired' do
        let(:user) { instance_double('User', uuid: '123') }

        before do
          allow(User).to receive(:with_reset_password_token).with('foo').and_return(user)
          allow(user).to receive(:reset_password_period_valid?).and_return(false)
        end

        it 'redirects to page where user enters email for password reset token' do
          expect(@attempts_api_tracker).to receive(:forgot_password_email_confirmed).with(
            success: false,
            failure_reason: { user: [:token_expired] },
          )

          get :edit

          expect(@analytics).to have_logged_event(
            'Password Reset: Token Submitted',
            success: false,
            error_details: { user: { token_expired: true } },
            user_id: '123',
          )
          expect(response).to redirect_to new_user_password_path
          expect(flash[:error]).to eq t('devise.passwords.token_expired')
        end
      end

      context 'token is valid' do
        render_views
        let(:user) { instance_double('User', uuid: '123') }
        let(:email_address) { instance_double('EmailAddress') }

        before do
          stub_analytics
          allow(User).to receive(:with_reset_password_token).with('foo').and_return(user)
          allow(user).to receive(:reset_password_period_valid?).and_return(true)
          allow(user).to receive(:email_addresses).and_return([email_address])
        end

        it 'displays the form to enter a new password' do
          expect(email_address).to receive(:email).twice

          forbidden = instance_double(ForbiddenPasswords)
          allow(ForbiddenPasswords).to receive(:new).with(email_address.email).and_return(forbidden)
          expect(forbidden).to receive(:call)
          expect(@attempts_api_tracker).to receive(:forgot_password_email_confirmed).with(
            success: true,
            failure_reason: nil,
          )

          get :edit

          expect(response).to render_template :edit
          expect(flash.keys).to be_empty
        end
      end
    end

    context 'when token is valid' do
      before do
        allow(User).to receive(:with_reset_password_token).with('foo').and_return(user)
        allow(user).to receive(:reset_password_period_valid?).and_return(true)
        allow(user).to receive(:email_addresses).and_return([email_address])
        session[:reset_password_token] = 'foo'
      end
      it 'renders the template to the clean edit password url with token stored in session' do
        expect(email_address).to receive(:email).twice

        forbidden = instance_double(ForbiddenPasswords)
        allow(ForbiddenPasswords).to receive(:new)
          .with(email_address.email).and_return(forbidden)
        expect(forbidden).to receive(:call)
        expect(@attempts_api_tracker).to receive(:forgot_password_email_confirmed).with(
          success: true,
          failure_reason: nil,
        )

        get :edit
        expect(response).to render_template :edit
        expect(flash.keys).to be_empty
      end
    end
  end

  describe '#update' do
    before do
      stub_analytics
      stub_attempts_tracker
    end
    context 'user submits new password after token expires' do
      it 'redirects to page where user enters email for password reset token' do
        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)
        user = create(
          :user,
          :fully_registered,
          reset_password_sent_at: Time.zone.now - Devise.reset_password_within - 1.hour,
          reset_password_token: db_confirmation_token,
        )

        params = {
          password: 'short',
          password_confirmation: 'short',
          reset_password_token: raw_reset_token,
        }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: false,
          failure_reason: {
            password: [:too_short],
            password_confirmation: [:too_short],
            reset_password_token: [:token_expired],
          },
        )

        get :edit, params: { reset_password_token: raw_reset_token }
        put :update, params: { reset_password_form: params }

        expect(@analytics).to have_logged_event(
          'Password Reset: Password Submitted',
          success: false,
          error_details: {
            password: { too_short: true },
            password_confirmation: { too_short: true },
            reset_password_token: { token_expired: true },
          },
          user_id: user.uuid,
          profile_deactivated: false,
          pending_profile_invalidated: false,
          pending_profile_pending_reasons: '',
        )
        expect(response).to redirect_to new_user_password_path
        expect(flash[:error]).to eq t('devise.passwords.token_expired')
      end
    end

    context 'user submits invalid new password' do
      let(:password) { 'short' }
      let(:password_confirmation) { 'short' }

      it 'renders edit' do
        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)
        user = create(
          :user,
          :fully_registered,
          reset_password_token: db_confirmation_token,
          reset_password_sent_at: Time.zone.now,
        )
        form_params = {
          password: password,
          password_confirmation: password_confirmation,
          reset_password_token: raw_reset_token,
        }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: false,
          failure_reason: {
            password: [:too_short],
            password_confirmation: [:too_short],
          },
        )

        put :update, params: { reset_password_form: form_params }

        expect(@analytics).to have_logged_event(
          'Password Reset: Password Submitted',
          success: false,
          error_details: {
            password: { too_short: true },
            password_confirmation: { too_short: true },
          },
          user_id: user.uuid,
          profile_deactivated: false,
          pending_profile_invalidated: false,
          pending_profile_pending_reasons: '',
        )
        expect(assigns(:forbidden_passwords)).to all(be_a(String))
        expect(response).to render_template(:edit)
      end
    end

    context 'user submits password confirmation that does not match' do
      let(:password) { 'salty pickles' }
      let(:password_confirmation) { 'salty pickles2' }

      it 'renders edit' do
        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)
        user = create(
          :user,
          :fully_registered,
          reset_password_token: db_confirmation_token,
          reset_password_sent_at: Time.zone.now,
        )
        form_params = {
          password: password,
          password_confirmation: password_confirmation,
          reset_password_token: raw_reset_token,
        }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: false,
          failure_reason: {
            password_confirmation: [:mismatch],
          },
        )

        put :update, params: { reset_password_form: form_params }

        expect(@analytics).to have_logged_event(
          'Password Reset: Password Submitted',
          success: false,
          error_details: {
            password_confirmation: { mismatch: true },
          },
          user_id: user.uuid,
          profile_deactivated: false,
          pending_profile_invalidated: false,
          pending_profile_pending_reasons: '',
        )
        expect(assigns(:forbidden_passwords)).to all(be_a(String))
        expect(response).to render_template(:edit)
      end
    end

    context 'user submits the reset password form twice' do
      let(:password) { 'a really long passw0rd' }

      it 'shows an invalid token error' do
        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)
        create(
          :user,
          :unconfirmed,
          reset_password_token: db_confirmation_token,
          reset_password_sent_at: Time.zone.now,
        )
        form_params = {
          password: password,
          password_confirmation: password,
          reset_password_token: raw_reset_token,
        }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: true,
          failure_reason: nil,
        )

        put :update, params: { reset_password_form: form_params }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: false,
          failure_reason: { reset_password_token: [:invalid_token] },
        )
        put :update, params: { reset_password_form: form_params }

        expect(response).to redirect_to new_user_password_path
        expect(flash[:error]).to eq t('devise.passwords.invalid_token')
      end
    end

    context 'IAL1 user submits valid new password' do
      let(:password) { 'a really long passw0rd' }

      it 'redirects to sign in page' do
        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)

        freeze_time do
          user = create(
            :user,
            :fully_registered,
            reset_password_token: db_confirmation_token,
            reset_password_sent_at: Time.zone.now,
          )
          old_confirmed_at = user.reload.confirmed_at
          allow(user).to receive(:active_profile).and_return(nil)

          security_event = PushNotification::PasswordResetEvent.new(user: user)
          expect(PushNotification::HttpPush).to receive(:deliver).with(security_event)

          stub_user_mailer(user)

          params = {
            password: password,
            password_confirmation: password,
            reset_password_token: raw_reset_token,
          }

          get :edit, params: { reset_password_token: raw_reset_token }

          expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
            success: true,
            failure_reason: nil,
          )
          put :update, params: { reset_password_form: params }

          expect(@analytics).to have_logged_event(
            'Password Reset: Password Submitted',
            success: true,
            user_id: user.uuid,
            profile_deactivated: false,
            pending_profile_invalidated: false,
            pending_profile_pending_reasons: '',
          )
          expect(user.events.password_changed.size).to be 1

          expect(response).to redirect_to new_user_session_path
          expect(flash[:info]).to eq t('devise.passwords.updated_not_active')
          expect(user.reload.confirmed_at).to eq old_confirmed_at
        end
      end
    end

    context 'ial2 user submits valid new password' do
      let(:password) { 'a really long passw0rd' }

      it 'deactivates the active profile and redirects' do
        stub_analytics

        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)
        user = create(
          :user,
          reset_password_token: db_confirmation_token,
          reset_password_sent_at: Time.zone.now,
        )
        _profile = create(:profile, :active, :verified, user: user)

        security_event = PushNotification::PasswordResetEvent.new(user: user)
        expect(PushNotification::HttpPush).to receive(:deliver).with(security_event)

        stub_user_mailer(user)

        get :edit, params: { reset_password_token: raw_reset_token }
        params = {
          password: password,
          password_confirmation: password,
          reset_password_token: raw_reset_token,
        }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: true,
          failure_reason: nil,
        )

        put :update, params: { reset_password_form: params }

        expect(@analytics).to have_logged_event(
          'Password Reset: Password Submitted',
          success: true,
          user_id: user.uuid,
          profile_deactivated: true,
          pending_profile_invalidated: false,
          pending_profile_pending_reasons: '',
        )
        expect(user.active_profile.present?).to eq false
        expect(response).to redirect_to new_user_session_path
      end
    end

    context 'unconfirmed user submits valid new password' do
      let(:password) { 'a really long passw0rd' }

      it 'confirms the user' do
        stub_analytics

        raw_reset_token, db_confirmation_token =
          Devise.token_generator.generate(User, :reset_password_token)

        user = create(
          :user,
          :unconfirmed,
          reset_password_token: db_confirmation_token,
          reset_password_sent_at: Time.zone.now,
        )

        security_event = PushNotification::PasswordResetEvent.new(user: user)
        expect(PushNotification::HttpPush).to receive(:deliver).with(security_event)

        stub_user_mailer(user)

        params = {
          password: password,
          password_confirmation: password,
          reset_password_token: raw_reset_token,
        }

        get :edit, params: { reset_password_token: raw_reset_token }

        expect(@attempts_api_tracker).to receive(:forgot_password_new_password_submitted).with(
          success: true,
          failure_reason: nil,
        )
        put :update, params: { reset_password_form: params }

        expect(@analytics).to have_logged_event(
          'Password Reset: Password Submitted',
          success: true,
          user_id: user.uuid,
          profile_deactivated: false,
          pending_profile_invalidated: false,
          pending_profile_pending_reasons: '',
        )
        expect(user.reload.confirmed?).to eq true
        expect(response).to redirect_to new_user_session_path
      end
    end
  end

  describe '#create' do
    before do
      stub_analytics
      stub_attempts_tracker
    end
    context 'no user matches email' do
      let(:email) { 'nonexistent@example.com' }

      it 'send an email to tell the user they do not have an account yet' do
        expect do
          put :create, params: {
            password_reset_email_form: { email: email },
          }
        end.to(change { ActionMailer::Base.deliveries.count }.by(1))

        expect(ActionMailer::Base.deliveries.last.subject)
          .to eq t('anonymous_mailer.password_reset_missing_user.subject')
        expect(@analytics).to have_logged_event(
          'Password Reset: Email Submitted',
          success: true,
          user_id: 'nonexistent-uuid',
          confirmed: false,
          active_profile: false,
        )
        expect(response).to redirect_to forgot_password_path
      end
    end

    context 'user exists' do
      let(:email) { 'test@example.com' }
      let(:email_param) { { email: email } }
      let!(:user) { create(:user, :fully_registered, **email_param) }

      it 'sends password reset email to user and tracks event' do
        expect(@attempts_api_tracker).to receive(:forgot_password_email_sent).with(email_param)

        expect do
          put :create, params: { password_reset_email_form: email_param }
        end.to change { ActionMailer::Base.deliveries.count }.by(1)

        expect(@analytics).to have_logged_event(
          'Password Reset: Email Submitted',
          success: true,
          user_id: user.uuid,
          confirmed: true,
          active_profile: false,
        )
        expect(response).to redirect_to forgot_password_path
      end
    end

    context 'user exists but is unconfirmed' do
      let(:user) { create(:user, :unconfirmed) }
      let(:params) do
        {
          password_reset_email_form: {
            email: user.email,
          },
        }
      end

      it 'sends missing user email and tracks event' do
        expect(@attempts_api_tracker).not_to receive(:forgot_password_email_sent)

        expect { put :create, params: params }
          .to change { ActionMailer::Base.deliveries.count }.by(1)

        expect(@analytics).to have_logged_event(
          'Password Reset: Email Submitted',
          success: true,
          user_id: user.uuid,
          confirmed: false,
          active_profile: false,
        )

        expect(ActionMailer::Base.deliveries.last.subject)
          .to eq t('anonymous_mailer.password_reset_missing_user.subject')
        expect(response).to redirect_to forgot_password_path
      end
    end

    context 'user is verified' do
      it 'captures in analytics that the user was verified' do
        user = create(:user, :fully_registered)
        create(:profile, :active, :verified, user: user)
        expect(@attempts_api_tracker).to receive(:forgot_password_email_sent)
          .with(email: user.email)

        params = { password_reset_email_form: { email: user.email } }
        put :create, params: params

        expect(@analytics).to have_logged_event(
          'Password Reset: Email Submitted',
          success: true,
          user_id: user.uuid,
          confirmed: true,
          active_profile: true,
        )
      end
    end

    context 'email is invalid' do
      it 'displays an error and tracks event' do
        expect(@attempts_api_tracker).not_to receive(:forgot_password_email_sent)

        params = { password_reset_email_form: { email: 'foo' } }
        expect { put :create, params: params }
          .to change { ActionMailer::Base.deliveries.count }.by(0)

        expect(@analytics).to have_logged_event(
          'Password Reset: Email Submitted',
          success: false,
          error_details: { email: { invalid: true } },
          user_id: 'nonexistent-uuid',
          confirmed: false,
          active_profile: false,
        )
        expect(response).to render_template :new
      end
    end

    it 'renders new if email is nil' do
      expect(@attempts_api_tracker).not_to receive(:forgot_password_email_sent)

      expect do
        post :create, params: { password_reset_email_form: { resend: false } }
      end.to change { ActionMailer::Base.deliveries.count }.by(0)

      expect(response).to render_template :new
    end

    it 'renders new if email is a Hash' do
      expect(@attempts_api_tracker).not_to receive(:forgot_password_email_sent)

      post :create, params: { password_reset_email_form: { email: { foo: 'bar' } } }

      expect(response).to render_template(:new)
    end
  end

  describe '#new' do
    it 'logs visit to analytics' do
      stub_analytics

      get :new

      expect(@analytics).to have_logged_event('Password Reset: Email Form Visited')
    end
  end

  def stub_user_mailer(user)
    mailer = instance_double(ActionMailer::MessageDelivery, deliver_now_or_later: true)
    user.email_addresses.each do |email_address|
      allow(UserMailer).to receive(:password_changed)
        .with(user, email_address, disavowal_token: instance_of(String))
        .and_return(mailer)
    end
  end
end
