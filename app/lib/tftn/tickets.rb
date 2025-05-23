# frozen_string_literal: true

module Tftn
  class Tickets < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[id_table_cours champ_cours prix_seance annotation_montant]
    end

    def authorized_fields
      super + %i[champ_nb_tickets annotation_message_usager acces_baserow]
    end

    def process(demarche, dossier)
      super
      return unless dossier_has_right_state

      @msgs = []

      # Récupérer et valider les données d'entrée
      nom_cours = fetch_course_name
      return unless nom_cours

      nb_tickets_max = fetch_nb_tickets_max

      # Obtenir le nombre de séances disponibles
      nb_seances = get_remaining_sessions(nom_cours)
      return unless nb_seances

      # Limiter au nombre de tickets demandés si spécifié
      nb_seances = [nb_seances, nb_tickets_max].min if nb_tickets_max.present? && nb_tickets_max.positive?

      # Calculer et stocker les résultats
      compute_and_store_results(nom_cours, nb_seances, nb_tickets_max)

      # Enregistrer les messages
      save_messages
    end

    def fetch_course_name
      champ_cours = param_field(:champ_cours)
      if champ_cours.blank? || champ_cours.value.blank?
        add_message("Champ #{@params[:champ_cours]} vide.")
        save_messages
        return nil
      end
      champ_cours.value
    end

    def fetch_nb_tickets_max
      return nil unless @params[:champ_nb_tickets].present?

      champ_nb_tickets = param_field(:champ_nb_tickets)
      return nil unless champ_nb_tickets.present? && champ_nb_tickets.value.present?

      if champ_nb_tickets.value.to_s.downcase.include?('tou')
        Float::INFINITY # Pas de limite
      else
        champ_nb_tickets.value.to_i
      end
    end

    def compute_and_store_results(nom_cours, nb_seances, nb_tickets_max)
      # Calculer le prix total
      prix_seance = @params[:prix_seance].to_i
      prix_total = nb_seances * prix_seance

      # Stocker le prix dans l'annotation privée
      save_annotation(@params[:annotation_montant], prix_total)

      # Créer et stocker un message explicatif pour l'usager
      message_usager = construire_message_usager(nom_cours, nb_seances, prix_seance, prix_total, nb_tickets_max)
      save_annotation(@params[:annotation_message_usager], message_usager) if @params[:annotation_message_usager].present?

      # Ajouter les informations au journal
      add_message("Nombre de séances possibles: #{nb_seances}, Prix unitaire: #{prix_seance} XPF")
    end

    private

    def get_remaining_sessions(nom_cours)
      # Récupérer les paramètres Baserow
      table_id = @params[:id_table_cours]
      config_name = @params[:acces_baserow]

      # Créer un client Baserow avec la configuration spécifiée
      table = Baserow::Config.table(table_id, config_name)

      # requete baserow pour selectionner les séances du cours donné après aujourd'hui
      params = query_params(table, nom_cours)
      # Faire la requête
      results = table.client.list_rows(table_id, params)

      # Retourner le nombre de séances
      results['count']
    rescue StandardError => e
      add_message("Erreur lors de la récupération des séances: #{e.message}")
      save_messages
      nil
    end

    def query_params(table, nom_cours)
      # Trouver les IDs des champs qui nous intéressent
      cours_field = table.fields.find { |k, _v| k =~ /label/i }&.second
      active_field = table.fields.find { |k, _v| k =~ /actif/i }&.second
      date_field = table.fields.find { |k, _v| k =~ /date/i }&.second
      raise "Impossible de trouver les champs 'cours' et/ou 'date' dans la table Baserow" if cours_field.nil? || date_field.nil?

      {
        # "include": "field_#{date_field['id']}",
        filters: {
          filter_type: 'AND',
          filters: [
            { type: 'has_value_equal',
              field: cours_field[:id],
              value: nom_cours },
            { type: 'boolean',
              field: active_field[:id],
              value: '1' },
            { type: 'date_is_on_or_after',
              field: date_field[:id],
              value: 'Pacific/Honolulu??today' }
          ]
        }
      }
    end

    def add_message(message)
      @msgs ||= []
      @msgs << message
    end

    def save_messages
      return if @msgs.blank?

      message = @msgs.join("\n")
      old_messages = annotation('Messages du robot')&.value
      return if old_messages&.include?(message)

      date = Time.now.strftime('%Y-%m-%d %H:%M')
      messages = "#{date} :\n#{message}"
      save_annotation('Messages du robot', messages)
      messages
    end

    def save_annotation(field, value)
      changed = SetAnnotationValue.set_value(@dossier, @demarche&.instructeur || instructeur_id, field, value)
      dossier_updated(@dossier) if changed
      value
    end

    def dossier_has_right_state
      @states.include?(@dossier.state)
    end

    def construire_message_usager(nom_cours, nb_seances, prix_seance, prix_total, nb_tickets_max)
      amount_msg = "Le montant à payer est de #{prix_total} XPF (#{nb_seances} séances à #{prix_seance} XPF)."
      if nb_tickets_max.present? && nb_tickets_max.positive?
        if nb_tickets_max == Float::INFINITY
          # Cas "Toutes les séances restantes"
          "Vous avez demandé toutes les séances disponibles pour le cours #{nom_cours}. #{amount_msg}"
        elsif nb_seances < nb_tickets_max
          # Cas où il y a moins de séances disponibles que demandées
          "Vous avez demandé #{nb_tickets_max} tickets pour le cours #{nom_cours}, mais seulement #{nb_seances} séances sont disponibles. #{amount_msg}"
        else
          # Cas où il y a suffisamment de séances disponibles
          "Vous avez demandé #{nb_tickets_max} tickets pour le cours #{nom_cours}. #{amount_msg}"
        end
      else
        # Cas où aucun nombre de tickets n'est spécifié
        "Il y a #{nb_seances} séances disponibles pour le cours #{nom_cours}. #{amount_msg}"
      end
    end
  end
end
