# frozen_string_literal: true

class UserPivCacLoginForm
  include ActiveModel::Model
  include PivCacFormHelpers

  attr_accessor :x509_dn_uuid, :x509_dn, :x509_issuer, :token, :error_type, :nonce, :user, :key_id

  validates :token, presence: true
  validates :nonce, presence: true

  def initialize(token:, nonce:, piv_cac_required: false)
    @token = token
    @nonce = nonce
    @piv_cac_required = piv_cac_required
  end

  def submit
    success = valid? && valid_submission?

    response_hash = { success:, errors: }
    response_hash[:extra] = { key_id: }
    FormResponse.new(**response_hash)
  end

  private

  def valid_submission?
    valid_token? &&
      user_found
  end

  def user_found
    maybe_user = PivCacConfiguration.find_by(x509_dn_uuid: x509_dn_uuid)&.user
    if maybe_user.present?
      self.user = maybe_user
      true
    else
      self.error_type = 'user.not_found'
      errors.add(
        :user, I18n.t('headings.piv_cac_setup.already_associated'),
        type: :not_found
      )
      false
    end
  end
end
