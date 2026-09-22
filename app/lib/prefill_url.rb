# frozen_string_literal: true

require 'base64'
require 'cgi'

# URL de préremplissage d'une démarche Mes-Démarches :
#   <MES_DEMARCHES_URL>/commencer/<chemin>?champ_<id>=<valeur>&…
# où <id> est l'identifiant GraphQL du descripteur de champ, Base64("Champ-<stable_id>").
# Les dates partent en ISO 8601 (AAAA-MM-JJ), seul format accepté par la plateforme.
# La clé est aussi échappée : un stable_id court produit un Base64 avec « = » de padding.
class PrefillUrl
  def self.build(chemin, valeurs)
    query = valeurs.filter_map do |stable_id, valeur|
      texte = format_value(valeur)
      next if texte.blank?

      "champ_#{CGI.escape(champ_id(stable_id))}=#{CGI.escape(texte)}"
    end
    "#{MesDemarches.public_url}/commencer/#{chemin}?#{query.join('&')}"
  end

  def self.champ_id(stable_id)
    Base64.strict_encode64("Champ-#{stable_id}")
  end

  def self.format_value(valeur)
    case valeur
    when nil then nil
    when Date, DateTime, Time then valeur.to_date.iso8601
    when Array then valeur.map { |v| format_value(v) }.compact.join(', ')
    else valeur.to_s.strip
    end
  end
end
