# frozen_string_literal: true

class DieseController < ApplicationController
  def check
    @verification_service = VerificationService.new
    @verification_service.check
    redirect_to diese_report_path
  end

  def report
    @checked_dossiers = Message.order('checks.checked_at desc').includes(:check).joins(:check).group_by { |m| m.check.dossier }
  end

  def post_message
    dossier_number = params['dossier'].to_i
    @verification_service = VerificationService.new
    @verification_service.post_message(dossier_number)
    redirect_to diese_report_path
  end
end
