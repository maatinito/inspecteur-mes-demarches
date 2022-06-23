# frozen_string_literal: true

class PaymentOrder < FieldChecker
  include StringTemplate

  def version
    super + 1
  end

  def required_fields
    %i[reference champ_montant champ_etat_paiement champ_ordre_de_paiement message]
  end

  def authorized_fields
    %i[etat_du_dossier tentatives quand_payé quand_demandé quand_expiré mode_test]
  end

  def initialize(params)
    super
    @when_asked = create_tasks(@params[:quand_demandé])
    @when_paid = create_tasks(@params[:quand_payé])
    @when_expired = create_tasks(@params[:quand_expiré])

    @states = Set.new([*(@params[:etat_du_dossier] || 'en_instruction')])

    test_mode = Set['oui', 'true', '1', 1].include?(@params[:mode_test]&.downcase)
    @api = Payzen::API.new(test_mode:)

    @reference = @params[:reference]
    @reference_prefix = 'md' if @reference.blank?
  end

  def dossier_has_right_state?(dossier)
    @states.include?(dossier.state)
  end

  def process(demarche, dossier)
    puts "-- dossier #{dossier.number} ok ==> Payzen order --"
    return unless dossier_has_right_state?(dossier)

    @dossier = dossier
    @demarche = demarche

    montant = field(@params[:champ_montant])
    return unless montant.present? && montant.to_i.positive?

    payment_id = field(@params[:champ_ordre_de_paiement])
    if payment_id.blank?
      ask_for_payment(montant)
    else
      check_payment
    end
  end

  private

  def ask_for_payment(amount)
    reference = "#{@reference_prefix}-#{@dossier.number}"
    order = @api.create_url_order(amount, reference)
    SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_ordre_de_paiement], order['paymentOrderId'])
    SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_expiration], order['expirationDate'])
    send_notification(order)
    execute(@when_asked, order)
    annotation_updated_on(@dossier)
    schedule_next_check
  end

  def schedule_next_check
    ScheduledTask.create(dossier: dossier.number, task: self.class.name.underscore, parameters: @params.to_json, run_at: 15.minutes.since)
  end

  def check_payment
    order_id = field(@params[:champ_ordre_de_paiement])
    order = @api.get_order(order_id)
    case order['paymentOrderStatus']
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

  def send_notification(order)
    template = @params[:message].presence || DEFAULT_MESSAGE
    body = instanciate(template, order)
    SendMessage.send(@dossier.id, @demarche.instructeur, body)
  end

  def execute(tasks, order)
    tasks.each do |task|
      task.process_order(@demarche, @dossier, order) if task.is_a?(Payzen::Task)
    end
  end
end
