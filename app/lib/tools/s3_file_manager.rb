# frozen_string_literal: true

module Tools
  class S3FileManager
    attr_reader :s3_client, :bucket_name, :yaml_cache

    def initialize(bucket_name, access_key_id:, secret_access_key:, endpoint:, region: 'us-east-1')
      @s3_client = Aws::S3::Client.new(
        access_key_id:,
        secret_access_key:,
        endpoint:,
        region:,
        force_path_style: true
      )
      @bucket_name = bucket_name
      @yaml_cache = {} # Stockage en mémoire : { filename => { content:, last_modified: } }
    end

    # Méthode principale pour les configurations YAML
    def configurations
      files = []
      s3_client.list_objects_v2(bucket: bucket_name, prefix: 'configurations/', delimiter: '/').contents.each do |object|
        next unless object.key.end_with?('.yml') # Ignorer les fichiers non YAML

        file_key = object.key
        last_modified = object.last_modified
        files << file_key

        next unless yaml_cache[file_key]&.dig(:last_modified) != last_modified

        # Fichier mis à jour ou nouvellement ajouté
        yaml_cache[file_key] = {
          content: load_yaml(file_key),
          last_modified:
        }
      end

      # Retirer les fichiers supprimés du cache
      (yaml_cache.keys - files).each { |key| yaml_cache.delete(key) }

      yaml_cache.transform_values { |v| v[:content] }
    end

    # Lire un fichier Word (ou tout autre fichier) dans `robot/models`
    def filepath(relative_path)
      file_key = "models/#{relative_path.sub('storage/', '')}"
      cache_file_path = "tmp/#{relative_path.gsub('/', '_')}" # Chemin temporaire basé sur le nom relatif

      begin
        # Obtenir les métadonnées du fichier dans S3
        object_head = s3_client.head_object(bucket: bucket_name, key: file_key)
        last_modified = object_head.last_modified

        # Télécharger le fichier si :
        # 1. Il n'existe pas localement
        # 2. Il a été modifié depuis la dernière lecture
        if !File.exist?(cache_file_path) || File.mtime(cache_file_path) < last_modified
          object = s3_client.get_object(bucket: bucket_name, key: file_key)
          FileUtils.mkdir_p(File.dirname(cache_file_path)) # Créer les répertoires si nécessaire
          File.write(cache_file_path, object.body.read)

          # Met à jour l'horodatage du fichier pour refléter la dernière modification dans S3
          File.utime(last_modified, last_modified, cache_file_path)
        end

        cache_file_path
      rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound => e
        Rails.logger.error("Unable to find #{file_key} in #{bucket_name}")
        raise e
      end
    end

    private

    # Charge le contenu YAML d'un fichier depuis S3
    def load_yaml(file_key)
      object = s3_client.get_object(bucket: bucket_name, key: file_key)
      YAML.safe_load(object.body.read, aliases: true)
    rescue Psych::SyntaxError => e
      Rails.logger.error("Erreur YAML dans le fichier #{file_key}: #{e.message}")
      {}
    end
  end
end
