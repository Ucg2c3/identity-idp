# frozen_string_literal: true

module AttemptsApi
  module TrackerEvents
    # @param [Boolean] success True if the email and password matched
    # A user has submitted an email address and password for authentication
    def email_and_password_auth(success:)
      track_event(
        'login-email-and-password-auth',
        success:,
      )
    end

    # @param [Boolean] success
    # A user has attempted to enroll the Backup Codes MFA method to their account
    def mfa_enroll_backup_code(success:)
      track_event(
        'mfa-enroll-backup-code',
        success:,
      )
    end

    # @param [Boolean] success
    # A user has attempted to enroll the TOTP MFA method to their account
    def mfa_enroll_totp(success:)
      track_event(
        'mfa-enroll-totp',
        success:,
      )
    end

    # Tracks when user submits registration password
    # @param [Boolean] success
    # @param [Hash<Symbol,Array<Symbol>>] failure_reason
    def user_registration_password_submitted(
      success:,
      failure_reason: nil
    )
      track_event(
        'user-registration-password-submitted',
        success:,
        failure_reason:,
      )
    end
  end
end
