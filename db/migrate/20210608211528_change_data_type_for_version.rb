class ChangeDataTypeForVersion < ActiveRecord::Migration[6.1]
  def self.up
    change_table :checks do |t|
      t.change :version, :bigint
    end
  end
  def self.down
    change_table :checks do |t|
      t.change :version, :float
    end
  end
end
