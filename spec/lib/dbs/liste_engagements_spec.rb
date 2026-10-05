# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::ListeEngagements do
  let(:tere) do
    described_class::Engagement.new(nom: 'Manutere TERE', email: 'manutere@exemple.pf', numero: 654_125,
                                    date: Date.new(2026, 9, 1), attendu: true)
  end
  let(:hoa) do
    described_class::Engagement.new(nom: 'Vaimiti HOA', email: 'vaimiti@exemple.pf', numero: 655_888,
                                    date: Date.new(2026, 9, 15), attendu: false)
  end

  describe '.format_recus / .parse_recus' do
    let(:texte) do
      "Manutere TERE (manutere@exemple.pf) — dossier 654125 — déposé le 01/09/2026\n" \
        'Vaimiti HOA (vaimiti@exemple.pf) — dossier 655888 — déposé le 15/09/2026 — non attendu'
    end

    it 'écrit une ligne par engagement, triée par numéro, avec la mention « non attendu »' do
      expect(described_class.format_recus([hoa, tere])).to eq texte
    end

    it 'relit exactement ce qu il a écrit' do
      expect(described_class.parse_recus(texte)).to eq [tere, hoa]
    end

    it 'ignore les lignes vides ou modifiées à la main et normalise le courriel en minuscules' do
      texte_sale = "\n#{texte.lines.first}  \nune note de l'agent\nJean (JEAN@Ex.PF) — dossier 1 — déposé le 02/02/2026\n"
      expect(described_class.parse_recus(texte_sale).map(&:email)).to eq ['manutere@exemple.pf', 'jean@ex.pf']
    end

    it 'ignore une ligne dont la date a la bonne forme mais n existe pas, sans perdre les autres' do
      texte_date_fausse = "Jean (jean@ex.pf) — dossier 1 — déposé le 30/02/2026\n#{texte.lines.first}"
      expect(described_class.parse_recus(texte_date_fausse).map(&:numero)).to eq [654_125]
    end

    it 'relit une ligne à nom vide ou à courriel vide, telle que format_recus peut l écrire' do
      sans_email = described_class::Engagement.new(nom: 'Vaimiti HOA', email: '', numero: 1, date: Date.new(2026, 9, 15), attendu: false)
      sans_nom = described_class::Engagement.new(nom: '', email: 'x@y.pf', numero: 2, date: Date.new(2026, 9, 16), attendu: true)
      expect(described_class.parse_recus(described_class.format_recus([sans_email, sans_nom]))).to eq [sans_email, sans_nom]
    end
  end

  describe '.upsert' do
    it 'remplace l engagement de même numéro et garde les autres' do
      tere2 = tere.dup.tap { |e| e.date = Date.new(2026, 9, 2) }
      expect(described_class.upsert([tere, hoa], tere2)).to contain_exactly(hoa, tere2)
    end
  end

  describe '.format_manquants' do
    let(:eleveurs) do
      [{ nom: 'Manutere TERE', email: 'Manutere@exemple.pf', telephone: '87 54 65 75' },
       { nom: 'Tehani MOU', email: 'tehani@exemple.pf', telephone: '' },
       { nom: 'Vaimiti HOA', email: 'vaimiti@exemple.pf', telephone: '88 65 25 62' }]
    end

    it 'liste les éleveurs sans engagement, avec leur téléphone, rapprochés par courriel sans la casse' do
      expect(described_class.format_manquants(eleveurs, [tere])).to eq(
        "Tehani MOU (tehani@exemple.pf)\nVaimiti HOA au 88 65 25 62 (vaimiti@exemple.pf)"
      )
    end

    it 'rend une chaîne vide quand tout le monde a signé' do
      expect(described_class.format_manquants(eleveurs, [tere, hoa, hoa.dup.tap { |e| e.email = 'tehani@exemple.pf' }])).to eq ''
    end
  end
end
