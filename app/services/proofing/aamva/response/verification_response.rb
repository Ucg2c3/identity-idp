# frozen_string_literal: true

require 'rexml/document'
require 'rexml/xpath'

module Proofing
  module Aamva
    module Response
      class VerificationResponse
        VERIFICATION_ATTRIBUTES_MAP = {
          'DriverLicenseExpirationDateMatchIndicator' => :state_id_expiration,
          'DriverLicenseIssueDateMatchIndicator' => :state_id_issued,
          'DriverLicenseNumberMatchIndicator' => :state_id_number,
          'DocumentCategoryMatchIndicator' => :id_doc_type,
          'PersonBirthDateMatchIndicator' => :dob,
          'PersonHeightMatchIndicator' => :height,
          'PersonSexCodeMatchIndicator' => :sex,
          'PersonWeightMatchIndicator' => :weight,
          'PersonEyeColorMatchIndicator' => :eye_color,
          'PersonLastNameExactMatchIndicator' => :last_name,
          'PersonFirstNameExactMatchIndicator' => :first_name,
          'PersonMiddleNameExactMatchIndicator' => :middle_name,
          'PersonNameSuffixMatchIndicator' => :name_suffix,
          'AddressLine1MatchIndicator' => :address1,
          'AddressLine2MatchIndicator' => :address2,
          'AddressCityMatchIndicator' => :city,
          'AddressStateCodeMatchIndicator' => :state,
          'AddressZIP5MatchIndicator' => :zipcode,
        }.freeze

        attr_reader :verification_results, :transaction_locator_id

        def initialize(http_response)
          @missing_attributes = []
          @verification_results = {}
          @http_response = http_response
          @errors = []

          handle_http_error
          handle_soap_error

          parse_response

          return if @errors.empty?

          error_message = @errors.join('; ')
          raise VerificationError.new(error_message)
        end

        private

        attr_reader :http_response, :missing_attributes

        def handle_http_error
          status = http_response.status
          @errors.push("Unexpected status code in response: #{status}") if status != 200
        end

        def handle_missing_attribute(attribute_name)
          missing_attributes.push(attribute_name)
          verification_results[attribute_name] = nil
        end

        def handle_soap_error
          error_handler = SoapErrorHandler.new(http_response)
          return unless error_handler.error_present?

          @errors.push(error_handler.error_message)
        end

        def node_for_match_indicator(match_indicator_name)
          REXML::XPath.first(rexml_document, "//#{match_indicator_name}")
        rescue REXML::ParseException
          nil
        end

        def parse_response
          VERIFICATION_ATTRIBUTES_MAP.each_pair do |match_indicator_name, attribute_name|
            attribute_node = node_for_match_indicator(match_indicator_name)
            if attribute_node.nil?
              handle_missing_attribute(attribute_name)
            elsif attribute_node.text == 'true'
              verification_results[attribute_name] = true
            else
              verification_results[attribute_name] = false
            end
          end

          @transaction_locator_id = (
            node_for_match_indicator('TransactionLocatorId') ||
            node_for_match_indicator('TransactionLocatorID')
          )&.text&.strip
        end

        def rexml_document
          return @rexml_document ||= REXML::Document.new(http_response.body)
        end
      end
    end
  end
end
