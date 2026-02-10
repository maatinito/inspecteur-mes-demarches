# frozen_string_literal: true

# Génère un QR code à partir d'un template.
#
# Syntaxe YAML :
#   calculs:
#     - qrcode:
#         taille: 300
#         contenu: "https://www.mes-demarches.gov.pf/dossiers/{numero}"
#         colonne: "qrcode"
#
# Utilisation dans le template Sablon :
#   «@qrcode.image:start»[placeholder image]«@qrcode.image:end»
#   Lien : «=qrcode.url»
#
# La méthode instanciate() (héritée de FieldChecker) supporte :
#   - Variables simples : {numero}
#   - Préfixes/suffixes : {prefix;numero;suffix}
#   - Ternaires : {champ?oui:non}
#
class Qrcode < FieldChecker
  def required_fields
    %i[contenu colonne]
  end

  def authorized_fields
    %i[taille texte]
  end

  # Appelé par PublipostageV3 pour chaque ligne/document
  # @dossier et @demarche sont déjà assignés par init_calculs()
  def process_row(_row, fields)
    # Construire le contenu du QR code avec instanciate (méthode héritée de FieldChecker)
    # Supporte les préfixes, ternaires, et accès aux champs du dossier
    contenu = instanciate(@params[:contenu], fields)
    return if contenu.blank?

    # Taille du QR code (300px par défaut)
    taille = @params[:taille] || 300

    # Texte du lien hypertexte (optionnel)
    texte = @params[:texte] || 'Cliquez ici'

    # Créer un objet QrcodeField (API cohérente avec PieceJustificativeFile)
    colonne = @params[:colonne]
    fields[colonne] = QrcodeField.new(contenu, size: taille, texte: texte)
  end
end
