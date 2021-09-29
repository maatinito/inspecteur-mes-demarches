# frozen_string_literal: true

class MandatoryFieldCheck < FieldChecker
  def required_fields
    super + %i[champs message]
  end

  def version
    super + 3
  end

  def check(_dossier)
    mandotory_fields = @params[:champs]
    mandotory_fields&.each do |field_name|
      fields = fields(field_name)
      empty = fields.empty? || fields.any? do |field|
        case field.__typename
        when 'PieceJustificativeChamp'
          field.file
        when 'DossierLinkChamp'
          field.string_value
        when 'RepetitionChamp'
          field.champs
        else
          field.value
        end.blank?
      end
      add_message(field_name, 'vide', @params[:message]) if empty
    end
  end
end
