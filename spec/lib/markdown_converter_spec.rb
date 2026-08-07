# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarkdownConverter do
  describe '.looks_like_markdown?' do
    context 'emphase appariée' do
      it 'détecte le gras à double astérisque' do
        expect(described_class.looks_like_markdown?('**gras**')).to be true
      end

      it 'détecte le gras à double underscore' do
        expect(described_class.looks_like_markdown?('__gras__')).to be true
      end

      it 'détecte l\'italique à astérisque simple' do
        expect(described_class.looks_like_markdown?('*italique*')).to be true
      end

      it 'détecte l\'italique à underscore simple' do
        expect(described_class.looks_like_markdown?('_italique_')).to be true
      end

      it 'détecte un nom latin en italique au milieu d\'une phrase' do
        expect(described_class.looks_like_markdown?('la vanille *Vanilla tahitensis* est cultivée')).to be true
      end

      it 'détecte une emphase sur un seul caractère' do
        expect(described_class.looks_like_markdown?('note *a* du tableau')).to be true
      end

      it 'détecte une emphase parmi plusieurs lignes de texte brut' do
        expect(described_class.looks_like_markdown?("Première ligne\nDeuxième **importante**\nTroisième")).to be true
      end
    end

    context 'délimiteurs non appariés ou isolés' do
      it 'ignore un astérisque seul' do
        expect(described_class.looks_like_markdown?('un * seul')).to be false
      end

      it 'ignore un double astérisque isolé' do
        expect(described_class.looks_like_markdown?('renvoi ** voir annexe')).to be false
      end

      it 'ignore une emphase dont l\'ouvrant est suivi d\'une espace' do
        expect(described_class.looks_like_markdown?('3 * 4 * 5')).to be false
      end

      it 'ignore des délimiteurs appariés à cheval sur deux lignes' do
        expect(described_class.looks_like_markdown?("montant * 2\ntotal * 3")).to be false
      end
    end

    context 'underscores intra-mot (non-régression : faux positifs)' do
      it 'ignore un identifiant snake_case' do
        expect(described_class.looks_like_markdown?('param_field_value')).to be false
      end

      it 'ignore un nom de fichier' do
        expect(described_class.looks_like_markdown?('mon_fichier_test.pdf')).to be false
      end

      it 'ignore une URL contenant des underscores' do
        expect(described_class.looks_like_markdown?('https://ex.pf/a_b_c/d_e')).to be false
      end

      it 'ignore des underscores intra-mot accentués' do
        expect(described_class.looks_like_markdown?('société_test_polynésie')).to be false
      end
    end

    context 'formules arithmétiques' do
      it 'ignore une multiplication espacée' do
        expect(described_class.looks_like_markdown?('x = 2 * y * f')).to be false
      end

      it 'ignore une multiplication entre nombres' do
        expect(described_class.looks_like_markdown?('10*10')).to be false
      end

      # Limite assumée : kramdown interprète lui aussi « 2*y*f » comme de
      # l'italique. Le détecteur reste cohérent avec le convertisseur.
      it 'détecte (à tort mais conformément à Markdown) une multiplication collée entre lettres' do
        expect(described_class.looks_like_markdown?('x = 2*y*f')).to be true
      end
    end

    context 'autres blocs Markdown' do
      it 'détecte un lien' do
        expect(described_class.looks_like_markdown?('voir [le site](https://ex.pf)')).to be true
      end

      it 'détecte un titre' do
        expect(described_class.looks_like_markdown?("## Titre\ncontenu")).to be true
      end

      it 'détecte une liste à tirets' do
        expect(described_class.looks_like_markdown?("- premier\n- second")).to be true
      end

      it 'détecte une liste à astérisques' do
        expect(described_class.looks_like_markdown?("* premier\n* second")).to be true
      end

      it 'détecte une citation' do
        expect(described_class.looks_like_markdown?('> citation')).to be true
      end
    end

    context 'entrées neutres' do
      it 'ignore du texte simple' do
        expect(described_class.looks_like_markdown?('Texte simple')).to be false
      end

      it 'ignore une chaîne vide' do
        expect(described_class.looks_like_markdown?('')).to be false
      end

      it 'ignore nil' do
        expect(described_class.looks_like_markdown?(nil)).to be false
      end

      it 'ignore une valeur non textuelle' do
        expect(described_class.looks_like_markdown?(42)).to be false
      end
    end

    context 'cohérence avec le convertisseur' do
      # Le détecteur ne doit pas déclencher une conversion qui ne produirait
      # aucun formatage : sinon la valeur est inutilement transformée en bloc
      # HTML par Sablon.
      neutres = ['Texte simple', 'param_field_value', 'mon_fichier_test.pdf',
                 'https://ex.pf/a_b_c/d_e', 'x = 2 * y * f', '10*10', 'un * seul']

      neutres.each do |texte|
        it "ne détecte pas #{texte.inspect}, que kramdown ne formaterait pas" do
          expect(described_class.looks_like_markdown?(texte)).to be false
          expect(described_class.convert(texte)).not_to match(/<(strong|em|del)>/)
        end
      end
    end
  end

  describe '.convert' do
    it 'convertit le gras en <strong>' do
      expect(described_class.convert('**Important**')).to include('<strong>Important</strong>')
    end

    it 'convertit l\'italique en <em>' do
      expect(described_class.convert('*Vanilla tahitensis*')).to include('<em>Vanilla tahitensis</em>')
    end

    it 'retourne une chaîne vide telle quelle' do
      expect(described_class.convert('')).to eq('')
    end

    it 'retourne une valeur non textuelle telle quelle' do
      expect(described_class.convert(42)).to eq(42)
    end

    it 'supprime les balises dangereuses' do
      html = described_class.convert('**gras** <script>alert(1)</script>')
      expect(html).to include('<strong>gras</strong>')
      expect(html).not_to include('script')
    end

    it 'sépare un titre collé au texte précédent' do
      html = described_class.convert("- item\n## Titre")
      expect(html).to match(%r{<h2>Titre</h2>})
    end
  end

  # Les listes deviennent des paragraphes indentés portant le marqueur écrit
  # par l'auteur : Word ne doit ni renuméroter, ni imposer ses propres puces.
  describe '.convert, listes' do
    it 'ne produit plus aucune liste HTML' do
      html = described_class.convert("1. un\n2. deux")
      expect(html).not_to include('<ol', '<ul', '<li')
    end

    it 'conserve la numérotation écrite à la main' do
      html = described_class.convert("3. troisième\n4. quatrième")
      expect(html).to include('>3. troisième<', '>4. quatrième<')
    end

    it 'conserve les marqueurs inconnus de Markdown' do
      html = described_class.convert("1. Condition :\n   1a. cas A\n   1b. cas B")
      expect(html).to include('>1a. cas A<', '>1b. cas B<')
    end

    it 'indente selon la profondeur, quelle que soit la largeur d\'indentation' do
      html = described_class.convert("1. un\n   - deux\n      • trois")
      expect(html).to include('margin-left: 18pt">1. un',
                              'margin-left: 36pt">- deux',
                              'margin-left: 54pt">• trois')
    end

    it 'traite un <ul> imbriqué dans un <ol> comme deux niveaux' do
      html = described_class.convert("1. Une des conditions :\n   - puce a\n   - puce b")
      expect(html).to include('margin-left: 18pt">1. Une des conditions :',
                              'margin-left: 36pt">- puce a',
                              'margin-left: 36pt">- puce b')
    end

    it 'conserve le gras à l\'intérieur d\'un item' do
      html = described_class.convert('- **OU** semences certifiées')
      expect(html).to include('<strong>OU</strong> semences certifiées')
    end

    it 'laisse les titres au parseur Markdown' do
      html = described_class.convert("- item\n## Titre\ntexte après")
      expect(html).to include('margin-left: 18pt">- item', '<h2>Titre</h2>')
    end

    it 'aplatit aussi les listes venues de HTML brut' do
      html = described_class.convert('<ol><li>A<ul><li>a1</li></ul></li></ol> et du **gras**')
      expect(html).not_to include('<ol', '<ul', '<li')
      expect(html).to include('margin-left: 18pt">1. A', 'margin-left: 36pt">- a1')
    end

    it 'réunit les paragraphes multiples d\'un item sans imbriquer de bloc' do
      html = described_class.convert('<ol><li><p>Premier</p><p>Second</p></li></ol>')
      expect(html).to include('>1. Premier<br>Second<')
      expect(html).not_to match(/<p[^>]*>[^<]*<p/)
    end

    it 'assainit le contenu d\'un item' do
      html = described_class.convert("- <script>alert(1)</script> suite\n- b")
      expect(html).not_to include('script')
    end

    it 'ne laisse jamais un bloc à l\'intérieur d\'un paragraphe de liste' do
      html = described_class.convert("- ligne\n\n<blockquote><p>bloc</p></blockquote>")
      expect(html).not_to match(%r{<p[^>]*>(?:(?!</p>).)*<(?:p|div|blockquote|ul|ol)[\s>]}m)
    end
  end
end
