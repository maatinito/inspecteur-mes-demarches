# frozen_string_literal: true

# Wrapper pour les valeurs booléennes utilisé par Sablon dans PublipostageV3.
# Permet à la fois d'évaluer une condition (`:if(present?)`) et d'afficher
# un libellé français (`Oui`/`Non`) lors d'une substitution directe (`=champ`).
#
# Exemples d'utilisation dans les templates Sablon :
#
#   «=accord»                    → "Oui" ou "Non"
#   «accord:if(present?)»…       → bloc rendu si la case est cochée
#   «accord:if(bool?)»…          → idem (alias sémantique)
#
# Les méthodes `true?` / `false?` sont fournies pour permettre des prédicats
# Sablon plus explicites si besoin.
class BooleanValue
  def initialize(value)
    @value = value ? true : false
  end

  def to_s
    @value ? 'Oui' : 'Non'
  end
  alias texte to_s

  # Sablon `:if(present?)` : vrai uniquement si la valeur est true.
  def present?
    @value
  end

  def empty?
    !@value
  end
  alias vide? empty?

  def true?
    @value
  end
  alias vrai? true?

  def false?
    !@value
  end
  alias faux? false?

  def ==(other)
    case other
    when BooleanValue then @value == other.instance_variable_get(:@value)
    when TrueClass, FalseClass then @value == other
    else false
    end
  end

  def to_bool
    @value
  end
end
