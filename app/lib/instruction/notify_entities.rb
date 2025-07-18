# frozen_string_literal: true

module Instruction
  class NotifyEntities < FieldChecker
    def version
      super + 5
    end

    def required_fields
      super + %i[champ_entites champ_etat_envois message baserow_config baserow_table_id]
    end

    def authorized_fields
      super + %i[objet]
    end

    def initialize(params)
      super
      @email_field = nil
      @entity_field = nil
      setup_baserow_fields
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      @msgs = []

      # Récupérer les entités du champ
      entities = fetch_entities
      return unless entities.any?

      # Récupérer l'état des envois existants
      existing_notifications = load_existing_notifications

      # Récupérer les emails depuis Baserow pour les entités
      email_entity_map = fetch_emails_for_entities(entities)
      return unless email_entity_map.any?

      # Envoyer les notifications
      send_notifications(email_entity_map, existing_notifications)

      # Sauvegarder les messages
      save_messages
    end

    private

    def setup_baserow_fields
      table = baserow_table
      return unless table

      @email_field = find_field_by_pattern(table, /email|courriel|mail/i)
      @entity_field = find_field_by_pattern(table, /entité|cellule|organisme|commune|service/i)

      unless @email_field
        @errors << 'Impossible de trouver une colonne email dans la table Baserow'
        return
      end

      unless @entity_field
        @errors << 'Impossible de trouver une colonne entité dans la table Baserow'
        return
      end

      add_message("Table Baserow connectée - Colonnes: email='#{@email_field[:name]}', entité='#{@entity_field[:name]}'")
    rescue StandardError => e
      @errors << "Erreur lors de la connexion à Baserow: #{e.message}"
    end

    def fetch_entities
      champ_entites = param_annotation(:champ_entites)
      if champ_entites.blank? || champ_entites.values.blank?
        add_message("Champ #{@params[:champ_entites]} vide.")
        return []
      end

      entities = champ_entites.values
      add_message("Entités détectées: #{entities.join(', ')}")
      entities
    end

    def load_existing_notifications
      champ_etat = param_annotation(:champ_etat_envois)
      return {} if champ_etat.blank? || champ_etat.value.blank?

      notifications = {}
      champ_etat.value.split("\n").each do |line|
        next unless line.match(/\[(.+?)\] (.+?) \((.+?)\)/)

        timestamp = Regexp.last_match(1)
        email = Regexp.last_match(2)
        entities = Regexp.last_match(3)

        notifications[email] = {
          timestamp:,
          entities:
        }
      end

      notifications
    end

    def fetch_emails_for_entities(entities)
      table = baserow_table
      return {} unless table

      email_entity_map = {}

      entities.each do |entity|
        fetch_emails_for_entity(entity, table, email_entity_map)
      end

      add_message("#{email_entity_map.size} emails trouvés pour les entités")
      email_entity_map
    rescue StandardError => e
      add_message("Erreur lors de la récupération des emails: #{e.message}")
      {}
    end

    def fetch_emails_for_entity(entity, table, email_entity_map)
      params = {
        filters: {
          filter_type: 'AND',
          filters: [
            { type: 'contains',
              field: @entity_field[:id],
              value: entity }
          ]
        }
      }

      results = table.list_rows(params)
      email_field_name = "field_#{@email_field[:id]}"

      results['results']&.each do |row|
        email = row[email_field_name]
        next if email.blank?

        if email_entity_map[email]
          email_entity_map[email] << entity
        else
          email_entity_map[email] = [entity]
        end
      end
    end

    def send_notifications(email_entity_map, existing_notifications)
      new_notifications = []
      sent_count = 0

      email_entity_map.each do |email, entities|
        # Vérifier si cette personne a déjà été notifiée
        if existing_notifications.key?(email)
          # add_message("Notification déjà envoyée à #{email}.")
          next
        end

        # Envoyer la notification
        next unless send_notification_to_email(email, entities)

        timestamp = Time.current.strftime('%Y-%m-%d %H:%M:%S')
        entities_str = entities.join(', ')
        new_notifications << "[#{timestamp}] #{email} (#{entities_str})"
        sent_count += 1
        # add_message("Notification envoyée à #{email} pour #{entities_str}")
      end

      # Mettre à jour le champ d'état des envois
      update_notification_state(existing_notifications, new_notifications)

      # add_message("#{sent_count} nouvelles notifications envoyées")
    end

    def send_notification_to_email(email, _entities)
      subject = @params[:objet] || 'Notification concernant le dossier {number}'
      message = @params[:message]

      # Instancier les variables dans le sujet et le message
      final_subject = instanciate(subject)
      final_message = instanciate(message)

      params = {
        dossier: @dossier.number,
        demarche: @demarche.id,
        recipients: email,
        subject: final_subject,
        message: final_message
      }
      NotificationMailer.with(params).notify_user.deliver_later

      true
    rescue StandardError => e
      add_message("Erreur lors de l'envoi à #{email}: #{e.message}")
      false
    end

    def update_notification_state(existing_notifications, new_notifications)
      return if new_notifications.empty?

      # Reconstruire le contenu du champ
      all_notifications = existing_notifications.map do |email, notif|
        "[#{notif[:timestamp]}] #{email} (#{notif[:entities]})"
      end
      all_notifications.concat(new_notifications)

      # Mettre à jour le champ via save_annotation
      save_annotation(@params[:champ_etat_envois], all_notifications.join("\n"))
    end

    def baserow_table
      return @baserow_table if @baserow_table

      @baserow_table = Baserow::Config.table(@params[:baserow_table_id], @params[:baserow_config])
    rescue StandardError => e
      @errors << "Erreur lors de la connexion à Baserow: #{e.message}"
      nil
    end

    def find_field_by_pattern(table, pattern)
      table.fields.find { |k, _v| k =~ pattern }&.second
    end

    def add_message(message)
      @msgs ||= []
      @msgs << message
    end

    def save_messages
      return if @msgs.blank?

      save_annotation('Messages du robot', @msgs.join("\n"))
    end

    def save_annotation(field, value)
      changed = SetAnnotationValue.set_value(@dossier, @demarche&.instructeur || instructeur_id, field, value)
      dossier_updated(@dossier) if changed
      value
    end
  end
end
