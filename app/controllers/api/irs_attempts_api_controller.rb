##
# This controller implements the Poll-based delivery method for Security Event
# Tokens as described RFC 8936
#
# ref: https://datatracker.ietf.org/doc/html/rfc8936
#
module Api
  class IrsAttemptsApiController < ApplicationController
    include RenderConditionConcern

    check_or_render_not_found -> { IdentityConfig.store.irs_attempt_api_enabled }

    skip_before_action :verify_authenticity_token
    before_action :authenticate_client
    prepend_before_action :skip_session_load
    prepend_before_action :skip_session_expiration

    respond_to :json

    def create
      if timestamp
        result = encrypted_security_event_log_result

        headers['X-Payload-Key'] = Base64.strict_encode64(result.encrypted_key)
        headers['X-Payload-IV'] = Base64.strict_encode64(result.iv)

        send_data result.encrypted_data,
                  disposition: "filename=#{result.filename}"
      else
        render json: { status: :unprocessable_entity, description: 'Invalid timestamp parameter' },
               status: :unprocessable_entity
      end
      analytics.irs_attempts_api_events(**analytics_properties(authenticated: true))
    end

    private

    def authenticate_client
      bearer, csp_id, token = request.authorization&.split(' ', 3)
      if bearer != 'Bearer' || !valid_auth_tokens.include?(token) ||
         csp_id != IdentityConfig.store.irs_attempt_api_csp_id
        analytics.irs_attempts_api_events(**analytics_properties(authenticated: false))
        render json: { status: 401, description: 'Unauthorized' }, status: :unauthorized
      end
    end

    # @return [Array<String>] JWE strings
    def security_event_tokens
      return [] unless timestamp

      events = redis_client.read_events(timestamp: timestamp)
      events.values
    end

    def encrypted_security_event_log_result
      IrsAttemptsApi::EnvelopeEncryptor.encrypt(
        data: security_event_tokens.join("\r\n"),
        timestamp: timestamp,
        public_key_str: IdentityConfig.store.irs_attempt_api_public_key,
      )
    end

    def redis_client
      @redis_client ||= IrsAttemptsApi::RedisClient.new
    end

    def valid_auth_tokens
      IdentityConfig.store.irs_attempt_api_auth_tokens
    end

    def analytics_properties(authenticated:)
      {
        rendered_event_count: security_event_tokens.count,
        timestamp: timestamp&.iso8601,
        authenticated: authenticated,
        success: authenticated && timestamp.present?,
      }
    end

    def timestamp
      timestamp_param = params.permit(:timestamp)[:timestamp]
      return nil if timestamp_param.nil?

      date_fmt = timestamp_param.include?('.') ? '%Y-%m-%dT%H:%M:%S.%N%z' : '%Y-%m-%dT%H:%M:%S%z'

      Time.strptime(timestamp_param, date_fmt)
    rescue ArgumentError
      nil
    end
  end
end
