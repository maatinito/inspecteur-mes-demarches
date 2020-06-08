# frozen_string_literal: true

class DieseController < ApplicationController
  def check
    @verification_service = VerificationService.new
    @verification_service.check
    redirect_to diese_report_path
  end

  def report
    @checked_dossiers = Message.includes(:check).joins(:check).order("checks.checked_at DESC").group_by { |m| m.check }
  end
end
