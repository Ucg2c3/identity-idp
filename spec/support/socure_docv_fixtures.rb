require 'rails_helper'

module SocureDocvFixtures
  class << self
    def pass_json(reason_codes: nil, document_type: :license)
      raw = read_fixture_file_at_path(
        document_type == :passport ? 'passport_pass.json' : 'license_pass.json',
      )
      body = JSON.parse(raw)
      if reason_codes
        body['documentVerification']['reasonCodes'] = reason_codes
      end
      body.to_json
    end

    def fail_json(reason_codes:, document_type: :license)
      raw = read_fixture_file_at_path(
        document_type == :passport ? 'passport_pass.json' : 'license_pass.json',
      )
      body = JSON.parse(raw)

      body['documentVerification']['decision']['value'] = 'reject'
      body['documentVerification']['reasonCodes'] = reason_codes

      body.to_json
    end

    private

    def read_fixture_file_at_path(filepath)
      expanded_path = Rails.root.join(
        'spec',
        'fixtures',
        'socure_docv',
        filepath,
      )
      File.read(expanded_path)
    end
  end
end
