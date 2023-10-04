# frozen_string_literal: true

module Daf
  class Instruction < FieldChecker
    PAYMENT_PROCESS_ATT = 'Processus de paiement'
    EXEMPTED = 'Dispensé'
    WITH_PREPAYMENT = 'Avec prépaiement'
    WITHOUT_PREPAYMENT = 'Sans prépaiement'

    PAYMENT_MANAGEMENT_ATT = 'Gestion du paiement'
    AUTOMATIC = 'Automatique'
    MANUAL = 'Manuel'

    SEARCH_STEP = 'Recherche'
    CURRENT_STEP = 'Etape en cours'

    def version
      super + 6
    end

    def required_fields
      super + %i[paiement1 paiement2 sans_paiement1 sans_paiement2]
    end

    def authorized_fields
      super + %i[naf_sans_paiement1]
    end

    def initialize(params)
      super

      init_nafs
      init_tasks
    end

    def must_check?(md_dossier)
      md_dossier&.state == 'en_construction' || md_dossier&.state == 'en_instruction'
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      set_certification_date(demarche, dossier)
      set_current_step(demarche, dossier)

      payment1(demarche, dossier)
      payment2(demarche, dossier)
    end

    def exempted?
      fields('Administration')&.any? { |champ| champ.value.present? }
    end

    def ask_prepayment?
      company = field('Numéro Tahiti')&.etablissement
      company.blank? || company.naf.split(' | ').none? { |naf| @nafs_without_prepayment.include?(naf) }
    end

    def set_certification_date(demarche, dossier)
      certification_date_blank = annotation('DATE DE CERTIFICATION')&.value.blank?
      SetAnnotationValue.set_value(dossier, demarche.instructeur, 'DATE DE CERTIFICATION', DateTime.iso8601(dossier.date_depot)) if certification_date_blank
    end

    def set_current_step(demarche, dossier)
      current_step_blank = annotation(CURRENT_STEP)&.value.blank?
      SetAnnotationValue.set_value(dossier, demarche.instructeur, CURRENT_STEP, SEARCH_STEP) if current_step_blank
    end

    def set_amount(demarche, dossier, champ_declencheur, champ_montant)
      amount = field(champ_declencheur)&.value ? 500 : 0
      SetAnnotationValue.set_value(dossier, demarche.instructeur, champ_montant, amount)
    end

    private

    def init_tasks
      @tasks = {}
      create_tasks(:paiement1)
      create_tasks(:paiement2)
      create_tasks(:sans_paiement1)
      create_tasks(:sans_paiement2)
    end

    def check_presence(payment_management, section)
      raise "La section paiement automatique doit contenir des taches pour #{section}: #{@params[payment_management]}" if @tasks[payment_management].key?(section)
    end

    def init_nafs
      nafs_without_prepayment = @params[:naf_sans_paiement1] || []
      nafs_without_prepayment = nafs_without_prepayment.split(',') if nafs_without_prepayment.is_a?(String)
      @nafs_without_prepayment = Set.new(nafs_without_prepayment)
    end

    def create_tasks(payment_step)
      @tasks[payment_step] = InspectorTask.create_tasks(@params[payment_step])
    end

    def payment1(demarche, dossier)
      return unless dossier.state == 'en_construction'

      pp = payment_process
      Rails.logger.info("Payment 1: #{pp}")
      changed = SetAnnotationValue.set_value(dossier, demarche.instructeur, PAYMENT_PROCESS_ATT, pp)
      changed |= set_amounts(demarche, dossier)

      dossier = @dossier = DossierActions.on_dossier(dossier.number) if changed
      payment_section = pp == WITH_PREPAYMENT ? :paiement1 : :sans_paiement1
      process_tasks(demarche, dossier, @tasks[payment_section])
    end

    def payment_process
      if exempted?
        EXEMPTED
      else
        (ask_prepayment? ? WITH_PREPAYMENT : WITHOUT_PREPAYMENT)
      end
    end

    def payment2(demarche, dossier)
      return unless instruction?(dossier) && ready_to_deliver?

      payment_section = must_pay? ? :paiement2 : :sans_paiement2
      Rails.logger.info("Payment 2: #{payment_section}")
      process_tasks(demarche, dossier, @tasks[payment_section])
    end

    def set_amounts(demarche, dossier)
      commands = field('États demandés')&.values
      SetAnnotationValue.set_value(dossier, demarche.instructeur, 'Montant transcription', commands.include?('TRANSCRIPTIONS') ? 500 : 0) |
        SetAnnotationValue.set_value(dossier, demarche.instructeur, 'Montant inscription', commands.include?('INSCRIPTIONS') ? 500 : 0)
    end

    def process_tasks(demarche, dossier, tasks)
      tasks.each do |task|
        Rails.logger.info("Applying task #{task.class.name}")
        task.process(demarche, dossier) if task.valid?
        @updated_dossiers += task.updated_dossiers
        @dossiers_to_recheck += task.dossiers_to_recheck
        dossier = DossierActions.on_dossier(dossier.number) if task.dossier_updated?(dossier)
      end
    end

    def instruction?(dossier)
      dossier.state == 'en_instruction'
    end

    def ready_to_deliver?
      annotation('VISA RECEVEUR')&.string_value.present?
    end

    def must_pay?
      annotation(PAYMENT_PROCESS_ATT).value != EXEMPTED
    end
  end
end
