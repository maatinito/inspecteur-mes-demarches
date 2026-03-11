# frozen_string_literal: true

module MesDemarchesToGrist
  class TypeMapper
    class UnsupportedTypeError < StandardError; end

    # Mapping Mes-Démarches → Grist
    # Différences clés avec Baserow :
    # - Text/long_text → Text (Grist n'a pas de long_text)
    # - number → Integer ou Numeric
    # - boolean → Toggle
    # - single_select → Choice (avec widgetOptions.choices)
    # - multiple_select → ChoiceList (avec widgetOptions.choices)
    # - date → Date
    # - file → Attachments
    TYPE_MAPPINGS = {
      'TextChampDescriptor' => { type: 'Text', config: {} },
      'TextareaChampDescriptor' => { type: 'Text', config: {} },
      'IntegerNumberChampDescriptor' => { type: 'Integer', config: {} },
      'DecimalNumberChampDescriptor' => { type: 'Numeric', config: {} },
      'DateChampDescriptor' => { type: 'Date', config: {} },
      'DatetimeChampDescriptor' => { type: 'DateTime:UTC', config: {} },
      'CheckboxChampDescriptor' => { type: 'Bool', config: {} },
      'YesNoChampDescriptor' => { type: 'Bool', config: {} },
      'PhoneChampDescriptor' => { type: 'Text', config: {} },
      'EmailChampDescriptor' => { type: 'Text', config: {} },
      'VisaChampDescriptor' => { type: 'Text', config: {} },
      'DropDownListChampDescriptor' => { type: 'Choice', config: {} },
      'MultipleDropDownListChampDescriptor' => { type: 'ChoiceList', config: {} },
      'CiviliteChampDescriptor' => { type: 'Choice', config: {} },
      'PieceJustificativeChampDescriptor' => { type: 'Attachments', config: {} }
    }.freeze

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
        if mes_demarches_type == 'DropDownListChampDescriptor' && field_descriptor['otherOption'] == true
          mapping = { type: 'Text', config: {} }
        else
          mapping[:config] = build_choice_options(field_descriptor)
        end
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

    # Grist utilise widgetOptions.choices au lieu de select_options
    def build_choice_options(field_descriptor)
      options = field_descriptor['options'] || []
      { widgetOptions: { choices: options } }
    end

    def build_civilite_options
      { widgetOptions: { choices: %w[M. Mme] } }
    end

    def clean_label(label)
      label.to_s.strip.gsub(/\s+/, ' ')
    end
  end
end
