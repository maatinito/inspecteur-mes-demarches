# frozen_string_literal: true

module Tools
  class DiskFileManager
    attr_reader :root_path, :yaml_cache

    def initialize(root_path)
      @root_path = root_path
      @yaml_cache = {} # Stockage en mémoire : { filename => { content:, last_modified: } }
    end

    # Méthode principale pour les configurations YAML
    def configurations
      files = Dir.glob(Rails.root.join(@root_path, 'configurations', '*.yml'))
      files.each do |file_key|
        last_modified = File.mtime(file_key)
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
      filename = Rails.root.join(@root_path, 'models', relative_path)
      return filename if File.exist?(filename)

      raise "Le fichier #{filename} n'existe pas."
    end

    private

    # Charge le contenu YAML d'un fichier depuis S3
    def load_yaml(file_key)
      YAML.load_file(file_key, aliases: true)
    rescue Psych::SyntaxError => e
      Rails.logger.error("Erreur YAML dans le fichier #{file_key}: #{e.message}")
      {}
    end
  end
end
