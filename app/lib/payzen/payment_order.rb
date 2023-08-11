# frozen_string_literal: true

module Payzen
  class PaymentOrder < FieldChecker
    include Payzen::StringTemplate
    attr_reader :when_asked, :when_paid, :when_expired

    def version
      super + 2
    end

    def required_fields
      %i[reference champ_ordre_de_paiement message boutique cle_de_test cle]
    end

    def authorized_fields
      %i[etat_du_dossier champ_montant montant quand_payé quand_demandé quand_expiré quand_gratuit mode_test champ_telephone sms]
    end

    def initialize(params)
      # backward compatibility where old scheduled task payment_order has no 'boutique, cle and cle_de_test' params
      params['boutique'] = ENV.fetch('PAYZEN_PROD_LOGIN', nil) unless params.key?('boutique')
      params['cle_de_test'] = ENV.fetch('PAYZEN_TEST_PASSWORD', nil) unless params.key?('cle_de_test')
      params['cle'] = ENV.fetch('PAYZEN_PROD_PASSWORD', nil) unless params.key?('cle')

      super
      @when_asked = InspectorTask.create_tasks(@params[:quand_demandé])
      @when_paid = InspectorTask.create_tasks(@params[:quand_payé])
      @when_expired = InspectorTask.create_tasks(@params[:quand_expiré])
      @when_free = InspectorTask.create_tasks(@params[:quand_gratuit])

      @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])

      @test_mode = Set['oui', 'true', '1', 1].include?(@params[:mode_test]&.downcase)
      password = @params[@test_mode ? :cle_de_test : :cle]
      store = @params[:boutique]
      @api = Payzen::API.new(store, password)

      @reference_prefix = @params[:reference]
      @reference_prefix = 'md' if @reference_prefix.blank?
      check_errors
    end

    def check_errors
      @errors << "l'attribut sms est obligatoire quand le champ 'champ_telephone' est donné." if @params[:champ_telephone].present? && @params[:sms].blank?
      @errors << "l'attribut champ_telephone est obligatoire quand le champ 'sms' est donné." if @params[:sms].present? && @params[:champ_telephone].blank?
      @errors << "L'un des attributs champs_montant ou montant doit être renseigné" if @params[:montant].blank? && @params[:champ_montant].blank?
    end

    def must_check?(dossier)
      @states.include?(dossier.state)
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      @dossier = dossier
      @demarche = demarche

      montant = annotation(@params[:champ_montant])&.value || @params[:montant]
      return if montant.blank?

      montant = montant.to_i
      payment_id = annotation(@params[:champ_ordre_de_paiement])&.value
      if montant.positive?
        if payment_id.blank?
          ask_for_payment(montant)
        else
          check_payment
        end
      elsif montant.zero?
        execute(@when_free, nil)
      end
    end

    def check_delay = (@test_mode ? 1 : 5).minutes.since.end_of_minute

    private

    def ask_for_payment(amount)
      order = create_order(amount)
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_ordre_de_paiement], order[:paymentOrderId])
      notify_user(order)
      execute(@when_asked, order)
      dossier_updated(@dossier)
      schedule_next_check
    end

    def create_order(amount)
      reference = "#{@reference_prefix}-#{@dossier.number}"
      phone_number = param_field(:champ_telephone)&.value
      return_url = "https://www.mes-demarches.gov.pf/dossiers/#{@dossier.number}/messagerie"
      receipt_email = @dossier.usager.email
      if phone_number.present? && phone_number.match?(/8[789][0-9]{6}/)
        message = instanciate(@params[:sms])
        order = @api.create_sms_order(amount, reference, phone_number, message, return_url:, receipt_email:)
      else
        order = @api.create_url_order(amount, reference, return_url:, receipt_email:)
      end
      report_error(order) if order[:errorCode].present?
      order
    end

    def schedule_next_check
      ScheduledTask.enqueue(dossier.number, self.class, @params, check_delay)
    end

    def check_payment
      order_id = annotation(@params[:champ_ordre_de_paiement])&.value
      unless order_id.present? && order_id.match(/[a-f0-9]{32}/)
        Rails.logger.warn("Vérification de l'état du paiement ignoré: L'id #{order_id} de la demande de paiement ne corresponds pas à une demande PayZen.")
        return
      end

      order = get_order(order_id)
      return unless order

      if order[:errorCode].present?
        report_error(order)
        return
      end

      case order[:paymentOrderStatus]
      when 'RUNNING', 'REFUSED'
        Rails.logger.info("Schedule payzen order check for dossier #{@dossier.number} field #{@params[:champ_montant]} at #{check_delay}")
        schedule_next_check
      when 'PAID'
        Rails.logger.info("Payzen order for dossier #{@dossier.number} field #{@params[:champ_montant]} is paid")
        execute(@when_paid, order)
      when 'EXPIRED', 'CANCELLED'
        Rails.logger.info("Payzen order for dossier #{@dossier.number} field #{@params[:champ_montant]} has expired")
        execute(@when_expired, order)
      else
        raise StandardError, "Payzen: Status inconnu de l'ordre de paiement: #{order['paymentOrderStatus']}"
      end
    end

    def get_order(order_id)
      begin
        order = @api.get_order(order_id)
      rescue APIEntreprise::API::ServiceUnavailable => e
        Rails.logger.error("Erreur réseau lors de la lecture de l'ordre de paiement #{order_id}: #{e.message}")
        e.backtrace.select { |b| b.include?('/app/') }.first(7).each { |b| Rails.logger.error(b) }
      rescue StandardError => e
        message = "Erreur lors l'appel à PayZen"
        NotificationMailer.with(demarche: @demarche.id, dossier: @dossier.number, message:, e:).report_error.deliver_later
      ensure
        schedule_next_check unless order
      end
      order
    end

    def report_error(order)
      message = "Erreur PayZen en vérifiant un ordre de paiement: #{order[:errorCode]} - #{order[:errorMessage]}"
      NotificationMailer.with(demarche: @demarche.id, dossier: @dossier.number, message:).report_error.deliver_later
    end

    DEFAULT_MESSAGE = <<~MSG
      Bonjour,
      Pour obtenir le résultat de votre demande, vous devez effectuer le paiement d'un montant de {amount} Fcp en cliquant sur ce lien {paymentURL}.
      Ce lien est valide jusqu'au {expirationDate}."
    MSG

    def notify_user(order)
      template = @params[:message].presence || DEFAULT_MESSAGE
      body = instanciate(template, order)
      SendMessage.send(@dossier, @demarche.instructeur, body)
    end

    def execute(tasks, order)
      tasks.each do |task|
        Rails.logger.info("Applying task #{task.class.name}")
        if task.is_a?(Payzen::Task)
          task.process_order(@demarche, @dossier, order)
        else
          task.process(@demarche, @dossier)
        end
      end
    end
  end
end
