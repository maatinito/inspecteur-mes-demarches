# frozen_string_literal: true

# Écriture idempotente de lignes dans un bloc répétable d'annotations :
# une valeur par colonne, seules les valeurs modifiées sont envoyées, et les
# colonnes listées des lignes en trop sont vidées (les autres colonnes,
# saisies par l'instructeur ou calculées par formule, ne sont pas touchées).
#
# À inclure dans un FieldChecker : utilise @dossier et @demarche.
module EcritureBloc
  private

  # lignes : une valeur par colonne, dans l'ordre de `colonnes`. Le bloc
  # optionnel reçoit chaque ligne en trop avant qu'elle soit vidée.
  def recopie(bloc_label, lignes, colonnes)
    bloc = SetAnnotationValue.allocate_blocks(@dossier, @demarche.instructeur, bloc_label, lignes.size)
    changed = false
    bloc.rows.each_with_index do |row, index|
      ligne = lignes[index]
      yield row if ligne.nil? && block_given?
      colonnes.each_with_index do |label, colonne|
        changed |= ecrit(row, bloc_label, label, ligne && ligne[colonne])
      end
    end
    changed
  end

  def champ(row, label)
    row.champs.find { |c| c.label == label }
  end

  def valeur(row, label)
    annotation = champ(row, label)
    annotation && SetAnnotationValue.value_of(annotation).to_s
  end

  # Retourne un booléen de statut (comme save/update), pas un prédicat
  def ecrit(row, bloc_label, label, value)
    annotation = champ(row, label)
    unless annotation
      Rails.logger.warn("Champ '#{label}' introuvable dans le bloc '#{bloc_label}' du dossier #{@dossier.number}")
      return false
    end
    value = SetAnnotationValue.coerce_to_annotation_type(annotation, annotation.__typename == 'IntegerNumberChamp' ? value.to_i : value.to_s)
    return false if SetAnnotationValue.value_of(annotation).to_s == value.to_s

    SetAnnotationValue.raw_set_annotation(@dossier.id, @demarche.instructeur, annotation, value)
    true
  rescue StandardError => e
    # Liste de choix : une valeur absente des options est refusée par le
    # serveur et le champ reste vide.
    Rails.logger.error("Dossier #{@dossier.number} : '#{label}' du bloc '#{bloc_label}' ne peut pas recevoir '#{value}' : #{e.message}")
    false
  end

  # Ramène une valeur à l'option d'une liste qui ne diffère que par les
  # accents, la ponctuation ou la casse (« Bananiers/fe'i » => « Bananiers/fei »).
  def option_equivalente(valeur, options)
    cle = ->(texte) { I18n.transliterate(texte.to_s).downcase.gsub(/[^a-z0-9]/, '') }
    Array(options).find { |option| cle.call(option) == cle.call(valeur) } || valeur
  end

  def lignes_du_bloc(champ_source)
    object_field_values(@dossier, champ_source, log_empty: false).find { |c| c.respond_to?(:rows) }&.rows || []
  end

  def lignes_actuelles(bloc_label)
    SetAnnotationValue.get_annotation(@dossier, bloc_label)&.rows
  end
end
