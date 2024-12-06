# frozen_string_literal: true

module Tools
  class DossierDataMigration
    attr_reader :base_directory, :batch_size

    def initialize(base_directory, batch_size = 100)
      @base_directory = base_directory
      @batch_size = batch_size
    end

    def migrate_files
      return unless Dir.exist?(base_directory)

      dossiers = Dir.entries(base_directory).select { |entry| File.directory?(File.join(base_directory, entry)) && entry.match?(/^\d+$/) }

      dossiers.each do |dossier|
        dossier_number = dossier.to_i
        dossier_path = File.join(base_directory, dossier)

        yaml_files = Dir.entries(dossier_path).select { |f| f.end_with?('.yml') }

        migrate_dossier(dossier_number, dossier_path, yaml_files)
      end
    end

    private

    def migrate_dossier(dossier_number, dossier_path, yaml_files)
      yaml_files.each_slice(batch_size) do |batch|
        ActiveRecord::Base.transaction do
          batch.each do |file|
            label = File.basename(file, '.yml')
            Rails.logger.info("Migrating #{dossier_number}/#{label}")
            file_path = File.join(dossier_path, file)
            data = YAML.safe_load_file(file_path, permitted_classes: [Symbol]) # Conversion YAML en Ruby hash
            DossierData.find_or_initialize_by(
              dossier: dossier_number,
              label:
            ).update!(data:)
          rescue ActiveRecord::RecordInvalid => e
            puts "Erreur lors du traitement de #{file}: #{e.message}"
          rescue Psych::SyntaxError => e
            puts "Erreur de syntaxe YAML dans #{file}: #{e.message}"
          end
        end
      end
    end
  end
end
