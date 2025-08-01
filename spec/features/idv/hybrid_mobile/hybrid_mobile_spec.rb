require 'rails_helper'

RSpec.describe 'Hybrid Flow', :allow_net_connect_on_start do
  include IdvHelper
  include IdvStepHelper
  include DocAuthHelper
  include AbTestsHelper
  include PassportApiHelpers

  let(:phone_number) { '415-555-0199' }
  let(:sp) { :oidc }
  let(:passports_enabled) { false }
  let(:max_attempts) { IdentityConfig.store.doc_auth_max_attempts }

  before do
    allow(FeatureManagement).to receive(:doc_capture_polling_enabled?).and_return(true)
    allow(IdentityConfig.store).to receive(:doc_auth_max_attempts).and_return(max_attempts)
    allow(IdentityConfig.store).to receive(:socure_docv_enabled).and_return(true)
    allow(IdentityConfig.store).to receive(:use_vot_in_sp_requests).and_return(true)
    allow(IdentityConfig.store).to receive(:doc_auth_passports_enabled)
      .and_return(passports_enabled)
    allow(IdentityConfig.store).to receive(:doc_auth_mock_dos_api).and_return(true)
    allow(Telephony).to receive(:send_doc_auth_link).and_wrap_original do |impl, config|
      @sms_link = config[:link]
      impl.call(**config)
    end.at_least(1).times
  end

  it 'proofs and hands off to mobile', js: true do
    user = nil

    perform_in_browser(:desktop) do
      visit_idp_from_sp_with_ial2(sp)
      user = sign_up_and_2fa_ial1_user

      complete_doc_auth_steps_before_hybrid_handoff_step
      clear_and_fill_in(:doc_auth_phone, phone_number)
      click_send_link

      expect(page).to have_content(t('doc_auth.headings.text_message'))
      expect(page).to have_content(t('doc_auth.info.you_entered'))
      expect(page).to have_content('+1 415-555-0199')

      # Confirm that Continue button is not shown when polling is enabled
      expect(page).not_to have_content(t('doc_auth.buttons.continue'))
    end

    expect(@sms_link).to be_present

    perform_in_browser(:mobile) do
      visit @sms_link

      # Confirm that jumping to LinkSent page does not cause errors
      visit idv_link_sent_url
      expect(page).to have_current_path(root_url)

      # Confirm that we end up on the LN / Mock page even if we try to
      # go to the Socure one.
      visit idv_hybrid_mobile_socure_document_capture_url
      expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)

      # Confirm that clicking cancel and then coming back doesn't cause errors
      click_link 'Cancel'
      visit idv_hybrid_mobile_document_capture_url

      # Confirm that jumping to Phone page does not cause errors
      visit idv_phone_url
      expect(page).to have_current_path(root_url)
      visit idv_hybrid_mobile_document_capture_url

      # Confirm that jumping to Welcome page does not cause errors
      visit idv_welcome_url
      expect(page).to have_current_path(root_url)
      visit idv_hybrid_mobile_document_capture_url

      expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
      expect(page).not_to have_content(t('doc_auth.headings.document_capture_selfie'))
      attach_and_submit_images

      expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
      expect(page).to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
      expect(page).to have_text(t('doc_auth.instructions.switch_back'))
      expect_step_indicator_current_step(t('step_indicator.flows.idv.verify_id'))

      # Confirm app disallows jumping back to DocumentCapture page
      visit idv_hybrid_mobile_document_capture_url
      expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
    end

    perform_in_browser(:desktop) do
      expect(page).to_not have_content(t('doc_auth.headings.text_message'), wait: 10)
      expect(page).to have_current_path(idv_ssn_path)

      fill_out_ssn_form_ok
      click_idv_continue

      expect(page).to have_content(t('headings.verify'))
      complete_verify_step

      prefilled_phone = page.find(id: 'idv_phone_form_phone').value

      expect(
        PhoneFormatter.format(prefilled_phone),
      ).to eq(
        PhoneFormatter.format(user.default_phone_configuration.phone),
      )

      fill_out_phone_form_ok
      verify_phone_otp

      fill_in t('idv.form.password'), with: Features::SessionHelper::VALID_PASSWORD
      click_idv_continue

      acknowledge_and_confirm_personal_key

      validate_idv_completed_page(user)
      click_agree_and_continue

      validate_return_to_sp
    end
  end

  context 'when facial confirmation is requested' do
    it 'proofs and hands off to mobile', js: true do
      user = nil

      perform_in_browser(:desktop) do
        visit_idp_from_oidc_sp_with_ial2(facial_match_required: true)

        user = sign_up_and_2fa_ial1_user

        complete_doc_auth_steps_before_hybrid_handoff_step
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link

        expect(page).to have_content(t('doc_auth.headings.text_message'))
        expect(page).to have_content(t('doc_auth.info.you_entered'))
        expect(page).to have_content('+1 415-555-0199')

        # Confirm that Continue button is not shown when polling is enabled
        expect(page).not_to have_content(t('doc_auth.buttons.continue'))
      end

      expect(@sms_link).to be_present

      perform_in_browser(:mobile) do
        visit @sms_link

        # Confirm that jumping to LinkSent page does not cause errors
        visit idv_link_sent_url
        expect(page).to have_current_path(root_url)
        visit idv_hybrid_mobile_document_capture_url

        # Confirm that clicking cancel and then coming back doesn't cause errors
        click_link 'Cancel'
        visit idv_hybrid_mobile_document_capture_url

        # Confirm that jumping to Phone page does not cause errors
        visit idv_phone_url
        expect(page).to have_current_path(root_url)
        visit idv_hybrid_mobile_document_capture_url

        # Confirm that jumping to Welcome page does not cause errors
        visit idv_welcome_url
        expect(page).to have_current_path(root_url)
        visit idv_hybrid_mobile_document_capture_url

        expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
        attach_liveness_images
        submit_images

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
        expect(page).to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
        expect(page).to have_text(t('doc_auth.instructions.switch_back'))
        expect_step_indicator_current_step(t('step_indicator.flows.idv.verify_id'))

        # Confirm app disallows jumping back to DocumentCapture page
        visit idv_hybrid_mobile_document_capture_url
        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
      end

      perform_in_browser(:desktop) do
        expect(page).to_not have_content(t('doc_auth.headings.text_message'), wait: 10)
        expect(page).to have_current_path(idv_ssn_path)

        fill_out_ssn_form_ok
        click_idv_continue

        expect(page).to have_content(t('headings.verify'))
        complete_verify_step

        prefilled_phone = page.find(id: 'idv_phone_form_phone').value

        expect(
          PhoneFormatter.format(prefilled_phone),
        ).to eq(
          PhoneFormatter.format(user.default_phone_configuration.phone),
        )

        fill_out_phone_form_ok
        verify_phone_otp

        fill_in t('idv.form.password'), with: Features::SessionHelper::VALID_PASSWORD
        click_idv_continue

        acknowledge_and_confirm_personal_key

        validate_idv_completed_page(user)
        click_agree_and_continue

        validate_return_to_sp
      end
    end
  end

  context 'Passports Enabled', allow_net_connect_on_start: false, allow_browser_log: true do
    let(:passports_enabled) { true }
    let(:api_status) { 'UP' }

    before do
      allow(IdentityConfig.store).to receive(:doc_auth_passports_percent).and_return(100)
      stub_request(:get, IdentityConfig.store.dos_passport_composite_healthcheck_endpoint)
        .to_return({ status: 200, body: { status: api_status }.to_json })
      reload_ab_tests
    end

    after do
      reload_ab_tests
    end

    context 'valid passport data', js: true do
      let(:passport_image) do
        Rails.root.join(
          'spec', 'fixtures',
          'passport_credential.yml'
        )
      end

      it 'works with valid passport data' do
        user = nil

        perform_in_browser(:desktop) do
          user = sign_in_and_2fa_user

          complete_doc_auth_steps_before_hybrid_handoff_step
          clear_and_fill_in(:doc_auth_phone, phone_number)
          click_send_link

          expect(page).to have_content(t('doc_auth.headings.text_message'))
          expect(page).to have_content(t('doc_auth.info.you_entered'))
          expect(page).to have_content('+1 415-555-0199')

          # Confirm that Continue button is not shown when polling is enabled
          expect(page).not_to have_content(t('doc_auth.buttons.continue'))
        end

        expect(@sms_link).to be_present

        perform_in_browser(:mobile) do
          visit @sms_link
          expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
          choose_id_type(:passport)
          expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
          attach_passport_image(passport_image)
          submit_images
          expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
          expect(page).to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
          expect(page).to have_text(t('doc_auth.instructions.switch_back'))
          expect_step_indicator_current_step(t('step_indicator.flows.idv.verify_id'))

          # Confirm app disallows jumping back to DocumentCapture page
          visit idv_hybrid_mobile_document_capture_url
          expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
        end

        perform_in_browser(:desktop) do
          expect(page).to_not have_content(t('doc_auth.headings.text_message'), wait: 10)
          expect(page).to have_current_path(idv_ssn_path)

          fill_out_ssn_form_ok
          click_idv_continue
          expect_step_indicator_current_step(t('step_indicator.flows.idv.verify_info'))
          expect(page).to have_content(t('doc_auth.headings.address'))
          fill_in 'idv_form_address1', with: '123 Main St'
          fill_in 'idv_form_city', with: 'Nowhere'
          select 'Virginia', from: 'idv_form_state'
          fill_in 'idv_form_zipcode', with: '66044'
          click_idv_continue
          expect(page).to have_current_path(idv_verify_info_path)
          expect(page).to have_content('VA')
          expect(page).to have_content('123 Main St')
          expect(page).to have_content('Nowhere')
          complete_verify_step

          prefilled_phone = page.find(id: 'idv_phone_form_phone').value

          expect(
            PhoneFormatter.format(prefilled_phone),
          ).to eq(
            PhoneFormatter.format(user.default_phone_configuration.phone),
          )

          fill_out_phone_form_ok
          verify_phone_otp
        end
      end
    end

    context 'invalid passport data', js: true do
      let(:passport_image) do
        Rails.root.join(
          'spec', 'fixtures',
          'passport_bad_mrz_credential.yml'
        )
      end

      before do
        perform_in_browser(:desktop) do
          sign_in_and_2fa_user

          complete_doc_auth_steps_before_hybrid_handoff_step
          clear_and_fill_in(:doc_auth_phone, phone_number)
          click_send_link

          expect(page).to have_content(t('doc_auth.headings.text_message'))
          expect(page).to have_content(t('doc_auth.info.you_entered'))
          expect(page).to have_content('+1 415-555-0199')

          # Confirm that Continue button is not shown when polling is enabled
          expect(page).not_to have_content(t('doc_auth.buttons.continue'))
        end
      end

      it 'correctly processes invalid passport mrz data', js: true do
        expect(@sms_link).to be_present

        perform_in_browser(:mobile) do
          visit @sms_link
          expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
          choose_id_type(:passport)
          expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
          attach_passport_image(passport_image)
          submit_images
          expect(page).not_to have_current_path(idv_hybrid_mobile_capture_complete_url)
          expect(page).to have_content(t('doc_auth.info.review_passport'))
          expect_to_try_again(is_hybrid: true)
          expect(page).to have_content(t('doc_auth.info.review_passport'))
        end

        perform_in_browser(:desktop) do
          page.refresh
          expect(page).to have_current_path(idv_link_sent_url)
        end
      end

      context 'with a network error' do
        let(:passport_image) do
          Rails.root.join(
            'spec', 'fixtures',
            'passport_credential.yml'
          )
        end
        before do
          DocAuth::Mock::DocAuthMockClient.mock_response!(
            method: :post_passport_image,
            response: DocAuth::Response.new(
              success: false,
              errors: { network: I18n.t('doc_auth.errors.general.network_error') },
            ),
          )
        end

        it 'shows the error message' do
          expect(@sms_link).to be_present

          perform_in_browser(:mobile) do
            visit @sms_link
            expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
            choose_id_type(:passport)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
            attach_passport_image(passport_image)
            submit_images
            expect(page).not_to have_current_path(idv_hybrid_mobile_capture_complete_url)
            expect(page).to have_content(t('doc_auth.errors.general.network_error'))
            expect_rate_limit_warning(max_attempts - 1)
          end

          perform_in_browser(:desktop) do
            page.refresh
            expect(page).to have_current_path(idv_link_sent_url)
          end
        end
      end

      context 'pii validation error' do
        let(:passport_image) do
          Rails.root.join(
            'spec', 'fixtures',
            'passport_bad_pii_credentials.yml'
          )
        end

        it 'fails pii check' do
          expect(@sms_link).to be_present

          perform_in_browser(:mobile) do
            visit @sms_link
            expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
            choose_id_type(:passport)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
            attach_passport_image(passport_image)
            submit_images
            expect(page).not_to have_current_path(idv_hybrid_mobile_capture_complete_url)
            expect_to_try_again(is_hybrid: true)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
            expect_rate_limit_warning(max_attempts - 1)
          end

          perform_in_browser(:desktop) do
            page.refresh
            expect(page).to have_current_path(idv_link_sent_url)
          end
        end
      end

      context 'when MRZ request responds with 400 error' do
        let(:fake_dos_api_endpoint) { 'http://fake_dos_api_endpoint/' }

        before do
          allow(IdentityConfig.store).to receive(:doc_auth_mock_dos_api).and_return(false)
          allow(IdentityConfig.store).to receive(:dos_passport_mrz_endpoint)
            .and_return(fake_dos_api_endpoint)
          stub_request(:post, fake_dos_api_endpoint)
            .to_return(status: 400, body: '{}', headers: {})
        end

        it 'shows the error message' do
          expect(@sms_link).to be_present

          perform_in_browser(:mobile) do
            visit @sms_link
            expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
            choose_id_type(:passport)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
            attach_passport_image
            submit_images
            expect(page).not_to have_current_path(idv_hybrid_mobile_capture_complete_url)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
          end

          perform_in_browser(:desktop) do
            page.refresh
            expect(page).to have_current_path(idv_link_sent_url)
          end
        end
      end

      context 'when MRZ request responds with 500 error' do
        let(:fake_dos_api_endpoint) { 'http://fake_dos_api_endpoint/' }

        before do
          allow(IdentityConfig.store).to receive(:doc_auth_mock_dos_api).and_return(false)
          allow(IdentityConfig.store).to receive(:dos_passport_mrz_endpoint)
            .and_return(fake_dos_api_endpoint)
          stub_request(:post, fake_dos_api_endpoint)
            .to_return(status: 500, body: '{}', headers: {})
        end

        it 'shows the error message' do
          expect(@sms_link).to be_present

          perform_in_browser(:mobile) do
            visit @sms_link
            expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
            choose_id_type(:passport)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
            attach_passport_image
            submit_images
            expect(page).not_to have_current_path(idv_hybrid_mobile_capture_complete_url)
            expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
          end

          perform_in_browser(:desktop) do
            page.refresh
            expect(page).to have_current_path(idv_link_sent_url)
          end
        end
      end
    end
  end

  it 'shows the waiting screen correctly after cancelling from mobile and restarting', js: true do
    perform_in_browser(:desktop) do
      sign_in_and_2fa_user
      complete_doc_auth_steps_before_hybrid_handoff_step
      clear_and_fill_in(:doc_auth_phone, phone_number)
      click_send_link

      expect(page).to have_content(t('doc_auth.headings.text_message'))
    end

    expect(@sms_link).to be_present

    perform_in_browser(:mobile) do
      visit @sms_link
      expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
      expect(page).not_to have_content(t('doc_auth.headings.document_capture_selfie'))
      click_on t('links.cancel')
      click_on t('forms.buttons.cancel') # Yes, cancel
    end

    perform_in_browser(:desktop) do
      expect(page).to_not have_content(t('doc_auth.headings.text_message'), wait: 10)
      clear_and_fill_in(:doc_auth_phone, phone_number)
      click_send_link

      expect(page).to have_content(t('doc_auth.headings.text_message'))
    end
  end

  context 'user is rate limited on mobile' do
    let(:max_attempts) { IdentityConfig.store.doc_auth_max_attempts }

    before do
      allow(IdentityConfig.store).to receive(:doc_auth_max_attempts).and_return(max_attempts)
      DocAuth::Mock::DocAuthMockClient.mock_response!(
        method: :post_front_image,
        response: DocAuth::Response.new(
          success: false,
          errors: { network: I18n.t('doc_auth.errors.general.network_error') },
        ),
      )
    end

    it 'shows capture complete on mobile and error page on desktop', js: true do
      perform_in_browser(:desktop) do
        sign_in_and_2fa_user
        complete_doc_auth_steps_before_hybrid_handoff_step
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link

        expect(page).to have_content(t('doc_auth.headings.text_message'))
      end

      expect(@sms_link).to be_present

      perform_in_browser(:mobile) do
        visit @sms_link

        (max_attempts - 1).times do
          attach_and_submit_images
          click_on t('idv.failure.button.warning')
        end

        # final failure
        attach_and_submit_images

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
        expect(page).not_to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
        expect(page).to have_text(t('doc_auth.instructions.switch_back'))
      end

      perform_in_browser(:desktop) do
        expect(page).to have_current_path(idv_session_errors_rate_limited_path, wait: 10)
      end
    end
  end

  context 'passport hybrid flow', allow_net_connect_on_start: false do
    before do
      allow(IdentityConfig.store).to receive(:socure_docv_enabled).and_return(false)
      allow(IdentityConfig.store).to receive(:doc_auth_passports_enabled).and_return(true)
      allow(IdentityConfig.store).to receive(:doc_auth_passports_percent).and_return(100)
      allow(IdentityConfig.store).to receive(:doc_auth_vendor_default).and_return('mock')
      stub_request(:get, IdentityConfig.store.dos_passport_composite_healthcheck_endpoint)
        .to_return({ status: 200, body: { status: 'UP' }.to_json })
      reload_ab_tests
    end

    after do
      reload_ab_tests
    end

    it 'review step shows one image if passport selected', js: true do
      perform_in_browser(:desktop) do
        sign_in_and_2fa_user
        complete_doc_auth_steps_before_hybrid_handoff_step
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link
      end

      expect(@sms_link).to be_present

      perform_in_browser(:mobile) do
        visit @sms_link
        expect(page).to have_current_path(idv_hybrid_mobile_choose_id_type_url)
        choose(t('doc_auth.forms.id_type_preference.passport'))
        click_on t('forms.buttons.continue')
        expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
        attach_passport_image(
          Rails.root.join(
            'spec', 'fixtures',
            'passport_bad_mrz_credential.yml'
          ),
        )
        submit_images
        expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
        click_on t('idv.failure.button.warning')
        expect(page).to have_content(t('doc_auth.headings.document_capture_passport'))
        expect(page).not_to have_content(t('doc_auth.headings.document_capture_back'))
        expect(page).to have_content(t('doc_auth.headings.review_issues_passport'))
        expect(page).to have_content(t('doc_auth.info.review_passport'))
      end
    end
  end

  context 'after rate limiting user can capture on last attempt' do
    let(:max_attempts) { 1 }

    before do
      allow(IdentityConfig.store).to receive(:doc_auth_max_attempts).and_return(max_attempts)
      DocAuth::Mock::DocAuthMockClient.reset!
    end

    it 'successfully captures image on last attempt', js: true do
      perform_in_browser(:desktop) do
        sign_in_and_2fa_user
        complete_doc_auth_steps_before_hybrid_handoff_step
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link

        expect(page).to have_content(t('doc_auth.headings.text_message'))
      end

      expect(@sms_link).to be_present

      perform_in_browser(:mobile) do
        visit @sms_link

        # final attempt
        attach_and_submit_images

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
        expect(page).to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
        expect(page).to have_text(t('doc_auth.instructions.switch_back'))
      end

      perform_in_browser(:desktop) do
        expect(page).to have_current_path(idv_ssn_url, wait: 10)
      end
    end
  end

  context 'barcode read error on mobile (redo document capture)', allow_browser_log: true do
    it 'continues to ssn on desktop when user selects Continue', js: true do
      perform_in_browser(:desktop) do
        sign_in_and_2fa_user
        complete_doc_auth_steps_before_hybrid_handoff_step
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link

        expect(page).to have_content(t('doc_auth.headings.text_message'))
      end

      expect(@sms_link).to be_present

      perform_in_browser(:mobile) do
        visit @sms_link

        mock_doc_auth_attention_with_barcode
        attach_and_submit_images
        click_idv_continue

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
        expect(page).to have_content(strip_nbsp(t('doc_auth.headings.capture_complete')))
        expect(page).to have_text(t('doc_auth.instructions.switch_back'))
      end

      perform_in_browser(:desktop) do
        expect(page).to have_current_path(idv_ssn_path, wait: 10)

        fill_out_ssn_form_ok
        click_idv_continue

        expect(page).to have_current_path(idv_verify_info_path, wait: 10)

        # verify pii is displayed
        expect(page).to have_text('DAVID')
        expect(page).to have_text('SAMPLE')
        expect(page).to have_text('123 ABC AVE')

        warning_link_text = t('doc_auth.headings.capture_scan_warning_link')
        click_link warning_link_text

        expect(page).to have_current_path(idv_hybrid_handoff_path, ignore_query: true)
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link
      end

      perform_in_browser(:mobile) do
        visit @sms_link

        DocAuth::Mock::DocAuthMockClient.reset!
        attach_and_submit_images

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
      end

      perform_in_browser(:desktop) do
        expect(page).to have_current_path(idv_ssn_path, wait: 10)
        complete_ssn_step
        expect(page).to have_current_path(idv_verify_info_path)

        # verify orig pii no longer displayed
        expect(page).not_to have_text('DAVID')
        expect(page).not_to have_text('SAMPLE')
        expect(page).not_to have_text('123 ABC AVE')
        # verify new pii from redo is displayed
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:first_name])
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:last_name])
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:address1])

        complete_verify_step
      end
    end
  end

  context 'barcode read error on desktop, redo document capture on mobile' do
    it 'continues to ssn on desktop when user selects Continue', js: true do
      perform_in_browser(:desktop) do
        sign_in_and_2fa_user
        complete_doc_auth_steps_before_document_capture_step
        mock_doc_auth_attention_with_barcode
        attach_and_submit_images
        click_idv_continue
        expect(page).to have_current_path(idv_ssn_path, wait: 10)

        fill_out_ssn_form_ok
        click_idv_continue

        expect(page).to have_current_path(idv_verify_info_path, wait: 10)

        # verify pii is displayed
        expect(page).to have_text('DAVID')
        expect(page).to have_text('SAMPLE')
        expect(page).to have_text('123 ABC AVE')

        warning_link_text = t('doc_auth.headings.capture_scan_warning_link')
        click_link warning_link_text

        expect(page).to have_current_path(idv_hybrid_handoff_path, ignore_query: true)
        clear_and_fill_in(:doc_auth_phone, phone_number)
        click_send_link
      end

      perform_in_browser(:mobile) do
        visit @sms_link

        DocAuth::Mock::DocAuthMockClient.reset!

        expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)
        expect(page).not_to have_content(t('doc_auth.headings.document_capture_selfie'))

        visit(idv_hybrid_mobile_document_capture_url(selfie: true))
        expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url(selfie: true))
        expect(page).not_to have_content(t('doc_auth.headings.document_capture_selfie'))

        attach_and_submit_images

        expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
      end

      perform_in_browser(:desktop) do
        expect(page).to have_current_path(idv_ssn_path, wait: 10)
        complete_ssn_step
        expect(page).to have_current_path(idv_verify_info_path)

        # verify orig pii no longer displayed
        expect(page).not_to have_text('DAVID')
        expect(page).not_to have_text('SAMPLE')
        expect(page).not_to have_text('123 ABC AVE')
        # verify new pii from redo is displayed
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:first_name])
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:last_name])
        expect(page).to have_text(Idp::Constants::MOCK_IDV_APPLICANT[:address1])

        complete_verify_step
      end
    end
  end

  it 'prefills the phone number used on the phone step if the user has no MFA phone', :js do
    user = create(:user, :with_authentication_app)

    perform_in_browser(:desktop) do
      start_idv_from_sp(facial_match_required: true)
      sign_in_and_2fa_user(user)

      complete_doc_auth_steps_before_hybrid_handoff_step
      clear_and_fill_in(:doc_auth_phone, phone_number)
      click_send_link
    end

    expect(@sms_link).to be_present

    perform_in_browser(:mobile) do
      visit @sms_link

      expect(page).to have_current_path(idv_hybrid_mobile_document_capture_url)

      attach_liveness_images
      submit_images

      expect(page).to have_current_path(idv_hybrid_mobile_capture_complete_url)
      expect(page).to have_text(t('doc_auth.instructions.switch_back'))
    end

    perform_in_browser(:desktop) do
      expect(page).to have_current_path(idv_ssn_path, wait: 10)

      fill_out_ssn_form_ok
      click_idv_continue

      expect(page).to have_content(t('headings.verify'))
      complete_verify_step

      prefilled_phone = page.find(id: 'idv_phone_form_phone').value

      expect(
        PhoneFormatter.format(prefilled_phone),
      ).to eq(
        PhoneFormatter.format(phone_number),
      )
    end
  end
end
