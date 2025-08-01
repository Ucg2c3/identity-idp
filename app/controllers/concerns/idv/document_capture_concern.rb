# frozen_string_literal: true

module Idv
  module DocumentCaptureConcern
    extend ActiveSupport::Concern

    def handle_stored_result(user: current_user, store_in_session: true)
      if stored_result&.success? && validation_requirements_met?
        extract_pii_from_doc(user, store_in_session: store_in_session)
        flash[:success] = t('doc_auth.headings.capture_complete')
        successful_response
      else
        extra = { stored_result_present: stored_result.present? }
        failure(nil, extra)
      end
    end

    def successful_response
      FormResponse.new(success: true)
    end

    # copied from Flow::Failure module
    def failure(message = nil, extra = nil)
      form_response_params = { success: false }
      form_response_params[:errors] = error_hash(message)
      form_response_params[:extra] = extra unless extra.nil?
      FormResponse.new(**form_response_params)
    end

    def error_hash(message)
      {
        message: message || I18n.t('doc_auth.errors.general.network_error'),
        socure: stored_result&.errors&.dig(:socure),
        pii_validation: stored_result&.errors&.dig(:pii_validation),
        unaccepted_id_type: stored_result&.errors&.dig(:unaccepted_id_type),
        selfie_fail: stored_result&.errors&.dig(:selfie_fail),
      }
    end

    def extract_pii_from_doc(user, store_in_session: false)
      if defined?(idv_session) # hybrid mobile does not have idv_session
        idv_session.had_barcode_read_failure = stored_result.attention_with_barcode?
        # See also Idv::InPerson::StateIdController#update
        idv_session.doc_auth_vendor = document_capture_session.doc_auth_vendor
        if store_in_session
          idv_session.pii_from_doc = stored_result.pii_from_doc
          idv_session.selfie_check_performed = stored_result.selfie_check_performed?
        end
      end

      track_document_issuing_state(user, stored_result.pii_from_doc[:state])
    end

    def stored_result
      return @stored_result if defined?(@stored_result)
      @stored_result = document_capture_session&.load_result
    end

    def selfie_requirement_met?
      !resolved_authn_context_result.facial_match? ||
        stored_result.selfie_check_performed?
    end

    def mrz_requirement_met?
      return true if !document_capture_session.passport_requested?
      return false if submitted_id_type != 'passport'
      return false if !IdentityConfig.store.doc_auth_passports_enabled

      stored_result.mrz_status == :pass
    end

    def redirect_to_correct_vendor(vendor, in_hybrid_mobile:)
      return if IdentityConfig.store.doc_auth_redirect_to_correct_vendor_disabled

      expected_doc_auth_vendor = document_capture_session.doc_auth_vendor
      return if vendor == expected_doc_auth_vendor
      return if vendor == Idp::Constants::Vendors::LEXIS_NEXIS &&
                expected_doc_auth_vendor == Idp::Constants::Vendors::MOCK
      return if vendor == Idp::Constants::Vendors::SOCURE &&
                expected_doc_auth_vendor == Idp::Constants::Vendors::SOCURE_MOCK

      correct_path = correct_vendor_path(
        expected_doc_auth_vendor,
        in_hybrid_mobile: in_hybrid_mobile,
      )

      redirect_to correct_path
    end

    def correct_vendor_path(expected_doc_auth_vendor, in_hybrid_mobile:)
      case expected_doc_auth_vendor
      when Idp::Constants::Vendors::SOCURE, Idp::Constants::Vendors::SOCURE_MOCK
        in_hybrid_mobile ? idv_hybrid_mobile_socure_document_capture_path
                         : idv_socure_document_capture_path
      when Idp::Constants::Vendors::LEXIS_NEXIS, Idp::Constants::Vendors::MOCK
        in_hybrid_mobile ? idv_hybrid_mobile_document_capture_path
                         : idv_document_capture_path
      end
    end

    def fetch_test_verification_data
      return unless IdentityConfig.store.socure_docv_verification_data_test_mode

      docv_transaction_token_override = params.permit(:docv_token)[:docv_token]
      return unless IdentityConfig.store.socure_docv_verification_data_test_mode_tokens
        .include?(docv_transaction_token_override)

      SocureDocvResultsJob.perform_now(
        document_capture_session_uuid:,
        docv_transaction_token_override:,
        async: true,
      )
    end

    def track_document_request_event(document_request:, document_response:, timer:)
      document_request_body = JSON.parse(document_request.body, symbolize_names: true)[:config]
      response_hash = document_response.to_h
      log_extras = {
        reference_id: response_hash[:referenceId],
        vendor: 'Socure',
        vendor_request_time_in_ms: timer.results['vendor_request'],
        success: @url.present?,
        customer_user_id: document_request_body[:customerUserId],
        document_type: document_request_body[:documentType],
        use_case_key: document_request_body[:useCaseKey],
        docv_transaction_token: response_hash.dig(:data, :docvTransactionToken),
        socure_status: response_hash[:status],
        socure_msg: response_hash[:msg],
      }
      analytics_hash = log_extras
        .merge(analytics_arguments)
        .merge(document_request_body).except(
          :documentType, # requested document type
          :useCaseKey,
        )
        .merge(response_body: document_response.to_h)
      analytics.idv_socure_document_request_submitted(**analytics_hash)
    end

    def choose_id_type_path
      idv_choose_id_type_path
    end

    def doc_auth_upload_enabled?
      # false for now until we consolidate this method with desktop_selfie_test_mode_enabled
      false
    end

    private

    def validation_requirements_met?
      return false if document_type_mismatch?

      selfie_requirement_met? && mrz_requirement_met?
    end

    def document_type_mismatch?
      # Reject passports when feature is disabled but user submitted a passport
      return true if !IdentityConfig.store.doc_auth_passports_enabled &&
                     submitted_id_type == 'passport'

      # Reject when user requested passport flow but submitted a different document type
      return true if document_capture_session.passport_requested? &&
                     submitted_id_type != 'passport'

      # Reject when user didn't request passport flow but submitted a passport
      return true if !document_capture_session.passport_requested? &&
                     submitted_id_type == 'passport'

      false
    end

    def submitted_id_type
      stored_result.pii_from_doc&.dig(:id_doc_type)
    end

    def id_type_requested
      document_capture_session.passport_requested? ? 'passport' : 'state_id'
    end

    def track_document_issuing_state(user, state)
      return unless IdentityConfig.store.state_tracking_enabled && state
      doc_auth_log = DocAuthLog.find_by(user_id: user.id)
      return unless doc_auth_log
      doc_auth_log.state = state
      doc_auth_log.save!
    end
  end
end
