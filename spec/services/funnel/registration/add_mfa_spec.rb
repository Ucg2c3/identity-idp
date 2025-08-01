require 'rails_helper'

RSpec.describe Funnel::Registration::AddMfa do
  let(:analytics) { FakeAnalytics.new }
  subject { described_class }
  let(:user) { create(:user) }

  let(:user_id) { user.id }
  let(:funnel) { RegistrationLog.first }

  let(:threatmetrix_attrs) do
    {
      user_id: user_id,
      request_ip: Faker::Internet.ip_v4_address,
      threatmetrix_session_id: SecureRandom.uuid,
      email: user.email,
      in_ab_test_bucket: true,
      in_account_creation_flow: true,
    }
  end

  it 'shows user is not fully registered with no mfa' do
    expect(funnel&.registered_at).to_not be_present
  end

  it 'shows user is fully registered after adding an mfa' do
    subject.call(user_id, 'phone', analytics, threatmetrix_attrs)

    expect(funnel.registered_at).to be_present
  end

  context 'with threat metrix for account creation enabled' do
    before do
      allow(FeatureManagement)
        .to receive(:account_creation_device_profiling_collecting_enabled?)
        .and_return(:collect_only)

      allow(IdentityConfig).to receive(:account_creation_tmx_processed_percent)
        .and_return(100)
    end
    it 'triggers threatmetrix job call' do
      expect(AccountCreationThreatMetrixJob).to receive(:perform_now)
      subject.call(user_id, 'phone', analytics, threatmetrix_attrs)
    end
  end
end
