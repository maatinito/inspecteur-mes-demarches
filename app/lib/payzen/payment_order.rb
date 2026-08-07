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
      %i[etat_du_dossier champ_montant montant quand_payé quand_demandé quand_expiré quand_gratuit mode_test champ_telephone sms scheduled]
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

      montant = champ_value(annotation(@params[:champ_montant])).presence || @params[:montant]
      return if montant.blank?

      montant = montant.to_i
      payment_id = champ_value(annotation(@params[:champ_ordre_de_paiement]))
      if montant.positive?
        if payment_id.blank?
          # Un rejeu planifié ne crée jamais d'ordre : ses params sont figés en base et
          # peuvent être périmés (mode_test, clés). Seule l'inspection relit le YAML courant.
          ask_for_payment(montant) unless @params[:scheduled]
        else
          check_payment
        end
      elsif montant.zero?
        execute(@when_free, nil)
      end
    end

    def interval_minutes(t_minutes)
      min = 2.0
      max = 30.0
      scale = 100.0
      delta = max - min

      interval = min + (delta * Math.log(1 + (t_minutes / scale)) / Math.log(1 + (4320.0 / scale)))
      interval.round(1)
    end

    def check_delay = (@test_mode ? 1 : 15).minutes.since.end_of_minute

    # PayZen cloisonne les ordres entre test et production : un ordre créé avec l'autre clé
    # de la boutique est invisible ici et répond PSP_1000. Le cas arrive quand la
    # configuration bascule de mode alors que des ordres sont en cours, et le message brut
    # ne permet pas de le diagnostiquer.
    ORDER_NOT_FOUND = 'PSP_1000'

    DEFAULT_MESSAGE = <<~MSG
      Bonjour,
      Pour obtenir le résultat de votre demande, vous devez effectuer le paiement d'un montant de {amount} Fcp en cliquant sur ce lien {paymentURL}.
      Ce lien est valide jusqu'au {expirationDate}."
    MSG

    private

    def ask_for_payment(amount)
      order = create_order(amount)
      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_ordre_de_paiement], order[:paymentOrderId])
      begin
        notify_user(order)
      rescue StandardError => e
        # forget about order if message not sent
        SetAnnotationValue.set_value(@dossier, @demarche.instructeur, @params[:champ_ordre_de_paiement], '')
        raise e
      end
      dossier_updated(@dossier)
      schedule_next_check
      execute(@when_asked, order)
    end

    def create_order(amount)
      reference = "#{@reference_prefix}-#{@dossier.number}"
      phone_number = champ_value(param_field(:champ_telephone))
      return_url = "https://www.mes-demarches.gov.pf/dossiers/#{@dossier.number}/messagerie"
      receipt_email = @dossier.usager.email
      if phone_number.present? && phone_number.match?(/8[789][0-9]{6}/)
        message = instanciate(@params[:sms])
        order = @api.create_sms_order(amount, reference, phone_number, message, return_url:, receipt_email:)
      else
        order = @api.create_url_order(amount, reference, return_url:, receipt_email:)
      end
      raise StandardError, "Erreur PayZen en créant un ordre de paiement: #{order[:errorCode]} - #{order[:errorMessage]}" if order[:errorCode].present?

      order
    end

    def schedule_next_check
      # 'scheduled' est réinjecté à chaque rejeu : inutile de le figer en base.
      ScheduledTask.enqueue(dossier.number, self.class, @params.except(:scheduled), check_delay)
    end

    def order_error_message(order, order_id)
      message = "Erreur PayZen en vérifiant un ordre de paiement: #{order[:errorCode]} - #{order[:errorMessage]}"
      return message unless order[:errorCode] == ORDER_NOT_FOUND && found_in_other_mode?(order_id)

      "#{message}. L'ordre #{order_id} existe en mode #{@test_mode ? 'production' : 'test'} alors que la " \
        "configuration est en mode #{@test_mode ? 'test' : 'production'} : vider l'annotation " \
        "'#{@params[:champ_ordre_de_paiement]}' pour en générer un nouveau dans le mode courant."
    end

    def found_in_other_mode?(order_id)
      password = @params[@test_mode ? :cle : :cle_de_test]
      return false if password.blank?

      Payzen::API.new(@params[:boutique], password).get_order(order_id)[:errorCode].blank?
    rescue StandardError
      false # la sonde est un confort de diagnostic, elle ne doit jamais masquer l'erreur d'origine
    end

    def check_payment
      order_id = champ_value(annotation(@params[:champ_ordre_de_paiement]))
      unless order_id.present? && order_id.match(/^[a-f0-9]{32}$/)
        Rails.logger.warn("Vérification de l'état du paiement ignoré: L'id #{order_id} de la demande de paiement ne corresponds pas à une demande PayZen.")
        return
      end

      begin
        order = @api.get_order(order_id)
        raise StandardError, order_error_message(order, order_id) if order[:errorCode].present?

        Rails.logger.info("Payzen order check for dossier #{@dossier.number}: #{order[:paymentOrderStatus]}")
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
      rescue APIEntreprise::API::ServiceUnavailable => e
        schedule_next_check
        Rails.logger.error("Erreur réseau lors de la lecture de l'ordre de paiement #{order_id}: #{e.message}")
      end
    end

    def notify_user(order)
      template = @params[:message].presence || DEFAULT_MESSAGE
      body = instanciate(template, order)
      SendMessage.deliver_message(@dossier, @demarche.instructeur, body)
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
