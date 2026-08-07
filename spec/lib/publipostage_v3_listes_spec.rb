# frozen_string_literal: true

require 'rails_helper'

# Vérifie le WordML réellement produit pour une valeur de colonne de
# référentiel contenant une liste rédigée à la main.
#
# Trois invariants, chacun correspondant à une panne constatée en production :
#   - aucun <w:p> imbriqué : Word refusait d'ouvrir le document ;
#   - aucun <w:numPr> : plus de renumérotation automatique par Word, ni de
#     dépendance à un w:abstractNum lié dans word/numbering.xml ;
#   - un <w:ind> par niveau : la hiérarchie reste lisible sans liste Word.
RSpec.describe 'PublipostageV3 rendu des listes' do
  wordml_ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

  # L'environnement Sablon n'est sollicité que par les listes natives, qui ne
  # sont plus produites : un document nul suffit et prouve l'indépendance
  # vis-à-vis de word/numbering.xml.
  let(:env) { double('Environment', document: nil) }

  before { PublipostageV3.new({}).send(:configure_sablon_for_french_word) }

  define_method(:render) do |markdown|
    html = MarkdownConverter.convert(markdown)
    xml = Sablon::HTMLConverter.new.process(html, env)
    Nokogiri::XML("<root xmlns:w='#{wordml_ns}'>#{xml}</root>")
  end

  define_method(:lines_of) do |doc|
    doc.xpath('//w:p').filter_map do |para|
      texte = para.xpath('.//w:t').map(&:text).join.strip
      next if texte.empty?

      { texte: texte, retrait: para.at_xpath('.//w:ind')&.[]('w:left') }
    end
  end

  context 'avec la valeur réelle d\'un référentiel phytosanitaire' do
    let(:markdown) do
      <<~MD
        1. Une des conditions suivantes :
           - Région exempte de *Cronartium* spp.
           - **OU** Semences certifiées exemptes
        2. **ET** Traitement thermique
      MD
    end

    it 'ne génère aucun <w:p> imbriqué' do
      expect(render(markdown).xpath('//w:p//w:p')).to be_empty
    end

    it 'ne génère aucune numérotation Word' do
      expect(render(markdown).xpath('//w:numPr')).to be_empty
    end

    it 'restitue les marqueurs de l\'auteur et deux niveaux de retrait' do
      expect(lines_of(render(markdown))).to eq(
        [
          { texte: '1. Une des conditions suivantes :', retrait: '360' },
          { texte: '- Région exempte de Cronartium spp.', retrait: '720' },
          { texte: '- OU Semences certifiées exemptes', retrait: '720' },
          { texte: '2. ET Traitement thermique', retrait: '360' }
        ]
      )
    end

    it 'conserve le gras' do
      expect(render(markdown).xpath('//w:b')).not_to be_empty
    end
  end

  it 'n\'écrase pas une numérotation ne commençant pas à 1' do
    expect(lines_of(render("3. troisième\n4. quatrième")).map { |l| l[:texte] })
      .to eq(['3. troisième', '4. quatrième'])
  end

  it 'restitue des marqueurs inconnus de Markdown' do
    expect(lines_of(render("1. Condition :\n   1a. cas A\n   1b. cas B")).map { |l| l[:texte] })
      .to eq(['1. Condition :', '1a. cas A', '1b. cas B'])
  end

  it 'accepte une imbrication de types instable' do
    doc = render("1. un\n   1. sous-numéroté\n   - puis une puce\n      • plus profond")
    expect(doc.xpath('//w:p//w:p')).to be_empty
    expect(lines_of(doc).map { |l| l[:retrait] }).to eq(%w[360 720 720 1080])
  end

  it 'laisse les titres devenir de vrais styles Word' do
    doc = render("- item\n## Titre")
    expect(doc.xpath('//w:pStyle').map { |s| s['w:val'] }).to include('Titre2')
  end
end
