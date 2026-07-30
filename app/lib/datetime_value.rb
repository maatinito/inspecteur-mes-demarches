# frozen_string_literal: true

# Pendant de `DateValue` pour les champs date-heure.
#
# Hérite de `DateTime` et **pas** de `Time` : `Time#to_a` existe, donc un splat
# (`[*value]`, utilisé par `Publipostage#generate_docx`) exploserait la valeur en
# dix éléments. `DateTime` est une sous-classe de `Date` et n'a pas de `to_a`.
class DatetimeValue < DateTime
  def to_s
    strftime('%d/%m/%Y à %Hh%M')
  end

  # Date seule, sans l'heure. Utilisable telle quelle dans un template Sablon
  # («=mon_champ.date») ou dans un plugin. Renvoie un `DateValue` et non un
  # `Date` nu, pour que l'affichage reste au format français.
  def date
    DateValue.new(year, month, day)
  end

  # Ramené au fuseau de l'application (Pacific/Tahiti) : l'heure affichée ne doit
  # pas dépendre du décalage avec lequel l'API a sérialisé la valeur.
  #
  # `Time.zone.parse` rend `nil` (au lieu de lever) sur une valeur illisible ;
  # on convertit ce cas en `Date::Error` pour que `FieldChecker#typed_date_value`
  # continue de l'intercepter et de rendre '' sans jamais lever.
  def self.from_iso(iso)
    parsed = Time.zone.parse(iso)
    raise Date::Error, "date illisible : #{iso.inspect}" if parsed.nil?

    iso8601(parsed.iso8601)
  end
end
