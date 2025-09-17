# frozen_string_literal: true

namespace :demarches do
  desc 'List all fields from demarches referenced in configuration files'
  task :list_fields, [:config_dir] => :environment do |_task, args|
    config_dir = args[:config_dir] || 'config'

    unless Dir.exist?(config_dir)
      puts "Error: Directory '#{config_dir}' does not exist"
      exit 1
    end

    # Collect all unique demarche IDs from YAML files
    demarche_ids = Set.new

    Dir.glob(File.join(config_dir, '**/*.yml')).each do |yaml_file|
        content = YAML.load_file(yaml_file, aliases: true)
        next unless content.is_a?(Hash)

        # Scan all root objects with a 'demarches' attribute
        content.each_value do |value|
          next unless value.is_a?(Hash) && value['demarches']

          demarches = value['demarches']
          demarches = [demarches] unless demarches.is_a?(Array)
          demarches.each { |d| demarche_ids.add(d.to_i) if d }
        end
    rescue StandardError => e
        puts "Warning: Failed to parse #{yaml_file}: #{e.message}"
    end

    if demarche_ids.empty?
      puts "No demarches found in configuration files in #{config_dir}"
      exit 0
    end

    puts "Found #{demarche_ids.size} unique demarches: #{demarche_ids.to_a.sort.join(', ')}"

    # Fetch field definitions from GraphQL API
    results = {}

    demarche_ids.each do |demarche_id|
      print "Fetching fields for demarche #{demarche_id}... "

      begin
        response = MesDemarches.query(
          MesDemarches::Queries::DemarcheRevision,
          variables: { demarche: demarche_id }
        )

        if response.errors&.any?
          puts "ERROR: #{response.errors.map(&:message).join(', ')}"
          next
        end

        demarche = response.data.demarche

        if demarche.nil?
          puts 'NOT FOUND'
          next
        end

        revision = demarche.published_revision

        if revision.nil?
          puts 'NO PUBLISHED REVISION'
          next
        end

        # Extract fields information
        results[demarche_id] = {
          title: demarche.title,
          number: demarche.number,
          revision: {
            id: revision.id,
            date_publication: revision.date_publication
          },
          champs: extract_field_descriptors(revision.champ_descriptors),
          annotations: extract_field_descriptors(revision.annotation_descriptors)
        }

        puts "OK (#{revision.champ_descriptors.size} champs, #{revision.annotation_descriptors.size} annotations)"
      rescue StandardError => e
        puts "ERROR: #{e.message}"
      end
    end

    # Output JSON result
    output_file = "demarches_fields_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(output_file, JSON.pretty_generate(results))
    puts "\nResults saved to: #{output_file}"
  end

  private

  def extract_field_descriptors(descriptors)
    return [] unless descriptors

    descriptors.map do |descriptor|
      field = {
        id: descriptor.id,
        label: descriptor.label,
        description: descriptor.description,
        required: descriptor.required,
        type: descriptor.__typename
      }

      # Handle repetition fields with nested descriptors
      field[:champs] = extract_field_descriptors(descriptor.champ_descriptors) if descriptor.respond_to?(:champ_descriptors) && descriptor.champ_descriptors

      field
    end
  end
end
