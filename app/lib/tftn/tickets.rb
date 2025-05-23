# frozen_string_literal: true

module Tftn
  class Tickets < FieldChecker
    def version
      super + 1
    end

    def required_fields
      super + %i[id_table_baserow champ_cours prix_seance annotation_montant]
    end

    def authorized_fields
      super + %i[champ_nb_tickets annotation_message_usager config_baserow]
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

      if champ_nb_tickets.value.to_s.downcase.include?('toutes')
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
      add_message("Cours: #{nom_cours}")
      add_message("Nombre de séances trouvées: #{nb_seances}")
      add_message("Prix unitaire: #{prix_seance} XPF")
      add_message("Prix total calculé: #{prix_total} XPF")
    end

    private

    def get_remaining_sessions(nom_cours)
      # Récupérer les paramètres Baserow
      table_id = @params[:id_table_baserow]
      config_name = @params[:config_baserow]

      # Créer un client Baserow avec la configuration spécifiée
      table = Baserow::Config.table(table_id, config_name)

      # Charger les champs pour trouver les IDs
      fields = table.client.list_fields(table_id)

      # Trouver les IDs des champs qui nous intéressent
      cours_field = fields.find { |f| f['name'] =~ /cours/i }
      date_field = fields.find { |f| f['name'] =~ /date/i }

      if cours_field.nil? || date_field.nil?
        add_message("Impossible de trouver les champs 'cours' et/ou 'date' dans la table Baserow")
        save_messages
        return nil
      end

      cours_field_id = cours_field['id']
      date_field_id = date_field['id']

      # Construire les paramètres de filtrage
      today = Date.today.strftime('%Y-%m-%d')
      params = {
        "filter__field_#{cours_field_id}__equal" => nom_cours,
        "filter__field_#{date_field_id}__date_after" => today
      }

      # Faire la requête
      results = table.client.list_rows(table_id, params)

      # Retourner le nombre de séances
      results['count']
    rescue StandardError => e
      add_message("Erreur lors de la récupération des séances: #{e.message}")
      save_messages
      nil
    end

    def add_message(message)
      @msgs ||= []
      @msgs << message
    end

    def save_messages
      messages = @msgs.join("\n")
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
