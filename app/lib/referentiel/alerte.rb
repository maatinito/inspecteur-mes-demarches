# frozen_string_literal: true

module Referentiel
  # Alerte (courriel + Sentry) quand le verrou refuse une table, au plus une fois par 24 h.
  module Alerte
    FREQUENCE = 24.hours

    def self.signaler(refus) # rubocop:disable Naming/PredicateMethod
      table = refus.table
      return false if table.nil?
      return false if table.alerte_le && table.alerte_le > FREQUENCE.ago

      message = "#{refus.message} Synchronisation et effacement suspendus. " \
                'Rétablir le marqueur dans le builder, puis reculer le curseur de la démarche au ' \
                "#{table.refus_depuis} pour rejouer les suppressions manquées."
      envoyer(message)
      Sentry.capture_message(message)
      table.update_columns(alerte_le: Time.current)
      true
    end

    def self.informer(table, message)
      envoyer("#{message} (backend #{table.backend}, table #{table.table_ref})")
    end

    def self.envoyer(message)
      NotificationMailer.with(message:, tags: Rails.logger.formatter.current_tags.join(',')).report_error.deliver_later
    end
    private_class_method :envoyer
  end
end
