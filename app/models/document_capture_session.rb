# frozen_string_literal: true

class DocumentCaptureSession < ApplicationRecord
  include NonNullUuid
  include ApplicationHelper

  belongs_to :user

  PASSPORT_STATUSES = [
    'allowed',
    'not_requested',
    'requested',
  ].freeze

  validates :passport_status, inclusion: { in: PASSPORT_STATUSES }, allow_nil: true

  def load_result
    return nil unless result_id.present?
    EncryptedRedisStructStorage.load(result_id, type: DocumentCaptureSessionResult)
  end

  # @param doc_auth_response [DocAuth::Response]
  # @param mrz_status [Symbol, nil] MRZ validation status for passport documents
  def store_result_from_response(doc_auth_response, mrz_response: nil)
    session_result = load_result || DocumentCaptureSessionResult.new(
      id: generate_result_id,
    )
    session_result.success = doc_auth_response.success?
    session_result.pii = doc_auth_response.pii_from_doc.to_h
    session_result.captured_at = Time.zone.now
    session_result.attention_with_barcode = doc_auth_response.attention_with_barcode?
    session_result.doc_auth_success = doc_auth_response.doc_auth_success?
    session_result.selfie_status = doc_auth_response.selfie_status
    session_result.errors = doc_auth_response.errors
    session_result.mrz_status = determine_mrz_status(mrz_response)

    EncryptedRedisStructStorage.store(
      session_result,
      expires_in: IdentityConfig.store.doc_capture_request_valid_for_minutes.minutes.in_seconds,
    )
    self.ocr_confirmation_pending = doc_auth_response.attention_with_barcode?
    save!
  end

  def store_failed_auth_data(front_image_fingerprint:, back_image_fingerprint:,
                             passport_image_fingerprint:, selfie_image_fingerprint:,
                             doc_auth_success:, selfie_status:,
                             errors: nil, mrz_status: :not_processed)
    session_result = load_result || DocumentCaptureSessionResult.new(
      id: generate_result_id,
    )
    session_result.success = false
    session_result.captured_at = Time.zone.now
    session_result.doc_auth_success = doc_auth_success
    session_result.selfie_status = selfie_status

    session_result.add_failed_front_image!(front_image_fingerprint)
    session_result.add_failed_back_image!(back_image_fingerprint)
    session_result.add_failed_passport_image!(passport_image_fingerprint)
    session_result.add_failed_selfie_image!(selfie_image_fingerprint) if selfie_status == :fail

    session_result.errors = errors
    session_result.mrz_status = mrz_status

    EncryptedRedisStructStorage.store(
      session_result,
      expires_in: IdentityConfig.store.doc_capture_request_valid_for_minutes.minutes.in_seconds,
    )
    save!
  end

  def load_proofing_result
    EncryptedRedisStructStorage.load(result_id, type: ProofingSessionAsyncResult)
  end

  def create_proofing_session
    EncryptedRedisStructStorage.store(
      ProofingSessionAsyncResult.new(
        id: generate_result_id,
        status: ProofingSessionAsyncResult::IN_PROGRESS,
        result: nil,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
    save!
  end

  def store_proofing_result(proofing_result)
    EncryptedRedisStructStorage.store(
      ProofingSessionAsyncResult.new(
        id: result_id,
        result: proofing_result,
        status: ProofingSessionAsyncResult::DONE,
      ),
      expires_in: IdentityConfig.store.async_wait_timeout_seconds,
    )
  end

  def expired?
    return true unless requested_at
    (requested_at + IdentityConfig.store.doc_capture_request_valid_for_minutes.minutes) <
      Time.zone.now
  end

  def confirm_ocr
    return unless self.ocr_confirmation_pending

    update!(ocr_confirmation_pending: false)
  end

  def passport_allowed?
    PASSPORT_STATUSES.include? passport_status
  end

  def passport_requested?
    passport_status == 'requested'
  end

  private

  def generate_result_id
    self.result_id = SecureRandom.uuid
  end

  def determine_mrz_status(mrz_response)
    return :not_processed unless mrz_response

    mrz_response.success? ? :pass : :failed
  end
end
