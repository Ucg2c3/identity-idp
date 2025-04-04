# frozen_string_literal: true

module SignUp
  class SelectEmailController < ApplicationController
    include RenderConditionConcern

    before_action :confirm_two_factor_authenticated
    before_action :verify_needs_completions_screen

    def show
      @sp_name = current_sp.friendly_name || sp.agency&.name
      @user_emails = user_emails
      @last_sign_in_email_address = last_email
      @select_email_form = build_select_email_form
      @can_add_email = EmailPolicy.new(current_user).can_add_email?
      analytics.sp_select_email_visited(needs_completion_screen_reason:)
    end

    def create
      @select_email_form = build_select_email_form

      result = @select_email_form.submit(form_params)

      analytics.sp_select_email_submitted(**result, needs_completion_screen_reason:)

      if result.success?
        user_session[:selected_email_id_for_linked_identity] = form_params[:selected_email_id]
        redirect_to sign_up_completed_path
      else
        flash[:error] = result.first_error_message
        redirect_to sign_up_select_email_path
      end
    end

    def user_emails
      @user_emails = current_user.confirmed_email_addresses
    end

    private

    def build_select_email_form
      SelectEmailForm.new(user: current_user)
    end

    def form_params
      params.fetch(:select_email_form, {}).permit(:selected_email_id)
    end

    def last_email
      if user_session[:selected_email_id_for_linked_identity]
        user_emails.find(user_session[:selected_email_id_for_linked_identity]).email
      else
        current_user.last_sign_in_email_address.email
      end
    end

    def verify_needs_completions_screen
      redirect_to account_url unless needs_completion_screen_reason
    end
  end
end
