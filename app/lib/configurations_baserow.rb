# frozen_string_literal: true

# Lecture des configurations du robot côté Baserow.
module ConfigurationsBaserow
  # Numéros des démarches dont une entrée de configuration (bloc avec `demarches`) synchronise
  # vers la table Baserow `table_id` : une tâche baserow_sync à n'importe quelle profondeur
  # (when_ok, contrôles, paramètres d'une autre tâche). Identifiants comparés comme des chaînes.
  def self.demarches_synchronisees_vers(table_id)
    VerificationService.configs.values.flat_map do |data|
      VerificationService.procedures(data).values
                         .select { |procedure| synchronise_vers?(procedure, table_id.to_s) }
                         .flat_map { |procedure| [*procedure['demarches']] }
    end.uniq.sort
  end

  def self.synchronise_vers?(noeud, table_id)
    case noeud
    when Hash
      synchro = noeud['baserow_sync']
      cible = synchro['baserow'] if synchro.is_a?(Hash)
      return true if cible.is_a?(Hash) && cible['table_id'].to_s == table_id

      noeud.values.any? { |valeur| synchronise_vers?(valeur, table_id) }
    when Array then noeud.any? { |valeur| synchronise_vers?(valeur, table_id) }
    else false
    end
  end
  private_class_method :synchronise_vers?
end
