# frozen_string_literal: true

require 'typhoeus'
require 'tmpdir'
require 'fileutils'

module Grist
  # Gère le téléchargement et l'upload de fichiers vers Grist
  # Download depuis S3 (Mes-Démarches) + upload vers Grist attachments
  # L'appelant formate ensuite en ["L", attachment_id] pour le champ Attachments
  #
  # IMPORTANT : Grist déduit le nom stocké de la pièce jointe du basename multipart,
  # qui correspond au basename du fichier on-disk uploadé. On écrit donc le
  # téléchargement sous le vrai nom visible (et non un nom de tempfile aléatoire),
  # faute de quoi la dé-duplication nom+taille de DataExtractor#normalize_files ne
  # matche jamais et chaque synchro ré-uploade le fichier.
  class FileUploader
    def initialize(client, doc_id)
      @client = client
      @doc_id = doc_id
    end

    # Télécharge un fichier depuis une URL et l'uploade vers Grist
    # @param url [String] URL du fichier à télécharger
    # @param visible_name [String] Nom du fichier à afficher
    # @return [Integer, nil] attachment_id ou nil en cas d'erreur
    def download_and_upload(url, visible_name)
      Rails.logger.info "GristFileUploader: Téléchargement de #{visible_name} depuis #{url[0..100]}..."

      dir = Dir.mktmpdir('grist_upload')
      path = File.join(dir, safe_basename(visible_name))
      return nil unless download_file(url, path, visible_name)

      upload_to_grist(path, visible_name)
    ensure
      FileUtils.remove_entry(dir) if dir && Dir.exist?(dir)
    end

    private

    # Nom de fichier sûr pour le système de fichiers : on retire uniquement les
    # séparateurs de chemin (Grist préserve accents/espaces, qu'on garde donc).
    def safe_basename(visible_name)
      name = visible_name.to_s.gsub(%r{[/\\]}, '_').strip
      name.empty? ? 'fichier' : name
    end

    def download_file(url, path, filename)
      response = Typhoeus.get(
        url,
        followlocation: true,
        maxredirs: 3,
        timeout: 60
      )

      unless response.success?
        Rails.logger.error "GristFileUploader: Erreur téléchargement #{filename}: #{response.code}"
        return false
      end

      File.binwrite(path, response.body)

      Rails.logger.debug "GristFileUploader: #{filename} téléchargé (#{response.body.bytesize} octets)"
      true
    rescue StandardError => e
      Rails.logger.error "GristFileUploader: Erreur téléchargement #{filename}: #{e.message}"
      false
    end

    # Upload vers Grist et retourne l'attachment_id
    def upload_to_grist(path, visible_name)
      result = @client.upload_attachment(@doc_id, path, visible_name)

      # Grist retourne un array d'IDs d'attachments
      attachment_ids = result.is_a?(Array) ? result : [result]
      attachment_id = attachment_ids.first

      Rails.logger.info "GristFileUploader: #{visible_name} uploadé avec succès (attachment_id: #{attachment_id})"
      attachment_id
    rescue StandardError => e
      Rails.logger.error "GristFileUploader: Erreur upload #{visible_name}: #{e.message}"
      nil
    end
  end
end
