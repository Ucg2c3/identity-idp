# frozen_string_literal: true

module Idv
  class ImageUploadsController < ApplicationController
    respond_to :json

    def create
      image_upload_form_response = image_upload_form.submit

      presenter = ImageUploadResponsePresenter.new(
        form_response: image_upload_form_response,
        url_options: url_options,
      )

      render json: presenter, status: presenter.status
    end

    private

    def image_upload_form
      @image_upload_form ||= Idv::ApiImageUploadForm.new(
        params,
        acuant_sdk_upgrade_ab_test_bucket: ab_test_bucket(:ACUANT_SDK),
        analytics:,
        attempts_api_tracker:,
        liveness_checking_required: resolved_authn_context_result.facial_match?,
        service_provider: current_sp,
        uuid_prefix: current_sp&.app_id,
      )
    end
  end
end
