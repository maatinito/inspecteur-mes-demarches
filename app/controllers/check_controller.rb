# frozen_string_literal: true

class CheckController < ApplicationController
  def verify
    InspectJob.run
    # @verification_service = VerificationService.new
    # @verification_service.check
    redirect_to check_report_path
  end

  def report
    # nested hash table  { demarche => dossier => check } unsorted
    @checked_dossiers = Check.order('checks.checked_at DESC').includes(:messages).includes(:demarche)
                             .each_with_object({}) do |c, h|
      h.update(c.demarche => { c.dossier => [c] }) do |_, h1, h2|
        h1.update(h2) do |_, l1, l2|
          l1 + l2
        end
      end
    end
    @running = InspectJob.running?
  end

  def post_message
    dossier_number = params['dossier'].to_i
    @verification_service = VerificationService.new
    @verification_service.post_message(dossier_number)
    redirect_to check_report_path
  end
end
