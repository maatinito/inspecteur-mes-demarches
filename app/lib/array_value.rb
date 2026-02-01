# frozen_string_literal: true

# Wrapper pour les tableaux de valeurs simples utilisé par Sablon dans PublipostageV3.
# Permet d'utiliser un tableau soit en boucle, soit comme string joinée.
#
# Exemples d'utilisation dans les templates Sablon :
#
# Affichage direct (to_s appelé automatiquement) :
#   «=copropriétaires»  → "Dupont, Martin, Durand"
#
# Boucle sur les valeurs :
#   «copropriétaires:each(nom)»
#     - «=nom»
#   «copropriétaires:endEach»
#   → - Dupont
#     - Martin
#     - Durand
#
# Avec alias français :
#   «=copropriétaires.texte»  → "Dupont, Martin, Durand"
#
class ArrayValue
  include Enumerable

  def initialize(array)
    @array = array
  end

  # Permet les boucles Sablon : «valeurs:each(v)»...«valeurs:endEach»
  def each(&)
    @array.each(&)
  end

  # Affichage direct : «=valeurs» → "val1, val2, val3"
  def to_s
    @array.map(&:to_s).join(', ')
  end
  alias texte to_s

  # Nombre d'éléments
  def size
    @array.size
  end
  alias taille size

  # Premier élément
  def first
    @array.first
  end
  alias premier first

  # Dernier élément
  def last
    @array.last
  end
  alias dernier last

  # Pour les prédicats Sablon : «valeurs:if(present?)»
  def present?
    @array.present?
  end

  def empty?
    @array.empty?
  end
  alias vide? empty?

  # Accès par index (pour compatibilité)
  def [](index)
    @array[index]
  end
end
