# frozen_string_literal: true

require 'typhoeus'
require 'tempfile'

module Baserow
  # Gère le téléchargement et l'upload de fichiers vers Baserow via multipart/form-data
  # Nécessaire car Baserow ne peut pas accéder aux URLs S3 de Mes-Démarches
  # (advocate bloque les adresses locales et les proxies)
  class FileUploader
    attr_reader :base_url, :token

    def initialize(token_config = nil)
      @base_url = ENV.fetch('BASEROW_URL', 'https://baserow.mes-demarches.gov.pf')
      @token = TokenManager.get_token(token_config)
    end

    # Télécharge un fichier depuis une URL et l'uploade vers Baserow
    # @param url [String] URL du fichier à télécharger
    # @param visible_name [String] Nom du fichier à afficher dans Baserow
    # @return [Hash] { name: "hash...", visible_name: "..." } ou nil en cas d'erreur
    def download_and_upload(url, visible_name)
      Rails.logger.info "FileUploader: Téléchargement de #{visible_name} depuis #{url[0..100]}..."

      # 1. Télécharger le fichier depuis Mes-Démarches
      tempfile = download_file(url, visible_name)
      return nil unless tempfile

      # 2. Uploader vers Baserow via multipart/form-data
      result = upload_to_baserow(tempfile, visible_name)

      result
    ensure
      # Nettoyer le fichier temporaire
      tempfile&.close
      tempfile&.unlink
    end

    private

    # Télécharge un fichier depuis une URL vers un fichier temporaire
    # @param url [String] URL du fichier
    # @param filename [String] Nom du fichier (pour l'extension)
    # @return [Tempfile, nil] Fichier temporaire ou nil en cas d'erreur
    def download_file(url, filename)
      # Extraire l'extension du fichier
      extension = File.extname(filename)

      # Créer un fichier temporaire
      tempfile = Tempfile.new(['baserow_upload', extension])
      tempfile.binmode

      # Télécharger le fichier
      response = Typhoeus.get(
        url,
        followlocation: true,
        maxredirs: 3,
        timeout: 60
      )

      unless response.success?
        Rails.logger.error "FileUploader: Erreur téléchargement #{filename}: #{response.code}"
        tempfile.close
        tempfile.unlink
        return nil
      end

      # Écrire le contenu dans le fichier temporaire
      tempfile.write(response.body)
      tempfile.rewind

      Rails.logger.debug "FileUploader: #{filename} téléchargé (#{response.body.bytesize} octets)"
      tempfile
    rescue StandardError => e
      Rails.logger.error "FileUploader: Erreur téléchargement #{filename}: #{e.message}"
      tempfile&.close
      tempfile&.unlink
      nil
    end

    # Uploade un fichier vers Baserow via multipart/form-data
    # @param file [File, Tempfile] Fichier à uploader
    # @param visible_name [String] Nom à afficher dans Baserow
    # @return [Hash, nil] { name: "hash...", visible_name: "..." } ou nil
    def upload_to_baserow(file, visible_name)
      url = "#{@base_url}/api/user-files/upload-file/"
      response = Typhoeus.post(url, headers: { 'Authorization' => "Token #{@token}" }, body: { file: File.open(file.path, 'rb') })

      return handle_upload_error(response, visible_name) unless response.success?

      build_file_response(response, visible_name)
    rescue StandardError => e
      Rails.logger.error "FileUploader: Erreur upload #{visible_name}: #{e.message}"
      nil
    end

    def handle_upload_error(response, visible_name)
      error = begin
        JSON.parse(response.body)
      rescue StandardError
        { 'error' => response.body }
      end
      Rails.logger.error "FileUploader: Erreur upload #{visible_name}: #{error}"
      nil
    end

    def build_file_response(response, visible_name)
      result = JSON.parse(response.body)
      Rails.logger.info "FileUploader: #{visible_name} uploadé avec succès (name: #{result['name']})"

      { 'name' => result['name'], 'visible_name' => visible_name }
    end
  end
end
