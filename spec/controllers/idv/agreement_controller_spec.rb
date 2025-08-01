require 'rails_helper'

RSpec.describe Idv::AgreementController do
  include FlowPolicyHelper

  let(:user) { create(:user) }

  before do
    stub_sign_in(user)
    stub_up_to(:welcome, idv_session: subject.idv_session)
    stub_analytics
    stub_attempts_tracker
  end

  describe '#step_info' do
    it 'returns a valid StepInfo object' do
      expect(Idv::AgreementController.step_info).to be_valid
    end
  end

  describe 'before_actions' do
    it 'includes authentication before_action' do
      expect(subject).to have_actions(
        :before,
        :confirm_two_factor_authenticated,
      )
    end

    it 'includes outage before_action' do
      expect(subject).to have_actions(
        :before,
        :check_for_mail_only_outage,
      )
    end
  end

  describe '#show' do
    let(:analytics_name) { 'IdV: doc auth agreement visited' }
    let(:analytics_args) do
      {
        step: 'agreement',
        analytics_id: 'Doc Auth',
      }
    end

    it 'renders the show template' do
      get :show

      expect(response).to render_template :show
    end

    it 'sends analytics_visited event' do
      get :show

      expect(@analytics).to have_logged_event(analytics_name, analytics_args)
    end

    it 'updates DocAuthLog agreement_view_count' do
      doc_auth_log = DocAuthLog.create(user_id: user.id)

      expect { get :show }.to(
        change { doc_auth_log.reload.agreement_view_count }.from(0).to(1),
      )
    end

    context 'welcome step is not complete' do
      it 'redirects to idv_welcome_url' do
        subject.idv_session.welcome_visited = nil

        get :show

        expect(response).to redirect_to(idv_welcome_url)
      end
    end

    context 'agreement already visited' do
      it 'does not redirect to hybrid_handoff' do
        stub_up_to(:agreement, idv_session: subject.idv_session)

        get :show

        expect(response).to render_template('idv/agreement/show')
      end

      context 'and verify info already completed' do
        before do
          stub_up_to(:verify_info, idv_session: subject.idv_session)
        end

        it 'renders the show template' do
          get :show
          expect(response).to render_template(:show)
        end
      end
    end
  end

  describe '#update' do
    let(:analytics_name) { 'IdV: doc auth agreement submitted' }

    let(:analytics_args) do
      {
        success: true,
        step: 'agreement',
        analytics_id: 'Doc Auth',
      }
    end

    let(:skip_hybrid_handoff) { nil }

    let(:params) do
      {
        doc_auth: {
          idv_consent_given: 1,
        },
        skip_hybrid_handoff: skip_hybrid_handoff,
      }.compact
    end

    it 'invalidates future steps' do
      expect(subject).to receive(:clear_future_steps!)

      put :update, params: params
    end

    it 'sends analytics_submitted event with consent given' do
      put :update, params: params

      expect(@analytics).to have_logged_event(analytics_name, analytics_args)
    end

    it 'does not set flow_path' do
      expect do
        put :update, params: params
      end.not_to change {
        subject.idv_session.flow_path
      }.from(nil)
    end

    context 'with a non-proofed user' do
      it 'does not track a reproofing event during initial proofing' do
        expect(@attempts_api_tracker).not_to receive(:idv_reproof)

        put :update, params:
      end
    end

    context 'with a previously proofed user' do
      context 'with a deactivated profile' do
        before { create(:profile, :deactivated, user:) }

        it 'tracks a reproofing event upon reproofing' do
          expect(@attempts_api_tracker).to receive(:idv_reproof)
          put :update, params:
        end
      end

      context 'with an activated legacy idv  profile' do
        it 'does not track a reproofing event during initial proofing' do
          expect(@attempts_api_tracker).not_to receive(:idv_reproof)

          put :update, params:
        end
        context 'when IAL2 is needed' do
          before do
            create(:profile, :active, user:)
            resolved_authn_context_result = Vot::Parser.new(
              acr_values: Saml::Idp::Constants::IAL_VERIFIED_FACIAL_MATCH_REQUIRED_ACR,
            ).parse
            allow(subject).to receive(:resolved_authn_context_result).and_return(
              resolved_authn_context_result,
            )
          end

          it 'tracks a reproofing event upon reproofing' do
            expect(@attempts_api_tracker).to receive(:idv_reproof)
            put :update, params:
          end
        end
      end
    end

    context 'on success' do
      context 'skip_hybrid_handoff present in params' do
        let(:skip_hybrid_handoff) { '' }

        it 'sets flow_path to standard' do
          expect do
            put :update, params: params
          end.to change {
            subject.idv_session.flow_path
          }.from(nil).to('standard').and change {
            subject.idv_session.skip_hybrid_handoff
          }.from(nil).to(true)
        end

        it 'redirects to how to verify' do
          put :update, params: params

          expect(response).to redirect_to(idv_how_to_verify_url)
        end

        it 'sets an idv_consent_given_at timestamp' do
          put :update, params: params

          expect(subject.idv_session.idv_consent_given_at).to be_within(3.seconds).of(Time.zone.now)
        end
      end

      context 'when both ipp and opt-in ipp are enabled' do
        before do
          allow(IdentityConfig.store).to receive(:in_person_proofing_opt_in_enabled) { true }
          allow(IdentityConfig.store).to receive(:in_person_proofing_enabled) { true }
        end

        it 'redirects to hybrid handoff with new content' do
          put :update, params: params
          expect(response).to redirect_to(idv_hybrid_handoff_url)
        end
      end

      context 'when ipp is enabled but opt-in ipp is disabled' do
        before do
          allow(IdentityConfig.store).to receive(:in_person_proofing_enabled) { true }
          allow(IdentityConfig.store).to receive(:in_person_proofing_opt_in_enabled) { false }
        end

        it 'redirects to hybrid handoff' do
          put :update, params: params
          expect(response).to redirect_to(idv_hybrid_handoff_url)
        end
      end

      context 'when ipp is disabled and opt-in ipp is enabled' do
        before do
          allow(IdentityConfig.store).to receive(:in_person_proofing_enabled) { false }
          allow(IdentityConfig.store).to receive(:in_person_proofing_opt_in_enabled) { true }
        end

        it 'redirects to hybrid handoff' do
          put :update, params: params
          expect(response).to redirect_to(idv_hybrid_handoff_url)
        end
      end

      context 'when both ipp and opt-in ipp are disabled' do
        before do
          allow(IdentityConfig.store).to receive(:in_person_proofing_enabled) { false }
          allow(IdentityConfig.store).to receive(:in_person_proofing_opt_in_enabled) { false }
        end

        it 'redirects to hybrid handoff' do
          put :update, params: params
          expect(response).to redirect_to(idv_hybrid_handoff_url)
        end
      end
    end

    context 'on failure' do
      let(:skip_hybrid_handoff) { nil }

      let(:params) do
        {
          doc_auth: {
            idv_consent_given: nil,
          },
          skip_hybrid_handoff: skip_hybrid_handoff,
        }.compact
      end

      it 'renders the form again' do
        put :update, params: params
        expect(response).to render_template('idv/agreement/show')
      end

      it 'does not set IDV consent flags' do
        put :update, params: params

        expect(subject.idv_session.idv_consent_given?).to eq(false)
        expect(subject.idv_session.idv_consent_given_at).to be_nil
      end
    end
  end
end
