# frozen_string_literal: true

module Payzen
  class PaymentOrder < FieldChecker
    include Payzen::StringTemplate
    attr_reader :when_asked, :when_paid, :when_expired

    CHECK_DELAY = 5.minutes.since.end_of_minute

    def version
      super + 1
    end

    def required_fields
      %i[reference champ_montant champ_ordre_de_paiement message]
    end

    def authorized_fields
      %i[etat_du_dossier tentatives quand_payé quand_demandé quand_expiré mode_test champ_telephone sms]
    end

    def initialize(params)
      super
      @when_asked = InspectorTask.create_tasks(@params[:quand_demandé])
      @when_paid = InspectorTask.create_tasks(@params[:quand_payé])
      @when_expired = InspectorTask.create_tasks(@params[:quand_expiré])

      @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])

      test_mode = Set['oui', 'true', '1', 1].include?(@params[:mode_test]&.downcase)
      @api = Payzen::API.new(test_mode:)

      @reference_prefix = @params[:reference]
      @reference_prefix = 'md' if @reference_prefix.blank?
      @errors << "l'attribut sms est obligatoire quand le champ 'champ_telephone' est donné." if @params[:champ_telephone].present? && @params[:sms].blank?
      @errors << "l'attribut champ_telephone est obligatoire quand le champ 'sms' est donné." if @params[:sms].present? && @params[:champ_telephone].blank?
    end

    def must_check?(dossier)
      @states.include?(dossier.state)
    end

    def process(demarche, dossier)
      return unless must_check?(dossier)

      @dossier = dossier
      @demarche = demarche

      montant = annotation(@params[:champ_montant])&.value.to_i
      return unless montant.positive?

      payment_id = annotation(@params[:champ_ordre_de_paiement])&.value
      if payment_id.blank?
        ask_for_payment(montant)
      else
        check_payment
      end
    end

    private

    def ask_for_payment(amount)
      order = craate_order(amount)
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_ordre_de_paiement], order[:paymentOrderId])
      notify_user(order)
      execute(@when_asked, order)
      annotation_updated_on(@dossier)
      schedule_next_check
    end

    def craate_order(amount)
      reference = "#{@reference_prefix}-#{@dossier.number}"
      phone_number = param_field(:champ_telephone)&.value
      if phone_number.present? && phone_number.match?(/8[789][0-9]{6}/)
        message = instanciate(@params[:sms])
        order = @api.create_sms_order(amount, reference, phone_number, message)
      else
        order = @api.create_url_order(amount, reference)
      end
      order
    end

    def schedule_next_check
      ScheduledTask.enqueue(dossier.number, self.class, @params, CHECK_DELAY)
    end

    def check_payment
      order_id = annotation(@params[:champ_ordre_de_paiement])&.value
      order = @api.get_order(order_id)
      case order[:paymentOrderStatus]
      when 'RUNNING', 'REFUSED'
        schedule_next_check
      when 'PAID'
        execute(@when_paid, order)
      when 'EXPIRED', 'CANCELLED'
        execute(@when_expired, order)
      else
        raise StandardError, "Payzen: Status inconnu de l'ordre de paiement: #{order['paymentOrderStatus']}"
      end
    end

    DEFAULT_MESSAGE = <<~MSG
      Bonjour,
      Pour obtenir le résultat de votre demande, vous devez effectuer le paiement d'un montant de {amount} Fcp en cliquant sur ce lien {paymentURL}.
      Ce lien est valide jusqu'au {expirationDate}."
    MSG

    def notify_user(order)
      template = @params[:message].presence || DEFAULT_MESSAGE
      body = instanciate(template, order)
      SendMessage.send(@dossier.id, @demarche.instructeur, body)
    end

    def execute(tasks, order)
      tasks.each do |task|
        if task.is_a?(Payzen::Task)
          task.process_order(@demarche, @dossier, order)
        else
          task.process(@demarche, @dossier)
        end
      end
    end
  end
end
