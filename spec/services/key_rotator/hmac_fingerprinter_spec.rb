require 'rails_helper'

describe KeyRotator::HmacFingerprinter do
  describe '#rotate' do
    let(:enable_compound_pii_fingerprint?) { true }
    let(:pii_hash) do
      {
        first_name: 'Tony',
        last_name: 'Tiger',
        dob: '1980-12-31',
        zipcode: '20001',
      }
    end

    before do
      allow(FeatureManagement).
        to receive(:enable_compound_pii_fingerprint?).
        and_return(enable_compound_pii_fingerprint?)
    end

    it 'changes email and ssn fingerprints' do
      rotator = described_class.new
      profile = create(:profile, :active, :verified, pii: pii_hash)
      user = profile.user
      pii_attributes = profile.decrypt_pii(user.password)

      old_ssn_signature = profile.ssn_signature
      old_compound_signature = profile.name_zip_birth_year_signature
      old_email_fingerprint = user.email_fingerprint

      rotate_hmac_key

      rotator.rotate(user: user, pii_attributes: pii_attributes)

      expect(user.active_profile.ssn_signature).to_not eq old_ssn_signature
      expect(user.active_profile.name_zip_birth_year_signature).to_not eq old_compound_signature
      expect(user.email_fingerprint).to_not eq old_email_fingerprint
    end

    context 'compound PII fingerprinting is disabled' do
      let(:enable_compound_pii_fingerprint?) { false }

      it 'does not update the compound PII fingerprint' do
        rotator = described_class.new
        profile = create(:profile, :active, :verified, pii: pii_hash)

        user = profile.user
        pii_attributes = profile.decrypt_pii(user.password)

        expect do
          rotate_hmac_key
          rotator.rotate(user: user, pii_attributes: pii_attributes)
        end.to_not change { profile.reload.name_zip_birth_year_signature }.
          from(nil)
      end
    end

    it 'does not change the `updated_at` timestamp' do
      profile = create(:profile, :active, :verified, pii: { ssn: '1234' })
      user = profile.user
      pii_attributes = profile.decrypt_pii(user.password)

      old_updated_timestamp = user.updated_at

      rotate_hmac_key
      rotator = described_class.new
      rotator.rotate(user: user, pii_attributes: pii_attributes)

      expect(user.updated_at).to eq old_updated_timestamp
    end

    it 'changes email fingerprint if no active profile' do
      rotator = described_class.new
      user = create(:user)
      old_email_fingerprint = user.email_fingerprint

      rotate_hmac_key

      rotator.rotate(user: user)

      expect(user.email_fingerprint).to_not eq old_email_fingerprint
    end
  end
end
