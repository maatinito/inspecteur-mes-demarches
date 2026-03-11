# frozen_string_literal: true

require 'typhoeus'
require 'tempfile'

module Grist
  # Gère le téléchargement et l'upload de fichiers vers Grist
  # Download depuis S3 (Mes-Démarches) + upload vers Grist attachments
  # L'appelant formate ensuite en ["L", attachment_id] pour le champ Attachments
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

      tempfile = download_file(url, visible_name)
      return nil unless tempfile

      upload_to_grist(tempfile, visible_name)
    ensure
      tempfile&.close
      tempfile&.unlink
    end

    private

    def download_file(url, filename)
      extension = File.extname(filename)
      tempfile = Tempfile.new(['grist_upload', extension])
      tempfile.binmode

      response = Typhoeus.get(
        url,
        followlocation: true,
        maxredirs: 3,
        timeout: 60
      )

      unless response.success?
        Rails.logger.error "GristFileUploader: Erreur téléchargement #{filename}: #{response.code}"
        tempfile.close
        tempfile.unlink
        return nil
      end

      tempfile.write(response.body)
      tempfile.rewind

      Rails.logger.debug "GristFileUploader: #{filename} téléchargé (#{response.body.bytesize} octets)"
      tempfile
    rescue StandardError => e
      Rails.logger.error "GristFileUploader: Erreur téléchargement #{filename}: #{e.message}"
      tempfile&.close
      tempfile&.unlink
      nil
    end

    # Upload vers Grist et retourne l'attachment_id
    def upload_to_grist(file, visible_name)
      result = @client.upload_attachment(@doc_id, file.path, visible_name)

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
