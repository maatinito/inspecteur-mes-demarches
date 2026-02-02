# frozen_string_literal: true

# Génère un identifiant unique sécurisé et le stocke dans un champ texte.
#
# Utilise UUID v7 par défaut, un standard moderne qui combine:
# - Un timestamp (48 bits) pour le tri chronologique
# - Des bits aléatoires (74 bits effectifs) pour l'unicité et la sécurité
#
# Caractéristiques:
# - Triable chronologiquement
# - Sécurisé contre l'énumération (2^74 possibilités par milliseconde)
# - Standard UUID (RFC 9562)
# - Compatible URL et base de données
# - 32 caractères (format compact sans tirets)
#
# Configuration YAML:
#
#   when_ok:
#     - generate_id:
#         champ: "Identifiant unique"
#         timestamp_field: "date_depot"  # optionnel
#
# Paramètres:
# - champ: Nom du champ texte destination (annotation privée)
# - timestamp_field: (optionnel) Nom d'un champ du dossier contenant un timestamp
#                    Si fourni, l'UUID sera basé sur ce timestamp
#                    Si absent, utilise Time.now
#
# Comportement:
# - Génère l'ID uniquement si le champ destination est vide
# - Ne modifie jamais un ID existant (idempotent)
# - Log l'opération pour audit
#
# Exemples d'utilisation:
#
#   # ID basé sur l'heure actuelle
#   - generate_id:
#       champ: "Identifiant du permis"
#
#   # ID basé sur la date de dépôt (pour tri chronologique précis)
#   - generate_id:
#       champ: "Identifiant du permis"
#       timestamp_field: "date_depot"
#
# Format de sortie:
#   018d3b8a01234567abcdef0123456789 (32 caractères hexadécimaux)
#
class GenerateId < FieldChecker
  def version
    super + 1
  end

  def required_fields
    super + %i[champ]
  end

  def authorized_fields
    super + %i[timestamp_field]
  end

  def process(demarche, dossier)
    super
    return unless must_check?(dossier)

    generate_id_if_needed
  end

  private

  def generate_id_if_needed
    # Récupérer le champ destination (annotation privée)
    annotation = param_annotation(:champ, warn_if_empty: true)
    unless annotation
      Rails.logger.warn("Annotation '#{@params[:champ]}' introuvable sur le dossier #{@dossier.number}")
      return
    end

    # Vérifier si le champ est vide
    current_value = SetAnnotationValue.value_of(annotation)
    if current_value.present?
      Rails.logger.debug("ID déjà présent dans '#{annotation.label}' (#{current_value}), pas de régénération")
      return
    end

    # Générer l'ID
    id_value = generate_id_with_timestamp
    Rails.logger.info("Génération ID #{id_value} pour le dossier #{@dossier.number}")

    # Stocker dans l'annotation
    SetAnnotationValue.raw_set_value(
      @dossier.id,
      instructeur_id,
      annotation.id,
      id_value
    )

    dossier_updated(@dossier)
  rescue StandardError => e
    Rails.logger.error("Erreur lors de la génération de l'ID pour le dossier #{@dossier.number}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
  end

  def generate_id_with_timestamp
    timestamp = extract_timestamp || Time.now

    # Générer UUID v7 avec timestamp personnalisé
    # Ruby 3.3+ supporte uuid_v7 nativement
    uuid = if SecureRandom.respond_to?(:uuid_v7)
             # Ruby 3.3+ : utiliser la méthode native
             generate_uuid_v7_native(timestamp)
           else
             # Fallback pour Ruby < 3.3
             generate_uuid_v7_fallback(timestamp)
           end

    # Retourner sans tirets (format compact 32 caractères)
    uuid.delete('-')
  end

  def generate_uuid_v7_native(timestamp)
    # UUID v7 avec timestamp custom (Ruby 3.3+)
    # Note: SecureRandom.uuid_v7 ne supporte pas encore le timestamp custom
    # On génère donc manuellement
    generate_uuid_v7_manual(timestamp)
  end

  def generate_uuid_v7_fallback(timestamp)
    # Implémentation manuelle pour compatibilité
    generate_uuid_v7_manual(timestamp)
  end

  def generate_uuid_v7_manual(timestamp)
    # Structure UUID v7:
    # - 48 bits: timestamp (millisecondes depuis epoch)
    # - 12 bits: random
    # -  4 bits: version (0111)
    # -  2 bits: variant (10)
    # - 62 bits: random

    timestamp_ms = (timestamp.to_f * 1000).to_i

    # 48 bits timestamp
    time_high = (timestamp_ms >> 16) & 0xffffffff
    time_low = timestamp_ms & 0xffff

    # 12 bits random + 4 bits version (0111 = 7)
    rand_a = SecureRandom.random_number(0x1000) | 0x7000

    # 2 bits variant (10) + 62 bits random
    rand_b = SecureRandom.random_number(0x4000_0000_0000_0000) | 0x8000_0000_0000_0000

    # Format UUID
    # rubocop:disable Style/FormatStringToken
    format(
      '%08x-%04x-%04x-%04x-%012x',
      time_high,
      time_low,
      rand_a,
      (rand_b >> 48) & 0xffff,
      rand_b & 0xffffffffffff
    )
    # rubocop:enable Style/FormatStringToken
  end

  def extract_timestamp
    return nil unless @params[:timestamp_field]

    # Extraire la valeur du champ timestamp depuis le dossier
    field_name = @params[:timestamp_field]
    timestamp_value = object_field_values(@dossier, field_name, log_empty: false).first

    return nil unless timestamp_value

    # Convertir en Time si nécessaire
    case timestamp_value
    when Time, DateTime, Date
      timestamp_value.to_time
    when String
      # Essayer de parser la date ISO8601
      begin
        DateTime.iso8601(timestamp_value).to_time
      rescue ArgumentError
        Rails.logger.warn("Impossible de parser le timestamp '#{timestamp_value}' du champ '#{field_name}'")
        nil
      end
    else
      Rails.logger.warn("Type de timestamp non supporté: #{timestamp_value.class} (valeur: #{timestamp_value})")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("Erreur lors de l'extraction du timestamp du champ '#{field_name}': #{e.message}")
    nil
  end
end
