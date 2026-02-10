# frozen_string_literal: true

# Cache pour les QR codes générés.
# Utilise PieceJustificativeCache.get_or_generate() pour la gestion du cache.
#
# Exemple :
#   filepath = QrcodeCache.get("https://example.com", size: 300)
#
class QrcodeCache
  class << self
    def get(data, size: 300)
      # Checksum basé sur les DONNÉES (pas le fichier)
      checksum = Digest::SHA256.hexdigest("#{data}-#{size}")

      # Utilise le cache partagé avec gestion automatique de l'espace
      PieceJustificativeCache.get_or_generate('qrcode.png', checksum) do
        # Générer le QR code seulement si absent du cache
        qrcode = RQRCode::QRCode.new(data)
        qrcode.as_png(size: size).to_s
      end
    end
  end
end
