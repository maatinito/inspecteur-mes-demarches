# frozen_string_literal: true

module SchemaBuilders
  # Mappe les types de champs Mes-Démarches vers les types natifs d'une cible
  # (Baserow ou Grist). Consolide MesDemarchesToBaserow::TypeMapper et
  # MesDemarchesToGrist::TypeMapper.
  #
  # Usage:
  #   mapper = SchemaBuilders::TypeMapper.for(:baserow)
  #   mapper.call('TextChampDescriptor')       # => 'text'
  #   mapper.map_field_type('DateChampDescriptor')
  #   # => { type: 'date', config: { date_format: 'EU', date_include_time: false } }
  #
  #   mapper = SchemaBuilders::TypeMapper.for(:grist)
  #   mapper.call('TextChampDescriptor')       # => 'Text'
  #
  # Cibles inconnues lèvent ArgumentError.
  # Types Mes-Démarches inconnus lèvent UnsupportedTypeError (comportement
  # identique aux mappers d'origine).
  class TypeMapper
    class UnsupportedTypeError < StandardError; end

    # --- Tables de mapping (copiées à l'identique des mappers d'origine) ---

    BASEROW_MAPPINGS = {
      'TextChampDescriptor' => { type: 'text', config: {} },
      'TextareaChampDescriptor' => { type: 'long_text', config: {} },
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

    GRIST_MAPPINGS = {
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

    # Couleurs Baserow utilisées pour les select_options.
    BASEROW_DEFAULT_COLORS = %w[blue green red yellow orange purple pink light-blue light-green light-red].freeze

    # --- Factory + accesseurs ---

    def self.for(target)
      case target
      when :baserow then new(target: :baserow)
      when :grist   then new(target: :grist)
      else
        raise ArgumentError, "unknown target #{target.inspect}"
      end
    end

    def self.supported_type?(target, mes_demarches_type)
      mappings_for(target).key?(mes_demarches_type)
    end

    def self.should_ignore_type?(mes_demarches_type)
      IGNORED_TYPES.include?(mes_demarches_type)
    end

    def self.mappings_for(target)
      case target
      when :baserow then BASEROW_MAPPINGS
      when :grist   then GRIST_MAPPINGS
      else
        raise ArgumentError, "unknown target #{target.inspect}"
      end
    end

    attr_reader :target

    def initialize(target:)
      @target = target
      @mappings = self.class.mappings_for(target)
    end

    # API minimale demandée : retourne juste le type cible (string).
    def call(mes_demarches_type)
      ensure_supported!(mes_demarches_type)
      @mappings.fetch(mes_demarches_type)[:type]
    end

    def supported_type?(mes_demarches_type)
      @mappings.key?(mes_demarches_type)
    end

    # API complète (compat avec les TypeMappers d'origine) :
    # retourne { type:, config: } et applique les règles spécifiques
    # aux dropdowns / civilité.
    def map_field_type(mes_demarches_type, field_descriptor = {})
      ensure_supported!(mes_demarches_type)

      mapping = @mappings[mes_demarches_type].dup

      case mes_demarches_type
      when 'DropDownListChampDescriptor', 'MultipleDropDownListChampDescriptor'
        if mes_demarches_type == 'DropDownListChampDescriptor' && field_descriptor['otherOption'] == true
          mapping = other_option_mapping
        else
          mapping[:config] = build_select_options(field_descriptor)
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

    def ensure_supported!(mes_demarches_type)
      return if @mappings.key?(mes_demarches_type)

      raise UnsupportedTypeError, "Type non supporté: #{mes_demarches_type}"
    end

    # Mapping de repli quand un DropDownList a "otherOption" : text/Text selon la cible.
    def other_option_mapping
      case @target
      when :baserow then { type: 'text', config: {} }
      when :grist   then { type: 'Text', config: {} }
      end
    end

    def build_select_options(field_descriptor)
      options = field_descriptor['options'] || []

      case @target
      when :baserow
        select_options = options.map.with_index do |option, index|
          {
            value: option,
            color: BASEROW_DEFAULT_COLORS[index % BASEROW_DEFAULT_COLORS.length]
          }
        end
        { select_options: select_options }
      when :grist
        { widgetOptions: { choices: options } }
      end
    end

    def build_civilite_options
      case @target
      when :baserow
        {
          select_options: [
            { value: 'M.', color: 'blue' },
            { value: 'Mme', color: 'purple' }
          ]
        }
      when :grist
        { widgetOptions: { choices: %w[M. Mme] } }
      end
    end

    def clean_label(label)
      label.to_s.strip.gsub(/\s+/, ' ')
    end
  end
end
