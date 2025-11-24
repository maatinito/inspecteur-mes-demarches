# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PublipostageV2 do
  describe '#champ_value expansion' do
    let(:publipostage) { PublipostageV2.new({}) }

    context 'with ReferentielDePolynesieChamp' do
      let(:referentiel_champ) do
        double('ReferentielDePolynesieChamp',
               __typename: 'ReferentielDePolynesieChamp',
               label: 'ICPE',
               string_value: 'ICPE-001',
               columns: [
                 double(name: 'section', value: 'A'),
                 double(name: 'rubrique', value: '2510'),
                 double(name: 'alinea', value: '1'),
                 double(name: 'classe', value: 'E'),
                 double(name: 'date_autorisation', value: '2024-01-15')
               ])
      end

      it 'expands the main value and all columns' do
        result = publipostage.send(:champ_value, referentiel_champ)

        expect(result).to be_a(Hash)
        expect(result['']).to eq('ICPE-001')
        expect(result['.section']).to eq('A')
        expect(result['.rubrique']).to eq(2510) # Converted to integer
        expect(result['.alinea']).to eq(1) # Converted to integer
        expect(result['.classe']).to eq('E')
        expect(result['.date_autorisation']).to be_a(Date)
        expect(result['.date_autorisation'].to_s).to eq('2024-01-15')
      end

      it 'handles empty columns' do
        referentiel_champ.columns[1] = double(name: 'rubrique', value: '')
        result = publipostage.send(:champ_value, referentiel_champ)

        expect(result['.rubrique']).to eq('')
      end

      it 'handles missing columns' do
        allow(referentiel_champ).to receive(:columns).and_return(nil)
        result = publipostage.send(:champ_value, referentiel_champ)

        expect(result).to eq({ '' => 'ICPE-001' })
      end
    end

    context 'with NumeroDnChamp' do
      let(:numero_dn_champ) do
        double('NumeroDnChamp',
               __typename: 'NumeroDnChamp',
               label: 'DN',
               numero_dn: '123456',
               date_de_naissance: '1990-05-15')
      end

      it 'expands numero DN with sub-properties' do
        result = publipostage.send(:champ_value, numero_dn_champ)

        expect(result).to be_a(Hash)
        expect(result['']).to eq('123456|1990-05-15')
        expect(result['.numero_dn']).to eq('123456')
        expect(result['.date_de_naissance']).to eq('1990-05-15')
      end

      it 'handles nil values' do
        allow(numero_dn_champ).to receive(:numero_dn).and_return(nil)
        allow(numero_dn_champ).to receive(:date_de_naissance).and_return(nil)

        result = publipostage.send(:champ_value, numero_dn_champ)

        expect(result['']).to eq('|')
        expect(result['.numero_dn']).to eq('')
        expect(result['.date_de_naissance']).to eq('')
      end
    end

    context 'with CommuneDePolynesieChamp' do
      let(:commune_champ) do
        double('CommuneDePolynesieChamp',
               __typename: 'CommuneDePolynesieChamp',
               label: 'Commune',
               string_value: 'Papeete',
               commune: double(
                 name: 'Papeete',
                 postal_code: 98_714,
                 island: 'Tahiti',
                 archipelago: 'Société'
               ))
      end

      it 'expands commune with all properties' do
        result = publipostage.send(:champ_value, commune_champ)

        expect(result).to be_a(Hash)
        expect(result['']).to eq('Papeete')
        expect(result['.name']).to eq('Papeete')
        expect(result['.postalCode']).to eq(98_714)
        expect(result['.island']).to eq('Tahiti')
        expect(result['.archipelago']).to eq('Société')
      end

      it 'handles missing commune object' do
        allow(commune_champ).to receive(:commune).and_return(nil)

        result = publipostage.send(:champ_value, commune_champ)

        expect(result).to eq({ '' => 'Papeete' })
      end
    end

    context 'with CodePostalDePolynesieChamp' do
      let(:code_postal_champ) do
        double('CodePostalDePolynesieChamp',
               __typename: 'CodePostalDePolynesieChamp',
               label: 'Code Postal',
               string_value: '98714 - Papeete',
               commune: double(
                 name: 'Papeete',
                 postal_code: 98_714,
                 island: 'Tahiti',
                 archipelago: 'Société'
               ))
      end

      it 'expands code postal with all properties' do
        result = publipostage.send(:champ_value, code_postal_champ)

        expect(result).to be_a(Hash)
        expect(result['']).to eq('98714 - Papeete')
        expect(result['.name']).to eq('Papeete')
        expect(result['.postalCode']).to eq(98_714)
        expect(result['.island']).to eq('Tahiti')
        expect(result['.archipelago']).to eq('Société')
      end
    end

    context 'with RepetitionChamp containing expanded fields' do
      let(:repetition_champ) do
        rubrique1 = double('ReferentielDePolynesieChamp',
                           __typename: 'ReferentielDePolynesieChamp',
                           label: 'Rubrique',
                           string_value: 'R1',
                           columns: [
                             double(name: 'section', value: 'A'),
                             double(name: 'classe', value: 'E')
                           ])

        volume1 = double('IntegerNumberChamp',
                         __typename: 'IntegerNumberChamp',
                         label: 'Volume',
                         value: 100)

        double('Repetition', champs: [rubrique1, volume1])

        double('RepetitionChamp',
               __typename: 'RepetitionChamp',
               label: 'ICPE')
      end

      before do
        allow(publipostage).to receive(:bloc_to_rows).and_return([
                                                                   double('Repetition', champs: [
                                                                            double('ReferentielDePolynesieChamp',
                                                                                   __typename: 'ReferentielDePolynesieChamp',
                                                                                   label: 'Rubrique',
                                                                                   string_value: 'R1',
                                                                                   columns: [
                                                                                     double(name: 'section', value: 'A'),
                                                                                     double(name: 'classe', value: 'E')
                                                                                   ]),
                                                                            double('IntegerNumberChamp',
                                                                                   __typename: 'IntegerNumberChamp',
                                                                                   label: 'Volume',
                                                                                   value: 100)
                                                                          ])
                                                                 ])

        # Mock the super call for IntegerNumberChamp
        allow(publipostage).to receive(:graphql_champ_value) do |champ|
          champ.value if champ.__typename == 'IntegerNumberChamp'
        end
      end

      it 'expands fields within repetition blocks' do
        result = publipostage.send(:champ_value, repetition_champ)

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)

        row = result.first
        expect(row).to be_a(Hash)
        expect(row['Rubrique']).to eq('R1')
        expect(row['Rubrique.section']).to eq('A')
        expect(row['Rubrique.classe']).to eq('E')
        expect(row['Volume']).to eq(100)
      end
    end
  end

  describe '#convert_column_value' do
    let(:publipostage) { PublipostageV2.new({}) }

    it 'converts French date format' do
      result = publipostage.send(:convert_column_value, '15/01/2024')
      expect(result).to be_a(Date)
      expect(result.day).to eq(15)
      expect(result.month).to eq(1)
    end

    it 'converts boolean values' do
      expect(publipostage.send(:convert_column_value, 'true')).to be true
      expect(publipostage.send(:convert_column_value, 'vrai')).to be true
      expect(publipostage.send(:convert_column_value, 'false')).to be false
      expect(publipostage.send(:convert_column_value, 'faux')).to be false
    end

    it 'converts numbers' do
      expect(publipostage.send(:convert_column_value, '42')).to eq(42)
      expect(publipostage.send(:convert_column_value, '42.5')).to eq(42.5)
    end

    it 'returns nil for nil' do
      expect(publipostage.send(:convert_column_value, nil)).to be_nil
    end
  end
end
