# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Referentiel::ReferencePj do
  def champ(id_clair, fichiers: [double], padding: false, urlsafe: true)
    id = urlsafe ? Base64.urlsafe_encode64(id_clair, padding:) : Base64.strict_encode64(id_clair)
    double(id:, files: fichiers, __typename: 'PieceJustificativeChamp')
  end

  it 'compose la référence d\'un champ de la table principale' do
    expect(described_class.pour(686_128, champ('Champ-155122'))).to eq('md:686128:155122')
  end

  it 'ajoute le row_id pour un champ de bloc répétable' do
    expect(described_class.pour(686_128, champ('Champ-155122|01HZX3ABCD'))).to eq('md:686128:155122:01HZX3ABCD')
  end

  it 'retourne nil pour un champ vide' do
    expect(described_class.pour(686_128, champ('Champ-155122', fichiers: []))).to be_nil
  end

  it 'refuse un identifiant inattendu' do
    expect { described_class.pour(1, champ('Dossier-12')) }.to raise_error(ArgumentError)
  end

  it 'refuse un identifiant qui n\'est pas du Base64' do
    expect { described_class.pour(1, double(id: '***', files: [double])) }.to raise_error(ArgumentError)
  end

  it 'tolère le remplissage « = » et l\'alphabet standard' do
    attendu = 'md:686128:155122:01HZX3AB-D'
    expect(described_class.pour(686_128, champ('Champ-155122|01HZX3AB-D', padding: true))).to eq(attendu)
    expect(described_class.pour(686_128, champ('Champ-155122|01HZX3AB-D', urlsafe: false))).to eq(attendu)
  end
end
