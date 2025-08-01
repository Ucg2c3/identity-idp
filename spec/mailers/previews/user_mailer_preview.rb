class UserMailerPreview < ActionMailer::Preview
  def email_confirmation_instructions
    UserMailer.with(user: user, email_address: email_address_record)
      .email_confirmation_instructions(
        SecureRandom.hex,
        request_id: SecureRandom.uuid,
      )
  end

  def signup_with_your_email
    UserMailer.with(user: user, email_address: email_address_record)
      .signup_with_your_email(request_id: SecureRandom.uuid)
  end

  def reset_password_instructions
    UserMailer.with(user: user, email_address: email_address_record).reset_password_instructions(
      token: SecureRandom.hex, request_id: SecureRandom.hex,
    )
  end

  def reset_password_instructions_with_pending_gpo_letter
    UserMailer.with(
      user: user_with_pending_gpo_letter, email_address: email_address_record,
    ).reset_password_instructions(
      token: SecureRandom.hex, request_id: SecureRandom.hex,
    )
  end

  def password_changed
    UserMailer.with(user: user, email_address: email_address_record)
      .password_changed(disavowal_token: SecureRandom.hex)
  end

  def phone_added
    UserMailer.with(user: user, email_address: email_address_record)
      .phone_added(disavowal_token: SecureRandom.hex)
  end

  def personal_key_sign_in
    UserMailer.with(user: user, email_address: email_address_record)
      .personal_key_sign_in(disavowal_token: SecureRandom.hex)
  end

  def new_device_sign_in_after_2fa
    UserMailer.with(user: user, email_address: email_address_record).new_device_sign_in_after_2fa(
      events: [
        unsaveable(
          Event.new(
            event_type: :sign_in_before_2fa,
            created_at: Time.zone.now - 2.minutes,
            user:,
            device: user.devices.first,
          ),
        ),
        unsaveable(
          Event.new(
            event_type: :sign_in_after_2fa,
            created_at: Time.zone.now,
            user:,
            device: user.devices.first,
          ),
        ),
      ],
      disavowal_token: SecureRandom.hex,
    )
  end

  def new_device_sign_in_before_2fa
    UserMailer.with(user: user, email_address: email_address_record).new_device_sign_in_before_2fa(
      events: [
        unsaveable(
          Event.new(
            event_type: :sign_in_before_2fa,
            created_at: Time.zone.now - 2.minutes,
            user:,
            device: user.devices.first,
          ),
        ),
        *Array.new((params['failed_times'] || 1).to_i) do
          unsaveable(
            Event.new(
              event_type: :sign_in_unsuccessful_2fa,
              created_at: Time.zone.now,
              user:,
              device: user.devices.first,
            ),
          )
        end,
      ],
      disavowal_token: SecureRandom.hex,
    )
  end

  def personal_key_regenerated
    UserMailer.with(user: user, email_address: email_address_record).personal_key_regenerated
  end

  def account_reset_request
    UserMailer.with(user: user, email_address: email_address_record).account_reset_request(
      user.build_account_reset_request,
    )
  end

  def account_reset_granted
    UserMailer.with(user: user, email_address: email_address_record).account_reset_granted(
      user.build_account_reset_request,
    )
  end

  def account_reset_complete
    UserMailer.with(user: user, email_address: email_address_record).account_reset_complete
  end

  def account_delete_completed
    UserMailer.with(user: user, email_address: email_address_record).account_delete_completed
  end

  def account_reset_cancel
    UserMailer.with(user: user, email_address: email_address_record).account_reset_cancel
  end

  def please_reset_password
    UserMailer.with(user: user, email_address: email_address_record).please_reset_password
  end

  def verify_by_mail_letter_requested
    service_provider = unsaveable(
      ServiceProvider.new(
        friendly_name: 'Sample App SP',
        return_to_sp_url: 'https://example.com',
      ),
    )
    profile = Profile.new(initiating_service_provider: service_provider)
    user.instance_variable_set(:@pending_profile, profile)
    UserMailer.with(user: user, email_address: email_address_record).verify_by_mail_letter_requested
  end

  def add_email
    UserMailer.with(user: user, email_address: email_address_record)
      .add_email(token: SecureRandom.hex, request_id: nil)
  end

  def email_added
    UserMailer.with(user: user, email_address: email_address_record).email_added
  end

  def email_deleted
    UserMailer.with(user: user, email_address: email_address_record).email_deleted
  end

  def add_email_associated_with_another_account
    UserMailer.with(user: user, email_address: email_address_record)
      .add_email_associated_with_another_account
  end

  def account_verified
    service_provider = unsaveable(
      ServiceProvider.new(
        friendly_name: 'Example Sinatra App',
        return_to_sp_url: 'http://example.com',
      ),
    )
    UserMailer.with(user: user, email_address: email_address_record).account_verified(
      profile: unsaveable(
        Profile.new(
          user: user,
          initiating_service_provider: service_provider,
          verified_at: Time.zone.now,
        ),
      ),
    )
  end

  def in_person_completion_survey
    UserMailer.with(user: user, email_address: email_address_record).in_person_completion_survey
  end

  def in_person_deadline_passed
    UserMailer.with(user: user, email_address: email_address_record).in_person_deadline_passed(
      enrollment: in_person_enrollment_id_ipp,
      visited_location_name: in_person_visited_location_name,
    )
  end

  def in_person_ready_to_verify
    UserMailer.with(user: user, email_address: email_address_record).in_person_ready_to_verify(
      enrollment: in_person_enrollment_id_ipp,
    )
  end

  def in_person_ready_to_verify_skipped_location
    UserMailer.with(user: user, email_address: email_address_record).in_person_ready_to_verify(
      enrollment: in_person_enrollment_id_ipp_skipped_location,
    )
  end

  def in_person_ready_to_verify_passport
    UserMailer.with(user: user, email_address: email_address_record).in_person_ready_to_verify(
      enrollment: in_person_enrollment_passport,
    )
  end

  def in_person_ready_to_verify_enhanced_ipp_enabled
    UserMailer.with(user: user, email_address: email_address_record).in_person_ready_to_verify(
      enrollment: in_person_enrollment_enhanced_ipp,
    )
  end

  def in_person_ready_to_verify_reminder
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).in_person_ready_to_verify_reminder(
      enrollment: in_person_enrollment_id_ipp,
    )
  end

  def in_person_ready_to_verify_reminder_skipped_location
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).in_person_ready_to_verify_reminder(
      enrollment: in_person_enrollment_id_ipp_skipped_location,
    )
  end

  def in_person_ready_to_verify_reminder_passport
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).in_person_ready_to_verify_reminder(
      enrollment: in_person_enrollment_passport,
    )
  end

  def dupe_profile_created
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).dupe_profile_created(
      agency_name: 'Sample APP',
    )
  end

  def dupe_profile_sign_in_attempted
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).dupe_profile_sign_in_attempted(
      agency_name: 'Sample APP',
    )
  end

  def dupe_profile_account_review_complete_success
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).dupe_profile_account_review_complete_success(
      agency_name: 'Sample APP',
    )
  end

  def dupe_profile_account_review_complete_unable
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).dupe_profile_account_review_complete_unable(
      agency_name: 'Sample APP',
    )
  end

  def dupe_profile_account_review_complete_locked
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).dupe_profile_account_review_complete_locked(
      agency_name: 'Sample APP',
    )
  end

  def in_person_ready_to_verify_reminder_enhanced_ipp_enabled
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).in_person_ready_to_verify_reminder(
      enrollment: in_person_enrollment_enhanced_ipp,
    )
  end

  def in_person_verified
    UserMailer.with(user: user, email_address: email_address_record).in_person_verified(
      enrollment: in_person_enrollment_id_ipp,
      visited_location_name: in_person_visited_location_name,
    )
  end

  def in_person_failed
    UserMailer.with(user: user, email_address: email_address_record).in_person_failed(
      enrollment: in_person_enrollment_id_ipp,
      visited_location_name: in_person_visited_location_name,
    )
  end

  # To view this email, set the below in application.yml
  # in_person_passports_enabled: true
  # doc_auth_passports_enabled: true
  def in_person_failed_passports_enabled
    UserMailer.with(user: user, email_address: email_address_record).in_person_failed(
      enrollment: in_person_enrollment_id_ipp,
      visited_location_name: in_person_visited_location_name,
    )
  end

  def in_person_failed_fraud
    UserMailer.with(user: user, email_address: email_address_record).in_person_failed_fraud(
      enrollment: in_person_enrollment_id_ipp,
      visited_location_name: in_person_visited_location_name,
    )
  end

  def idv_please_call
    UserMailer.with(user: user, email_address: email_address_record).idv_please_call
  end

  def account_rejected
    UserMailer.with(user: user, email_address: email_address_record).account_rejected
  end

  def suspended_create_account
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).suspended_create_account
  end

  def suspended_reset_password
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).suspended_reset_password
  end

  def verify_by_mail_reminder
    UserMailer.with(
      user: user_with_pending_gpo_letter,
      email_address: email_address_record,
    ).verify_by_mail_reminder
  end

  def suspension_confirmed
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).suspension_confirmed
  end

  def account_reinstated
    UserMailer.with(
      user: user,
      email_address: email_address_record,
    ).account_reinstated
  end

  private

  def user
    @user ||= unsaveable(
      User.new(
        email_addresses: [email_address_record],
        devices: [
          unsaveable(
            Device.new(
              user_agent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/51.0.2704.103 Safari/537.36', # rubocop:disable Layout/LineLength
              last_ip: '8.8.8.8',
            ),
          ),
        ],
        email_language: params[:locale],
      ),
    )
  end

  def user_with_pending_gpo_letter
    raw_user = user
    gpo_pending_profile = unsaveable(
      Profile.new(
        user: raw_user,
        active: false,
        gpo_verification_pending_at: Time.zone.now,
      ),
    )
    raw_user.send(:instance_variable_set, :@pending_profile, gpo_pending_profile)
    raw_user
  end

  def email_address
    'email@example.com'
  end

  def email_address_record
    unsaveable(EmailAddress.new(email: email_address))
  end

  def in_person_visited_location_name
    'ACQUAINTANCESHIP'
  end

  def in_person_enrollment_id_ipp_skipped_location
    unsaveable(
      InPersonEnrollment.new(
        user: user,
        profile: unsaveable(Profile.new(user: user)),
        enrollment_code: '2048702198804358',
        created_at: Time.zone.now - 2.hours,
        service_provider: ServiceProvider.new(
          friendly_name: 'Test Service Provider',
          issuer: SecureRandom.uuid,
          logo: 'gsa.png',
        ),
        status_updated_at: Time.zone.now - 1.hour,
        current_address_matches_id: params['current_address_matches_id'] == 'true',
        selected_location_details: nil,
        sponsor_id: IdentityConfig.store.usps_ipp_sponsor_id,
        document_type: InPersonEnrollment::DOCUMENT_TYPE_STATE_ID,
      ),
    )
  end

  def in_person_enrollment_id_ipp
    unsaveable(
      InPersonEnrollment.new(
        user: user,
        profile: unsaveable(Profile.new(user: user)),
        enrollment_code: '2048702198804358',
        created_at: Time.zone.now - 2.hours,
        service_provider: ServiceProvider.new(
          friendly_name: 'Test Service Provider',
          issuer: SecureRandom.uuid,
          logo: 'gsa.png',
        ),
        status_updated_at: Time.zone.now - 1.hour,
        current_address_matches_id: params['current_address_matches_id'] == 'true',
        selected_location_details: {
          'name' => 'BALTIMORE',
          'street_address' => '900 E FAYETTE ST RM 118',
          'formatted_city_state_zip' => 'BALTIMORE, MD 21233-9715',
          'phone' => '555-123-6409',
          'weekday_hours' => '8:30 AM - 4:30 PM',
          'saturday_hours' => '9:00 AM - 12:00 PM',
          'sunday_hours' => 'Closed',
        },
        sponsor_id: IdentityConfig.store.usps_ipp_sponsor_id,
        document_type: InPersonEnrollment::DOCUMENT_TYPE_STATE_ID,
      ),
    )
  end

  def in_person_enrollment_passport
    unsaveable(
      InPersonEnrollment.new(
        user: user,
        profile: unsaveable(Profile.new(user: user)),
        enrollment_code: '2048702198804358',
        created_at: Time.zone.now - 2.hours,
        service_provider: ServiceProvider.new(
          friendly_name: 'Test Service Provider',
          issuer: SecureRandom.uuid,
          logo: '18f.svg',
        ),
        status_updated_at: Time.zone.now - 1.hour,
        current_address_matches_id: params['current_address_matches_id'] == 'true',
        selected_location_details: {
          'name' => 'BALTIMORE',
          'street_address' => '900 E FAYETTE ST RM 118',
          'formatted_city_state_zip' => 'BALTIMORE, MD 21233-9715',
          'phone' => '555-123-6409',
          'weekday_hours' => '8:30 AM - 4:30 PM',
          'saturday_hours' => '9:00 AM - 12:00 PM',
          'sunday_hours' => 'Closed',
        },
        sponsor_id: IdentityConfig.store.usps_ipp_sponsor_id,
        document_type: InPersonEnrollment::DOCUMENT_TYPE_PASSPORT_BOOK,
      ),
    )
  end

  def in_person_enrollment_enhanced_ipp
    unsaveable(
      InPersonEnrollment.new(
        user: user,
        profile: unsaveable(Profile.new(user: user)),
        enrollment_code: '2048702198804358',
        created_at: Time.zone.now - 2.hours,
        service_provider: ServiceProvider.new(
          friendly_name: 'Test Service Provider',
          issuer: SecureRandom.uuid,
          logo: '18f.svg',
        ),
        status_updated_at: Time.zone.now - 1.hour,
        current_address_matches_id: params['current_address_matches_id'] == 'true',
        selected_location_details: {
          'name' => 'BALTIMORE',
          'street_address' => '900 E FAYETTE ST RM 118',
          'formatted_city_state_zip' => 'BALTIMORE, MD 21233-9715',
          'phone' => '555-123-6409',
          'weekday_hours' => '8:30 AM - 4:30 PM',
          'saturday_hours' => '9:00 AM - 12:00 PM',
          'sunday_hours' => 'Closed',
        },
        sponsor_id: IdentityConfig.store.usps_eipp_sponsor_id,
        document_type: 'state_id',
      ),
    )
  end

  # Remove #save and #save! to make sure we can't write these made-up records
  def unsaveable(record)
    class << record
      def save
        raise "don't save me!"
      end

      def save!
        raise "don't save me!"
      end
    end

    record
  end
end
