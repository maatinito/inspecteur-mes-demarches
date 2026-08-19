# frozen_string_literal: true

module Calculs
  # Transforme la réponse d'un champ à choix en un drapeau par branche, pour les
  # conditionnels Sablon `«variable:if(present?)»` des modèles de publipostage.
  #
  # Sablon ne sait pas comparer une valeur à une constante : un modèle qui affiche
  # un paragraphe différent selon la réponse a besoin d'une variable distincte par
  # branche. Ce calcul les pose toutes — vides sauf celle qui correspond à la
  # réponse, qui reçoit la valeur du champ.
  #
  #   calculs:
  #     - calculs/value_flags:
  #         champ: Couverture maladie par l'organisme d'accueil
  #         valeurs:
  #           "Oui": reponse_couverture_maladie_oui
  #           "Non": reponse_couverture_maladie_non
  #           "Je ne sais pas": reponse_couverture_maladie_incertaine
  #
  # `source:` (`champ` ou `annotation`) lève l'ambiguïté quand un champ usager et
  # une annotation privée portent le même libellé. Sans lui, la recherche porte
  # sur les deux et retient la première trouvée, l'usager d'abord.
  #
  # Les drapeaux entrent dans l'empreinte du publipostage : changer la réponse
  # régénère et renvoie le document, ce qui est le comportement attendu puisque
  # le texte de la convention en dépend.
  class ValueFlags < FieldChecker
    def required_fields
      super + %i[champ valeurs]
    end

    def authorized_fields
      super + %i[source]
    end

    def version
      super + 1
    end

    def process_row(row, output)
      valeurs = @params[:valeurs] || {}
      # Toutes les variables sont posées à chaque passage, y compris les vides :
      # une clé qui apparaîtrait ou disparaîtrait de l'empreinte selon la réponse
      # ferait renvoyer une convention identique.
      valeurs.each_value { |variable| output[variable.to_s] = '' }

      value = valeur_du_champ(row).to_s
      variable = valeurs[value]
      output[variable.to_s] = value if variable.present?
    end

    private

    def valeur_du_champ(row)
      case @params[:source].to_s
      when 'champ' then champs_to_values(fields(@params[:champ])).first
      when 'annotation' then champs_to_values(annotations(@params[:champ])).first
      else get_values_of(row, @params[:champ])&.first
      end
    end
  end
end
