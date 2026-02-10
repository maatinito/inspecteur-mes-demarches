# frozen_string_literal: true

require 'sablon'

# Wrapper pour les QR codes utilisé par Sablon dans PublipostageV3.
# Permet un accès lazy aux images QR code et à l'URL encodée.
#
# Exemples d'utilisation dans les templates Sablon :
#
# Image QR code :
#   «@qrcode.image:start»[placeholder image]«@qrcode.image:end»
#
# URL encodée dans le QR code :
#   Lien : «=qrcode.url»
#
# Combiné :
#   «@qrcode.image:start»[img]«@qrcode.image:end»
#   Scannez ce code ou utilisez : «=qrcode.url»
#
# Conditionnel :
#   «qrcode:if(present?)»
#     «@qrcode.image:start»[img]«@qrcode.image:end»
#   «qrcode:endIf»
#
class QrcodeField
  attr_reader :data, :url

  def initialize(data, size: 300, texte: nil)
    @data = data
    @url = data # L'URL/texte encodé dans le QR code
    @size = size
    @texte = texte # Texte personnalisé pour le lien HTML
  end

  # IMAGES : Lazy loading de l'image QR code (comme PieceJustificativeFile#image)
  # Retourne un objet Sablon.content(:image) pour insertion dans le document
  def image
    return @image if defined?(@image)

    # Génère ou récupère depuis le cache
    filepath = QrcodeCache.get(@data, size: @size)
    @image = Sablon.content(:image, filepath)
  end

  # LIENS : URL/texte encodé dans le QR code
  def link
    @url
  end
  alias lien link

  # LIEN HTML : Retourne un lien hypertexte cliquable pour Sablon
  # Utilisation dans template : «=qrcode.lien_html»
  # Le texte peut être défini dans la config YAML ou utilise le défaut
  def lien_html
    texte = @texte || 'Cliquez ici'
    html = %(<a href="#{@url}">#{texte}</a>)
    Sablon.content(:html, html)
  end
  alias html_link lien_html

  # PRÉDICATS : Est-ce que le QR code est présent ?
  def present?
    @data.present?
  end

  # Pour la sérialisation JSON dans same_document
  # On stocke uniquement les données stables (pas l'image générée)
  def as_json(*)
    {
      '_qrcode' => true,
      'data' => @data,
      'size' => @size
    }
  end

  # Pour l'affichage direct (si utilisé comme string)
  def to_s
    @data
  end
end
