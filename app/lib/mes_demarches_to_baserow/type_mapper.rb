# frozen_string_literal: true

module MesDemarchesToBaserow
  class TypeMapper
    class UnsupportedTypeError < StandardError; end

    TYPE_MAPPINGS = {
      'TextChampDescriptor' => { type: 'text', config: {} }, # Texte court
      'TextareaChampDescriptor' => { type: 'long_text', config: {} }, # Texte long
      'IntegerNumberChampDescriptor' => { type: 'number', config: { number_decimal_places: 0 } },
      'DecimalNumberChampDescriptor' => { type: 'number', config: { number_decimal_places: 2 } },
      'DateChampDescriptor' => { type: 'date', config: { date_format: 'EU', date_include_time: false } },
      'DatetimeChampDescriptor' => { type: 'date', config: { date_format: 'EU', date_include_time: true } },
      'CheckboxChampDescriptor' => { type: 'boolean', config: {} },
      'YesNoChampDescriptor' => { type: 'boolean', config: {} },
      'PhoneChampDescriptor' => { type: 'phone_number', config: {} },
      'EmailChampDescriptor' => { type: 'email', config: {} },
      'VisaChampDescriptor' => { type: 'text', config: {} },
      'DropDownListChampDescriptor' => { type: 'single_select', config: {} },
      'MultipleDropDownListChampDescriptor' => { type: 'multiple_select', config: {} },
      'CiviliteChampDescriptor' => { type: 'single_select', config: {} },
      'PieceJustificativeChampDescriptor' => { type: 'file', config: {} }
    }.freeze

    # Types qui n'ont jamais de valeurs et doivent être ignorés
    IGNORED_TYPES = %w[
      ExplicationChampDescriptor
      HeaderSectionChampDescriptor
    ].freeze

    UNSUPPORTED_TYPES = %w[
      RepetitionChampDescriptor
      SiretChampDescriptor
      NumeroDnChampDescriptor
      LinkedDropDownListChampDescriptor
      ReferentielDePolynesieChampDescriptor
      CommuneDePolynesieChampDescriptor
      CodePostalDePolynesieChampDescriptor
      DossierLinkChampDescriptor
    ].freeze

    def self.map_field_type(mes_demarches_type, field_descriptor = {})
      new.map_field_type(mes_demarches_type, field_descriptor)
    end

    def self.supported_type?(mes_demarches_type)
      TYPE_MAPPINGS.key?(mes_demarches_type)
    end

    def self.should_ignore_type?(mes_demarches_type)
      IGNORED_TYPES.include?(mes_demarches_type)
    end

    def map_field_type(mes_demarches_type, field_descriptor = {})
      raise UnsupportedTypeError, "Type non supporté: #{mes_demarches_type}" unless self.class.supported_type?(mes_demarches_type)

      mapping = TYPE_MAPPINGS[mes_demarches_type].dup

      case mes_demarches_type
      when 'DropDownListChampDescriptor', 'MultipleDropDownListChampDescriptor'
        mapping[:config] = build_select_options(field_descriptor)
      when 'CiviliteChampDescriptor'
        mapping[:config] = build_civilite_options
      end

      mapping
    end

    def generate_field_name(label, prefix = nil)
      base_name = clean_label(label)
      prefix ? "#{prefix} - #{base_name}" : base_name
    end

    private

    def build_select_options(field_descriptor)
      options = field_descriptor['options'] || []

      select_options = options.map.with_index do |option, index|
        {
          value: option,
          color: default_colors[index % default_colors.length]
        }
      end

      { select_options: select_options }
    end

    def build_civilite_options
      {
        select_options: [
          { value: 'M.', color: 'blue' },
          { value: 'Mme', color: 'purple' }
        ]
      }
    end

    def default_colors
      %w[blue green red yellow orange purple pink light-blue light-green light-red]
    end

    def clean_label(label)
      label.to_s.strip.gsub(/\s+/, ' ')
    end

    def sanitize_name(name)
      name.to_s
          .gsub(/[àâä]/, 'a')
          .gsub(/[éèêë]/, 'e')
          .gsub(/[îï]/, 'i')
          .gsub(/[ôö]/, 'o')
          .gsub(/[ùûü]/, 'u')
          .gsub(/ç/, 'c')
          .gsub(/[^a-zA-Z0-9\s_-]/, '')
          .strip
          .gsub(/\s+/, '_')
          .downcase
    end
  end
end
