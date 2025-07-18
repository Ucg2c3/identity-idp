require 'rails_helper'

RSpec.describe Idv::DocPiiForm do
  include DocPiiHelper

  let(:user) { create(:user) }
  let(:pii) { nil }
  let(:subject) { Idv::DocPiiForm.new(pii: pii) }
  let(:first_name) { Faker::Name.first_name }
  let(:last_name) { Faker::Name.last_name }
  let(:address1) { Faker::Address.street_address }
  let(:zipcode) { Faker::Address.zip_code }
  let(:state) { Faker::Address.state_abbr }
  let(:valid_dob) { (Time.zone.today - (IdentityConfig.store.idv_min_age_years + 1).years).to_s }
  let(:valid_expiration) { Time.zone.today.to_s }
  let(:invalid_expiration) { (Time.zone.today - 1.day).to_s }
  let(:id_doc_type) { 'drivers_license' }
  let(:too_young_dob) do
    (Time.zone.today - (IdentityConfig.store.idv_min_age_years - 1).years).to_s
  end
  let(:mrz) do
    'P<UTOSAMPLE<<COMPANY<<<<<<<<<<<<<<<<<<<<<<<<ACU1234P<5UTO0003067F4003065<<<<<<<<<<<<<<02'
  end
  let(:good_state_id_pii) do
    {
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      dob: valid_dob,
      address1: Faker::Address.street_address,
      zipcode: Faker::Address.zip_code,
      state: Faker::Address.state_abbr,
      id_doc_type: id_doc_type,
      state_id_jurisdiction: 'AL',
      state_id_number: 'S59397998',
      state_id_issued: '2024-01-01',
      state_id_expiration: valid_expiration,
    }
  end
  let(:nil_id_doc_type_pii) { good_state_id_pii.merge(id_doc_type: nil) }
  let(:name_errors_pii) { good_state_id_pii.merge(first_name: nil, last_name: nil) }
  let(:name_and_dob_errors_pii) do
    good_state_id_pii.merge(
      first_name: nil,
      last_name: nil,
      dob: nil,
    )
  end
  let(:dob_min_age_error_pii) { good_state_id_pii.merge(dob: too_young_dob) }
  let(:state_id_expired_error_pii) do
    good_state_id_pii.merge(state_id_expiration: invalid_expiration)
  end
  let(:state_id_expiration_error_pii) { good_state_id_pii.merge(state_id_expiration: nil) }
  let(:non_string_zipcode_pii) { good_state_id_pii.merge(zipcode: 12345) }
  let(:nil_zipcode_pii) { good_state_id_pii.merge(zipcode: nil) }
  let(:state_error_pii) { good_state_id_pii.merge(state: 'YORK') }
  let(:jurisdiction_error_pii) { good_state_id_pii.merge(state_id_jurisdiction: 'XX') }
  let(:address1_error_pii) { good_state_id_pii.merge(address1: nil) }
  let(:nil_state_id_number_pii) { good_state_id_pii.merge(state_id_number: nil) }

  let(:good_passport_pii) do
    {
      first_name: Faker::Name.first_name,
      last_name: Faker::Name.last_name,
      dob: valid_dob,
      birth_place: 'WASHINGTON D.C.. U.S.A.',
      passport_issued: '2024-01-01',
      passport_expiration: '2099-01-01',
      id_doc_type: 'passport',
      issuing_country_code: 'USA',
      nationality_code: 'USA',
      mrz: mrz,
    }
  end
  let(:nil_birth_place_pii) { good_passport_pii.merge(birth_place: nil) }
  let(:passport_expired_error_pii) do
    good_passport_pii.merge(passport_expiration: invalid_expiration)
  end
  let(:nil_passport_issued_pii) { good_passport_pii.merge(passport_issued: nil) }
  let(:issuing_country_code_error_pii) { good_passport_pii.merge(issuing_country_code: 'XYZ') }
  let(:nationality_code_error_pii) { good_passport_pii.merge(nationality_code: 'XYZ') }
  let(:nil_mrz_pii) { good_passport_pii.merge(mrz: nil) }
  let(:passport_card_pii) { good_passport_pii.merge(id_doc_type: 'passport_card') }

  describe '#submit' do
    context 'when the form is valid' do
      let(:pii) { good_state_id_pii }

      it 'returns a successful form response' do
        result = subject.submit

        expect(result).to be_kind_of(FormResponse)
        expect(result.success?).to eq(true)
        expect(result.errors).to be_empty
        expect(result.extra).to eq(
          attention_with_barcode: false,
          id_doc_type: 'drivers_license',
          pii_like_keypaths: pii_like_keypaths_state_id,
          id_issued_status: 'present',
          id_expiration_status: 'present',
          passport_issued_status: 'missing',
          passport_expiration_status: 'missing',
        )
      end
    end

    context 'when the id_doc_type is not specified' do
      let(:pii) { nil_id_doc_type_pii }

      it 'returns a general no liveness error' do
        result = subject.submit

        expect(result).to be_kind_of(FormResponse)
        expect(result.success?).to eq(false)
        expect(result.errors[:no_document]).to eq [
          t('doc_auth.errors.general.no_liveness'),
        ]
      end
    end

    context 'when there is an error with both name fields' do
      let(:pii) { name_errors_pii }

      it 'returns a single name-specific pii error' do
        result = subject.submit

        expect(result).to be_kind_of(FormResponse)
        expect(result.success?).to eq(false)
        expect(result.errors[:name]).to eq [t('doc_auth.errors.alerts.full_name_check')]
        expect(result.extra).to eq(
          attention_with_barcode: false,
          id_doc_type: 'drivers_license',
          pii_like_keypaths: pii_like_keypaths_state_id,
          id_issued_status: 'present',
          id_expiration_status: 'present',
          passport_issued_status: 'missing',
          passport_expiration_status: 'missing',
        )
      end
    end

    context 'when there is an error with name fields and dob' do
      let(:pii) { name_and_dob_errors_pii }

      it 'returns a single generic pii error' do
        result = subject.submit

        expect(result).to be_kind_of(FormResponse)
        expect(result.success?).to eq(false)
        expect(result.errors.keys)
          .to contain_exactly(
            :name,
            :dob,
          )
        expect(result.extra).to eq(
          attention_with_barcode: false,
          id_doc_type: 'drivers_license',
          pii_like_keypaths: pii_like_keypaths_state_id,
          id_issued_status: 'present',
          id_expiration_status: 'present',
          passport_issued_status: 'missing',
          passport_expiration_status: 'missing',
        )
      end
    end

    context 'when there is an error with dob minimum age' do
      let(:pii) { dob_min_age_error_pii }

      it 'returns a single min age error' do
        result = subject.submit

        expect(result).to be_kind_of(FormResponse)
        expect(result.success?).to eq(false)
        expect(result.errors[:dob_min_age]).to eq [
          t('doc_auth.errors.pii.birth_date_min_age'),
        ]
        expect(result.extra).to eq(
          attention_with_barcode: false,
          id_doc_type: 'drivers_license',
          pii_like_keypaths: pii_like_keypaths_state_id,
          id_issued_status: 'present',
          id_expiration_status: 'present',
          passport_issued_status: 'missing',
          passport_expiration_status: 'missing',
        )
      end
    end

    context 'document is State ID' do
      context 'when the ID expiration is not present' do
        let(:pii) { state_id_expiration_error_pii }

        it 'the form is valid' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(true)
          expect(result.errors[:state_id_expiration]).to be_empty
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'drivers_license',
            pii_like_keypaths: pii_like_keypaths_state_id,
            id_issued_status: 'present',
            id_expiration_status: 'missing',
            passport_issued_status: 'missing',
            passport_expiration_status: 'missing',
          )
        end
      end

      context 'when the ID is expired' do
        let(:pii) { state_id_expired_error_pii }

        it 'returns a single state ID expiration error' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(false)
          expect(result.errors[:state_id_expiration]).to eq [
            t('doc_auth.errors.general.no_liveness'),
          ]
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'drivers_license',
            pii_like_keypaths: pii_like_keypaths_state_id,
            id_issued_status: 'present',
            id_expiration_status: 'present',
            passport_issued_status: 'missing',
            passport_expiration_status: 'missing',
          )
        end

        context 'expiration date is 2020-01-01' do # test 2020-01-01 fails outside socure test mode
          let(:pii) { state_id_expired_error_pii.merge(state_id_expiration: '2020-01-01') }
          it 'returns a single state ID expiration error' do
            result = subject.submit

            expect(result).to be_kind_of(FormResponse)
            expect(result.success?).to eq(false)
            expect(result.errors[:state_id_expiration]).to eq [
              t('doc_auth.errors.general.no_liveness'),
            ]
            expect(result.extra).to eq(
              attention_with_barcode: false,
              id_doc_type: 'drivers_license',
              pii_like_keypaths: pii_like_keypaths_state_id,
              id_issued_status: 'present',
              id_expiration_status: 'present',
              passport_issued_status: 'missing',
              passport_expiration_status: 'missing',
            )
          end
        end

        context 'when in socure_test_mode' do
          before do
            allow(IdentityConfig.store).to receive(:socure_docv_verification_data_test_mode)
              .and_return(true)
          end

          it 'returns a single state ID expiration error' do
            result = subject.submit

            expect(result).to be_kind_of(FormResponse)
            expect(result.success?).to eq(false)
            expect(result.errors[:state_id_expiration]).to eq [
              t('doc_auth.errors.general.no_liveness'),
            ]
            expect(result.extra).to eq(
              attention_with_barcode: false,
              id_doc_type: 'drivers_license',
              pii_like_keypaths: pii_like_keypaths_state_id,
              id_issued_status: 'present',
              id_expiration_status: 'present',
              passport_issued_status: 'missing',
              passport_expiration_status: 'missing',
            )
          end

          context 'expiration date is 2020-01-01' do
            let(:pii) { state_id_expired_error_pii.merge(state_id_expiration: '2020-01-01') }
            it 'returns a successful form response' do
              result = subject.submit

              expect(result).to be_kind_of(FormResponse)
              expect(result.success?).to eq(true)
              expect(result.errors).to be_empty
              expect(result.extra).to eq(
                attention_with_barcode: false,
                id_doc_type: 'drivers_license',
                pii_like_keypaths: pii_like_keypaths_state_id,
                id_issued_status: 'present',
                id_expiration_status: 'present',
                passport_issued_status: 'missing',
                passport_expiration_status: 'missing',
              )
            end
          end
        end
      end

      context 'when there is a non-string zipcode' do
        let(:pii) { non_string_zipcode_pii }

        it 'returns a single generic pii error' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(false)
          expect(result.errors[:zipcode]).to eq [
            t('doc_auth.errors.general.no_liveness'),
          ]
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'drivers_license',
            pii_like_keypaths: pii_like_keypaths_state_id,
            id_issued_status: 'present',
            id_expiration_status: 'present',
            passport_issued_status: 'missing',
            passport_expiration_status: 'missing',
          )
        end
      end

      context 'when there is a nil zipcode' do
        let(:pii) { nil_zipcode_pii }

        it 'returns a single generic pii error' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(false)
          expect(result.errors[:zipcode]).to eq [
            t('doc_auth.errors.general.no_liveness'),
          ]
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'drivers_license',
            pii_like_keypaths: pii_like_keypaths_state_id,
            id_issued_status: 'present',
            id_expiration_status: 'present',
            passport_issued_status: 'missing',
            passport_expiration_status: 'missing',
          )
        end
      end

      context 'when there was attention with barcode' do
        let(:subject) { Idv::DocPiiForm.new(pii: good_state_id_pii, attention_with_barcode: true) }

        it 'adds value as extra attribute' do
          result = subject.submit

          expect(result.extra[:attention_with_barcode]).to eq(true)
        end
      end

      context 'when there is no address1 information' do
        let(:subject) { Idv::DocPiiForm.new(pii: address1_error_pii) }

        it 'returns an error for not being able to read the address' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(false)
          expect(result.errors[:address1]).to eq [t('doc_auth.errors.alerts.address_check')]
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'drivers_license',
            pii_like_keypaths: pii_like_keypaths_state_id,
            id_issued_status: 'present',
            id_expiration_status: 'present',
            passport_issued_status: 'missing',
            passport_expiration_status: 'missing',
          )
        end
      end

      context 'when there is an invalid jurisdiction' do
        let(:subject) { Idv::DocPiiForm.new(pii: jurisdiction_error_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:jurisdiction])
            .to eq([I18n.t('doc_auth.errors.general.no_liveness')])
        end
      end

      context 'when there is an invalid state' do
        let(:subject) { Idv::DocPiiForm.new(pii: state_error_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:state]).to eq([I18n.t('doc_auth.errors.general.no_liveness')])
        end
      end
      context 'when the state_id_number is missing' do
        let(:subject) { Idv::DocPiiForm.new(pii: nil_state_id_number_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:state_id_number]).to eq(
            [I18n.t('doc_auth.errors.general.no_liveness')],
          )
        end
      end
    end

    context 'Document is Passport' do
      context 'when the passport form is valid' do
        let(:pii) { good_passport_pii }

        it 'returns a successful form response' do
          result = subject.submit

          expect(result).to be_kind_of(FormResponse)
          expect(result.success?).to eq(true)
          expect(result.errors).to be_empty
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'present',
            passport_expiration_status: 'present',
          )
        end
      end

      context 'when passport is expired' do
        let(:subject) { Idv::DocPiiForm.new(pii: passport_expired_error_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:passport_expiration]).to eq(
            [I18n.t('doc_auth.errors.general.no_liveness')],
          )
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'present',
            passport_expiration_status: 'present',
          )
        end
      end

      context 'when passport issued is nil' do
        let(:subject) { Idv::DocPiiForm.new(pii: nil_passport_issued_pii) }

        it 'passport_issued_status is missing' do
          result = subject.submit

          expect(result.success?).to eq(true)
          expect(result.errors).to be_empty
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'missing',
            passport_expiration_status: 'present',
          )
        end
      end

      context 'when there is an invalid issuing country code' do
        let(:subject) { Idv::DocPiiForm.new(pii: issuing_country_code_error_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:issuing_country_code]).to eq(
            [I18n.t('doc_auth.errors.general.no_liveness')],
          )
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'present',
            passport_expiration_status: 'present',
          )
        end
      end

      context 'mrz is nil' do
        let(:subject) { Idv::DocPiiForm.new(pii: nil_mrz_pii) }

        it 'responds with an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:mrz]).to eq(
            [I18n.t('doc_auth.errors.general.no_liveness')],
          )
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'present',
            passport_expiration_status: 'present',
          )
        end
      end

      context 'when the passport is a passport card' do
        let(:subject) { Idv::DocPiiForm.new(pii: passport_card_pii) }

        it 'returns an unsuccessful result' do
          result = subject.submit

          expect(result.success?).to eq(false)
          expect(result.errors[:id_doc_type]).to eq(
            [I18n.t('doc_auth.errors.general.no_liveness')],
          )
          expect(result.extra).to eq(
            attention_with_barcode: false,
            id_doc_type: 'passport_card',
            pii_like_keypaths: pii_like_keypaths_passport,
            id_issued_status: 'missing',
            id_expiration_status: 'missing',
            passport_issued_status: 'present',
            passport_expiration_status: 'present',
          )
        end
      end
    end
  end
end
