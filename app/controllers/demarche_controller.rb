# frozen_string_literal: true

class DemarcheController < ApplicationController
  before_action :authenticate_user!

  def verify
    InspectJob.run
    # @verification_service = VerificationService.new
    # @verification_service.check
    redirect_to configuration_path
  end

  def show
    @running = InspectJob.running?
    @configurations = configuration_list
    @configuration = current_configuration
    @dossiers = dossiers_for_current_configuration
  end

  def post_message
    dossier_number = params['dossier'].to_i
    @verification_service = VerificationService.new
    @verification_service.post_message(dossier_number)
    redirect_to configuration_path
  end

  private

  def current_configuration
    current = params[:configuration].presence || session[:configuration]
    if current.present? && @configurations.any? { |configuration, _count| configuration == current }
      session[:configuration] = current
    else
      session.delete(:configuration)
    end
    current || last_processed_configuration
  end

  def dossiers_for_current_configuration
    return [] unless @configuration.present?

    checks
      .where('demarches.configuration': @configuration)
      .includes(:messages)
      .order('checks.updated_at desc')
      .group_by(&:dossier)
  end

  def checks
    Check
      .joins(demarche: :instructeurs)
      .where(demarches_users: { user_id: current_user })
      .where(id: Message.select(:check_id))
  end

  def last_processed_configuration
    Check.order('updated_at desc').joins(:messages).first.demarche.configuration
  end

  def configuration_list
    checks
      .distinct
      .group('demarches.configuration')
      .count(:dossier)
  end
end
